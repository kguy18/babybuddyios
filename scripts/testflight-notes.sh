#!/usr/bin/env bash
# Prints TestFlight's What to Test for the PRs merged after an instant. For
# each PR, newest first: its title, then the bullets of its `## What to test`
# section as "- text". PRs labelled `internal` and PRs whose files all sit
# outside appstore.json's appDir are left out. The text fits TestFlight's
# 4000 characters by dropping the oldest PRs whole, and reads "Small fixes
# and polish." when nothing is left. `asc.mjs what-to-test` does the work.
#
# `since` is the previous upload's time (`asc.mjs last-upload`). Without it,
# the newest v tag's commit, then the newest build/* tag's commit, then the
# beginning of history.
#
#   scripts/testflight-notes.sh [since-iso-8601]
#   scripts/testflight-notes.sh 2026-09-23T11:25:00Z   # what the next build would say
set -euo pipefail
cd "$(dirname "$0")/.."
SINCE="${1:-}"
if [ -z "$SINCE" ]; then
  PREV="$(git tag --list 'v*' --sort=-v:refname | head -1)"
  [ -n "$PREV" ] || PREV="$(git tag --list 'build/*' --sort=-committerdate | head -1)"
  SINCE="$( [ -n "$PREV" ] && git log -1 --format=%cI "$PREV" || echo 1970-01-01T00:00:00Z )"
fi

# Filtered by merge time in asc.mjs rather than with --search, which some gh
# versions reject with "invalid character '{'".
gh pr list --state merged --limit 200 --json number,title,body,labels,mergedAt,files \
  | node scripts/asc.mjs what-to-test "$SINCE"
