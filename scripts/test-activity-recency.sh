#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/babybuddy-recency.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
cp "$repo/scripts/ActivityRecencyChecks.swift" "$scratch/main.swift"
swiftc -module-cache-path "$scratch/modules" "$repo/Sources/Shared/ActivityRecency.swift" \
    "$scratch/main.swift" -o "$scratch/checks"
"$scratch/checks"
