#!/bin/sh
# Pre-build guard, run by Xcode before every build of the app target (see project.yml).
#
# 1. The signing team must be the paid Apple Developer Program team. Two teams on this Mac show
#    as "Kurtis Guy"; the other one cannot use paid capabilities, and iOS refuses to update an
#    installed app across a team change. A fork sets EXPECTED_TEAM to its own team, alongside
#    DEVELOPMENT_TEAM in project.yml (see Docs/DEVELOPMENT.md).
# 2. A Release build on that team must carry every build-time secret. They come from
#    Config/Secrets.xcconfig, which is gitignored, and BabyBuddy.xcconfig includes it with
#    `#include?`, so a missing file used to pass silently: 1.1.0 shipped with no RevenueCat key
#    and no analytics. Debug builds, CI and forks are not held to this.
set -u
EXPECTED_TEAM="547DWTTFY6"
status=0

if [ "${DEVELOPMENT_TEAM:-}" != "$EXPECTED_TEAM" ]; then
  echo "error: DEVELOPMENT_TEAM is '${DEVELOPMENT_TEAM:-}', expected $EXPECTED_TEAM. Fix the team in project.yml (or EXPECTED_TEAM in scripts/guard-build.sh for a fork)."
  status=1
fi

if [ "${CONFIGURATION:-}" = "Release" ] && [ "${DEVELOPMENT_TEAM:-}" = "$EXPECTED_TEAM" ]; then
  for key in REVENUECAT_API_KEY TELEMETRYDECK_APP_ID TELEMETRYDECK_SALT; do
    eval "value=\${$key:-}"
    if [ -z "$value" ]; then
      echo "error: $key is empty in a Release build. Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig and fill it in; an archive from a fresh worktree needs the file copied in."
      status=1
    fi
  done
fi

exit $status
