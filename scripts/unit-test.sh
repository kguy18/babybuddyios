#!/usr/bin/env bash
# Runs the unit tests (scheme BabyBuddy) on a simulator leased from simlock (scripts/simlock.sh), or
# on the iPhone 17 Pro of the newest runtime when simlock is missing or UI_TEST_NO_SIMLOCK=1. Extra
# xcodebuild arguments pass straight through. CI runs its own xcodebuild step, not this script.
#
#   scripts/unit-test.sh
#   scripts/unit-test.sh -only-testing:BabyBuddyTests/ActivityForecastTests
set -euo pipefail
cd "$(dirname "$0")/.."
XCODEBUILD_SET=()
source scripts/simlock.sh
if simlock_wanted; then
  simlock_lease "iPhone 17 Pro" 26.5
  DESTINATION="id=$UDID"
else
  DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro"
fi
xcodebuild -project BabyBuddy.xcodeproj -scheme BabyBuddy -destination "$DESTINATION" \
  ${XCODEBUILD_SET[@]+"${XCODEBUILD_SET[@]}"} test CODE_SIGNING_ALLOWED=NO -quiet "$@"
