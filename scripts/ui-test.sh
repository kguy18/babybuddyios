#!/usr/bin/env bash
# Runs the XCUITest suite (scheme BabyBuddyUITests) on a dedicated simulator that is erased,
# booted, and shut down again around every run. Same command CI runs; extra xcodebuild arguments
# pass straight through.
#
#   scripts/ui-test.sh [xcodebuild args]
#   scripts/ui-test.sh -only-testing:BabyBuddyUITests/DialogTests/testSignOutCard
#   UI_TEST_DEVICE=CI-BabyBuddy scripts/ui-test.sh -retry-tests-on-failure -test-iterations 2
#
# Erasing covers what the app's own per-launch reset (BB_UITEST, see UITests/UITestCase.swift)
# can't: notification permission, the alternate app icon, Live Activities, delivered banners.
#
# The device is named "BabyBuddy UI Tests" ($UI_TEST_DEVICE to change), never "iPhone…", so no
# other script or human picks it — a foreign launch kills a UI run. It is an iPhone 17 Pro on the
# newest iOS runtime installed when it was created: the suite needs iOS 26+.
#
#   scripts/ui-test.sh --server [xcodebuild args]
#
# --server is the second lane: `ServerTests` against the demo Baby Buddy server, which is the only
# way to check that what the app queues actually reaches a server. It takes the server's address and
# the CI user's token from the environment (CI passes the repo secrets BB_E2E_SERVER_URL and
# BB_E2E_TOKEN) or, locally, from the login keychain items `babybuddy-e2e-url` and
# `babybuddy-e2e-token`, and hands them to the runner as TEST_RUNNER_ variables — environment,
# never a file, never printed. The keyless lane skips those tests entirely.
#
#   scripts/ui-test.sh --duo-open [xcodebuild args]
#
# --duo-open runs on iPhone Duo's open display: a device named "BabyBuddy UI Tests Duo", cloned from
# an installed iPhone Duo, unfolded with scripts/duoctl after it boots. XCUITest can't unfold it, and
# FoldTests skip unless the display is open. It runs FoldTests and SmokeTests unless the arguments
# name tests of their own, and on a failure saves what the open display showed to build/duo-open.png.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${UI_TEST_DEVICE:-BabyBuddy UI Tests}"
RESULT=build/UITests.xcresult
DUO_OPEN=""
# The server tests are their own lane: they sign in for real, so they don't belong in a run that is
# meant to need nothing but the simulator.
LANE=(-skip-testing:BabyBuddyUITests/ServerTests -skip-testing:BabyBuddyUITests/ScreenshotTests)

if [ "${1:-}" = "--server" ]; then
  shift
  RESULT=build/UITests-server.xcresult
  LANE=(-only-testing:BabyBuddyUITests/ServerTests)
  : "${BB_E2E_SERVER_URL:=$(security find-generic-password -s babybuddy-e2e-url -w 2>/dev/null || true)}"
  : "${BB_E2E_TOKEN:=$(security find-generic-password -s babybuddy-e2e-token -w 2>/dev/null || true)}"
  if [ -z "$BB_E2E_SERVER_URL" ] || [ -z "$BB_E2E_TOKEN" ]; then
    echo "::error::BB_E2E_SERVER_URL / BB_E2E_TOKEN are unset — repo secrets in CI, keychain items locally (CLAUDE.md ▸ UI tests)" >&2
    exit 1
  fi
  # xcodebuild hands TEST_RUNNER_-prefixed variables to the test runner, prefix stripped.
  export TEST_RUNNER_BB_E2E_SERVER_URL="$BB_E2E_SERVER_URL"
  export TEST_RUNNER_BB_E2E_TOKEN="$BB_E2E_TOKEN"
elif [ "${1:-}" = "--duo-open" ]; then
  shift
  DUO_OPEN=1
  DEVICE="${UI_TEST_DEVICE:-BabyBuddy UI Tests Duo}"
  RESULT=build/UITests-duo-open.xcresult
  case " $* " in
    *" -only-testing"*) ;;
    *) LANE+=(-only-testing:BabyBuddyUITests/FoldTests -only-testing:BabyBuddyUITests/SmokeTests) ;;
  esac
fi

UDID=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["name"] == sys.argv[1]:
            print(d["udid"]); sys.exit()
' "$DEVICE")
if [ -z "$UDID" ] && [ -n "$DUO_OPEN" ]; then
  # The Duo's device type and runtime, from whichever iPhone Duo Xcode installed.
  read -r TYPE RUNTIME < <(xcrun simctl list devices available --json | python3 -c '
import json, sys
for rt, ds in sorted(json.load(sys.stdin)["devices"].items(), reverse=True):
    for d in ds:
        if d["name"].startswith("iPhone Duo"):
            print(d["deviceTypeIdentifier"], rt); sys.exit()
sys.exit("no iPhone Duo simulator installed: Xcode 27.1 or later ships one")')
  UDID=$(xcrun simctl create "$DEVICE" "$TYPE" "$RUNTIME")
  echo "created simulator '$DEVICE' ($UDID)"
elif [ -z "$UDID" ]; then
  RUNTIME=$(xcrun simctl list runtimes available --json | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS"]
rts.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(rts[-1]["identifier"])')
  UDID=$(xcrun simctl create "$DEVICE" "iPhone 17 Pro" "$RUNTIME")
  echo "created simulator '$DEVICE' ($UDID)"
fi

trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true' EXIT
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
xcrun simctl erase "$UDID"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null

if [ -n "$DUO_OPEN" ]; then
  export DUOCTL_UDID="$UDID"
  # Unfold, then check the inner screen took over: duoctl drives private simulator interfaces, and
  # a run that stayed on the front display would only skip FoldTests.
  mkdir -p build
  unfold() {
    scripts/duoctl open \
      && scripts/duoctl state | python3 -c 'import json, sys; sys.exit(json.load(sys.stdin)["activeScreen"] != "inner")'
  }
  # Once in CI, straight after bootstatus, duoctl answered "no display is active (is the simulator
  # still booting?)": SpringBoard wasn't up yet. One more try after a pause covers that.
  if ! unfold; then
    echo "duoctl open didn't take; trying once more in 15 s"
    sleep 15
    if ! unfold; then
      scripts/duoctl screenshot build/duo-open.png || true
      echo "::error::duoctl open left the iPhone Duo on its front display"
      exit 1
    fi
  fi
fi

rm -rf "$RESULT"
set +e
# Unsigned on purpose: the store and the keychain both fall back to app-only locations without the
# App Group entitlement, which is all an in-app UI test touches.
# Time allowances so a hung test fails itself rather than the run: a demo test takes ~30 s, and a
# server one ~2 min (it signs in, then waits on the app's own sync). On an iPhone Duo (CI's
# xcode-27 preview image) a test takes 40 s to 2 min, and one slow wait pushed a retry past 300 s,
# so that lane gets 420 and 600.
# UI_TEST_XCTESTRUN runs tests already built with `build-for-testing` instead of building them, as
# CI's iPhone Duo shards do with the one build they share.
if [ -n "${UI_TEST_XCTESTRUN:-}" ]; then
  BUILD=(-xctestrun "$UI_TEST_XCTESTRUN" test-without-building)
else
  BUILD=(-project BabyBuddy.xcodeproj -scheme BabyBuddyUITests test)
fi
if [ -n "${UI_TEST_XCTESTRUN:-}" ] || xcrun simctl list devices "$UDID" --json | grep -q '"deviceTypeIdentifier" : ".*Duo"'; then
  ALLOWANCE=(-default-test-execution-time-allowance 420 -maximum-test-execution-time-allowance 600)
else
  ALLOWANCE=(-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 300)
fi
xcodebuild "${BUILD[@]}" -destination "id=$UDID" \
  -resultBundlePath "$RESULT" \
  -test-timeouts-enabled YES "${ALLOWANCE[@]}" \
  CODE_SIGNING_ALLOWED=NO -quiet "${LANE[@]}" "$@"
STATUS=$?
set -e
if [ -n "$DUO_OPEN" ] && [ "$STATUS" -ne 0 ]; then
  scripts/duoctl state || true
  scripts/duoctl screenshot build/duo-open.png || true
fi

# -quiet hides the totals, and would hide an empty -only-testing filter passing with zero tests.
[ -d "$RESULT" ] || { echo "::error::no result bundle — the build failed before any test ran"; exit 1; }
xcrun xcresulttool get test-results summary --path "$RESULT" --format json | python3 -c '
import json, sys
s = json.load(sys.stdin)
total, passed, failed, skipped = s["totalTestCount"], s["passedTests"], s["failedTests"], s["skippedTests"]
print(f"UI tests: {passed} passed, {failed} failed, {skipped} skipped (of {total})")
for t in s.get("testFailures", []):
    print("  FAIL {}: {}".format(t.get("testName"), t.get("failureText")))
# A skip is how the server lane reports an unreachable server, and how a test that leaves the app
# sits out on iPhone Duo, and how FoldTests sit out anywhere but the open display: green, but with
# coverage missing, so it has to be visible on the run rather than buried in this line.
if skipped:
    print(f"::warning::{skipped} UI tests skipped: the demo server unreachable or not configured, tests that leave the app on iPhone Duo, or FoldTests off the open display")
if total == 0:
    print("::error::zero UI tests ran — check the -only-testing filter"); sys.exit(1)
# On the open display nothing should skip: a skip there means a test misread the display.
if skipped and sys.argv[1]:
    print("::error::UI tests skipped on the open display"); sys.exit(1)
' "$DUO_OPEN" || exit 1
exit $STATUS
