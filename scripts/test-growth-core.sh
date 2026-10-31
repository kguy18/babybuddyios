#!/bin/sh
# Run actual Foundation-only growth sources with a standalone assertion harness.
# XCTest, SwiftUI Charts, SwiftData and the iOS app still require full Xcode.
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/babybuddy-growth.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
mkdir -p "$scratch/modules"
cp "$repo/scripts/GrowthCoreChecks.swift" "$scratch/main.swift"
swiftc -module-cache-path "$scratch/modules" \
    "$repo/Sources/Shared/Growth/GrowthSeries.swift" \
    "$repo/Sources/Shared/Growth/GrowthProfile.swift" \
    "$repo/Sources/Features/Insights/Growth/WHOGrowthReference.swift" \
    "$repo/Sources/Features/Insights/Growth/GrowthText.swift" \
    "$scratch/main.swift" -o "$scratch/growth-checks"
"$scratch/growth-checks" "$repo/Sources/Resources/who-growth-reference.json"
