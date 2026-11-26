#!/usr/bin/env bash
# Runs a command with this repo's 1Password Environments loaded.
#
#   scripts/op-run.sh <command> [arguments]
#
# The Environment IDs come from $OP_ENVIRONMENT_IDS (separated by spaces; a
# repo that keeps its IDs out of git sets it from CI variables), or else from
# .op-environment, one ID per line. Never prints a value.
set -euo pipefail
ids="${OP_ENVIRONMENT_IDS:-}"
[ -n "${ids//[[:space:]]/}" ] || ids="$(cat "$(dirname "$0")/../.op-environment" 2>/dev/null || true)"
flags=()
for id in $ids; do flags+=(--environment "$id"); done
if [ ${#flags[@]} -eq 0 ]; then
  echo "error: no Environment ID. Put it in .op-environment (1Password app → Developer → Environments → Manage → Copy environment ID)." >&2
  exit 1
fi
command -v op >/dev/null || { echo "error: 1Password CLI not installed (brew install --cask 1password-cli@beta)" >&2; exit 1; }
exec op run "${flags[@]}" -- "$@"
