#!/usr/bin/env bash
# Require the latest aggregate CI check for this exact source commit.
set -euo pipefail
sha="${1:?Usage: require_ci.sh COMMIT [--wait]}"
repo="${GH_REPO:?Set GH_REPO to owner/repository}"
wait_mode="${2:-}"
deadline=$((SECONDS + 4800))
while true; do
  result="$(gh api "repos/$repo/actions/workflows/ci.yml/runs" \
    -f head_sha="$sha" -f per_page=1 --method GET \
    --jq '.workflow_runs | first | if . == null then "missing" elif .status != "completed" then "pending" else .conclusion end')"
  if [[ "$result" == success ]]; then
    result="$(gh api "repos/$repo/commits/$sha/check-runs" \
    -f check_name=swift-test -f filter=latest -f per_page=100 --method GET \
    --jq '.check_runs | sort_by(.started_at) | last | if . == null then "missing" elif .status != "completed" then "pending" else .conclusion end')"
  fi
  if [[ "$result" == success ]]; then
    echo "Required CI passed for $sha."
    exit 0
  fi
  if [[ "$wait_mode" != --wait || ( "$result" != pending && "$result" != missing ) || $SECONDS -ge $deadline ]]; then
    echo "Required CI for $sha is $result; release blocked." >&2
    exit 1
  fi
  sleep 30
done
