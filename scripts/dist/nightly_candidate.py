#!/usr/bin/env python3
"""Select an eligible master commit only when it has no published nightly."""
import datetime
import json
import os
from pathlib import Path
import re
import subprocess


def gh(*args):
    return subprocess.check_output(["gh", *args], text=True)


def releases():
    pages = json.loads(gh("api", f"repos/{os.environ['GH_REPO']}/releases", "--paginate", "--slurp"))
    return [release for page in pages for release in page]


def skip_candidate(reason):
    print(reason)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write("changed=false\n")


if __name__ == "__main__":
    version = Path(".github/release-version").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or version == "0.0.0":
        raise SystemExit("Invalid .github/release-version")
    source_sha = os.environ.get("SOURCE_SHA", "").strip()
    if source_sha and not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise SystemExit("Invalid source SHA from completed CI run")
    if source_sha:
        associated_prs = json.loads(
            gh("api", f"repos/{os.environ['GH_REPO']}/commits/{source_sha}/pulls")
        )
        merged_to_master = any(
            pr.get("base", {}).get("ref") == "master" and pr.get("merged_at")
            for pr in associated_prs
        )
        if not merged_to_master:
            skip_candidate(f"Skipping {source_sha}: CI commit is not associated with a merged PR into master.")
            raise SystemExit(0)
        is_ancestor = subprocess.run(
            ["git", "merge-base", "--is-ancestor", source_sha, "HEAD"], check=False
        ).returncode
        if is_ancestor != 0:
            raise SystemExit(f"CI commit {source_sha} is not reachable from master")
    # Match CI's docs/plans exclusions so a docs-only HEAD cannot stall
    # the exact-SHA gate. Include merge commits when their tree changes code.
    # For CI-triggered runs, select only the triggering merge SHA; do not let
    # later master commits replace the commit that just passed CI.
    sha = subprocess.check_output([
        "git", "log", "-1", "--first-parent", "--format=%H", source_sha or "HEAD", "--",
        ".", ":(exclude)docs/**", ":(exclude)plans/**",
    ], text=True).strip()
    if source_sha and sha != source_sha:
        skip_candidate(f"Skipping {source_sha}: the merged PR changed only CI-excluded docs or plans.")
        raise SystemExit(0)
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise SystemExit("No CI-eligible source commit found")
    prefix = f"v{version}-nightly."
    tag_pattern = re.compile(re.escape(prefix) + r"\d{8}\." + re.escape(sha[:12]))
    candidate_releases = [
        release for release in releases()
        if tag_pattern.fullmatch(release["tag_name"])
    ]
    published = any(
        release["prerelease"] and not release["draft"]
        for release in candidate_releases
    )
    drafts = [
        release for release in candidate_releases if release["draft"]
    ]
    if drafts:
        # A retry after midnight must resume the existing draft and tag.
        tag = max(drafts, key=lambda release: release.get("created_at", ""))["tag_name"]
    else:
        date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d")
        tag = f"{prefix}{date}.{sha[:12]}"
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"sha={sha}\nversion={version}\ntag={tag}\nchanged={str(not published).lower()}\n")
