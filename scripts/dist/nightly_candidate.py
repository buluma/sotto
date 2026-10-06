#!/usr/bin/env python3
"""Select master only when this version/commit has no published nightly."""
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


if __name__ == "__main__":
    version = Path(".github/release-version").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or version == "0.0.0":
        raise SystemExit("Invalid .github/release-version")
    # Match CI's docs/plans exclusions so a docs-only HEAD cannot stall
    # the exact-SHA gate. Include merge commits when their tree changes code.
    sha = subprocess.check_output([
        "git", "log", "-1", "--first-parent", "--format=%H", "HEAD", "--",
        ".", ":(exclude)docs/**", ":(exclude)plans/**",
    ], text=True).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise SystemExit("No CI-eligible source commit found")
    prefix = f"v{version}-nightly."
    published = any(
        release["prerelease"] and not release["draft"]
        and release["tag_name"].startswith(prefix)
        and release["tag_name"].endswith(f".{sha[:12]}")
        for release in releases()
    )
    date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d")
    tag = f"{prefix}{date}.{sha[:12]}"
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"sha={sha}\nversion={version}\ntag={tag}\nchanged={str(not published).lower()}\n")
