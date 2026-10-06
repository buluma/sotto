#!/usr/bin/env python3
"""Publish a verified DMG through a draft; never move an existing tag."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from nightly_candidate import gh, releases


def validate():
    channel = os.environ["RELEASE_CHANNEL"]
    version = os.environ["VERSION"]
    tag = os.environ["RELEASE_TAG"]
    sha = os.environ["BUILD_GIT_COMMIT"]
    if channel not in {"stable", "nightly"}:
        raise SystemExit("Invalid release channel")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or version == "0.0.0":
        raise SystemExit("Invalid numeric app version")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise SystemExit("Expected full commit SHA")
    expected = f"v{version}"
    if channel == "stable" and tag != expected:
        raise SystemExit("Stable tag does not match version")
    if channel == "nightly" and not re.fullmatch(re.escape(expected) + r"-nightly\.\d{8}\." + sha[:12], tag):
        raise SystemExit("Nightly tag does not match candidate")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if head != sha:
        raise SystemExit("Checkout is not the requested candidate")
    # fetch-depth: 0 includes existing release tags. Reject conflicting tags.
    existing = subprocess.run(["git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}"], capture_output=True, text=True)
    if existing.returncode == 0 and existing.stdout.strip() != sha:
        raise SystemExit("Existing release tag points to another commit")
    return channel, version, tag, sha


def publish():
    channel, version, tag, sha = validate()
    dmg = Path(f"dist/Sotto-{tag.removeprefix('v')}-arm64.dmg")
    checksum = Path(str(dmg) + ".sha256")
    expected = checksum.read_text().strip().split()
    with dmg.open("rb") as source:
        digest = hashlib.sha256()
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
        actual = digest.hexdigest()
    if expected != [actual, dmg.name]:
        raise SystemExit("DMG checksum mismatch")
    existing = next((r for r in releases() if r["tag_name"] == tag), None)
    if existing and not existing["draft"]:
        raise SystemExit("Release already published; refusing to replace assets")
    notes = f"Channel: {channel}\nApp version: {version}\nSource commit: {sha}\n\n"
    notes += "Native UI accepted on this commit.\n" if channel == "stable" else "Experimental nightly; native UI acceptance is pending.\n"
    notes_path = Path("ci-logs/release-notes.md")
    notes_path.write_text(notes)
    # Draft creation does not create a missing tag. Create it explicitly only
    # after successful packaging, and never update an existing reference.
    repo = os.environ["GH_REPO"]
    references = json.loads(gh("api", f"repos/{repo}/git/matching-refs/tags/{tag}"))
    reference = next((r["object"] for r in references if r["ref"] == f"refs/tags/{tag}"), None)
    if reference is None:
        reference = json.loads(gh("api", f"repos/{repo}/git/refs", "--method", "POST", "-f", f"ref=refs/tags/{tag}", "-f", f"sha={sha}"))["object"]
    while reference["type"] == "tag":
        reference = json.loads(gh("api", f"repos/{repo}/git/tags/{reference['sha']}"))["object"]
    if reference["type"] != "commit" or reference["sha"] != sha:
        raise SystemExit("Remote release tag does not match candidate")
    if not existing:
        gh("release", "create", tag, "--verify-tag", "--target", sha, "--draft", "--title", f"Sotto {'Nightly ' if channel == 'nightly' else ''}{tag}", "--notes-file", str(notes_path))
    gh("release", "upload", tag, str(dmg), str(checksum), "--clobber")
    attached = json.loads(gh("release", "view", tag, "--json", "assets"))["assets"]
    for path in (dmg, checksum):
        if not any(a["name"] == path.name and a["size"] == path.stat().st_size and a["state"] == "uploaded" for a in attached):
            raise SystemExit(f"Asset upload incomplete: {path.name}")
    gh("release", "edit", tag, "--draft=false", f"--prerelease={str(channel == 'nightly').lower()}", f"--latest={str(channel == 'stable').lower()}", "--notes-file", str(notes_path))
    if channel == "nightly":
        # Retain tags for traceability; remove only published nightly releases/assets.
        nightlies = sorted((r for r in releases() if r["prerelease"] and not r["draft"] and re.fullmatch(r"v\d+\.\d+\.\d+-nightly\.\d{8}\.[0-9a-f]{12}", r["tag_name"])), key=lambda r: r["published_at"], reverse=True)
        for release in nightlies[14:]:
            gh("release", "delete", release["tag_name"], "--yes")


if __name__ == "__main__":
    if sys.argv[1:] == ["--validate"]:
        validate()
    elif not sys.argv[1:]:
        publish()
    else:
        raise SystemExit("Usage: publish_release.py [--validate]")
