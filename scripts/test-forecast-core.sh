#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/babybuddy-forecast.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
mkdir -p "$scratch/modules"
cp "$repo/scripts/ForecastCoreChecks.swift" "$scratch/main.swift"
swiftc -module-cache-path "$scratch/modules" "$repo/Sources/Shared/Forecast/ActivityForecast.swift" \
    "$repo/Sources/Shared/Forecast/ForecastText.swift" "$scratch/main.swift" -o "$scratch/checks"
"$scratch/checks"
