#!/usr/bin/env bash
# Runs the XCUITest suite (scheme BabyBuddyUITests) on a simulator of its own. Same command CI runs;
# extra xcodebuild arguments pass straight through.
#
# With simlock installed (scripts/simlock.sh), and outside CI, the run leases a fresh slim simulator
# from it and releases it at the end: an iPhone 17 Pro, or an iPhone Duo for --duo-open. What follows
# about a named device, erased, booted and shut down around every run, is the path without simlock,
# which CI takes.
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
# With UI_TEST_DUO_ROTATE=portrait it turns the open display on its side first, the way people
# hold it, which FoldTests that need it check for and the rest skip.
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

SIMCTL=(xcrun simctl)
XCODEBUILD_SET=()
source scripts/simlock.sh
if simlock_wanted; then
  if [ -n "$DUO_OPEN" ]; then
    simlock_lease "iPhone Duo" 27.2
    # duoctl looks for the simulator in Xcode's device set only.
    if [ -n "$DEVICE_SET" ]; then
      echo "::error::simlock keeps its devices in a set of its own, where duoctl can't reach them; run \`simlock config set drivers.ios.deviceSet default\` (AGENTS.md, Simulators)" >&2
      exit 1
    fi
  else
    simlock_lease "iPhone 17 Pro" 26.5
  fi
else
# No simlock, as on CI: find or create the named device, then erase and boot it. Left unindented so
# this path reads as it did before simlock.
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
fi

if [ -n "$DUO_OPEN" ]; then
  export DUOCTL_UDID="$UDID"
  # Unfold, then check the inner screen took over: duoctl drives private simulator interfaces, and
  # a run that stayed on the front display would only skip FoldTests.
  mkdir -p build
  unfold() {
    scripts/duoctl open \
      && scripts/duoctl state | python3 -c 'import json, sys; sys.exit(json.load(sys.stdin)["activeScreen"] != "inner")'
  }
  # Straight after bootstatus, duoctl sometimes answers "no display is active (is the simulator
  # still booting?)": SpringBoard isn't up yet. On CI one retry after 15 s was once enough and once
  # not (still no display 30 s on), so keep trying for two minutes.
  # duoctl reads the active screen from devicectl; print what devicectl and launchd report.
  displays() {
    xcrun devicectl device info displays -d "$UDID" --json-output - 2>/dev/null | python3 -c '
import json, sys
for d in json.load(sys.stdin)["result"]["displays"]:
    print("  {}: active={} backlight={}".format(d.get("name"), d.get("active"), d.get("backlightState")))' || true
    xcrun simctl spawn "$UDID" launchctl list | grep -E 'SpringBoard|backboardd' || true
  }
  for ATTEMPT in 1 2 3 4 5 6 7 8; do
    unfold && break
    displays
    if [ "$ATTEMPT" = 8 ]; then
      scripts/duoctl screenshot build/duo-open.png || xcrun simctl io "$UDID" screenshot build/duo-open.png || true
      echo "::error::duoctl open left the iPhone Duo on its front display"
      exit 1
    fi
    # A boot that still has no active screen a minute on doesn't recover by waiting; boot it again.
    if [ "$ATTEMPT" = 4 ]; then
      echo "no active screen after attempt 4; rebooting the iPhone Duo"
      xcrun simctl shutdown "$UDID"
      xcrun simctl boot "$UDID"
      xcrun simctl bootstatus "$UDID" -b >/dev/null
      continue
    fi
    echo "duoctl open didn't take (attempt $ATTEMPT of 8); trying again in 15 s"
    sleep 15
  done
  # UI_TEST_DUO_ROTATE=portrait turns the open display on its side for the run, fold across it.
  # XCUIDevice can't: the app is portrait-locked, and only the system turns it there.
  if [ -n "${UI_TEST_DUO_ROTATE:-}" ]; then scripts/duoctl rotate "$UI_TEST_DUO_ROTATE"; fi
fi

# A Duo shard's first test paid the simulator's cold start on top of its own waits. With a
# prebuilt app at hand, launch it once so its frameworks, WebKit among them, are warm before
# xcodebuild's first launch. The tests reinstall it and BB_UITEST wipes what this launch wrote.
if [ -n "${UI_TEST_XCTESTRUN:-}" ]; then
  APP="$(dirname "$UI_TEST_XCTESTRUN")/Debug-iphonesimulator/BabyBuddy.app"
  if [ -d "$APP" ]; then
    "${SIMCTL[@]}" install "$UDID" "$APP"
    SIMCTL_CHILD_BB_UITEST=1 "${SIMCTL[@]}" launch "$UDID" com.kurtisguy.BabyBuddy >/dev/null
    sleep 10
    "${SIMCTL[@]}" terminate "$UDID" com.kurtisguy.BabyBuddy >/dev/null 2>&1 || true
  else
    echo "no prebuilt app beside $UI_TEST_XCTESTRUN; skipping the warm-up launch"
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
if [ -n "${UI_TEST_XCTESTRUN:-}" ] || [ -n "$DUO_OPEN" ] \
  || "${SIMCTL[@]}" list devices "$UDID" --json | grep -q '"deviceTypeIdentifier" : ".*Duo"'; then
  ALLOWANCE=(-default-test-execution-time-allowance 420 -maximum-test-execution-time-allowance 600)
else
  ALLOWANCE=(-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 300)
fi
xcodebuild "${BUILD[@]}" -destination "id=$UDID" ${XCODEBUILD_SET[@]+"${XCODEBUILD_SET[@]}"} \
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

# CI passes -retry-tests-on-failure -test-iterations 2, and a test that passes on its second
# attempt counts as passed: a flaky test hides behind a green run. List those here and, in CI, in
# the job's step summary. A retry never fails the run.
xcrun xcresulttool get test-results tests --path "$RESULT" --compact | python3 -c '
import json, os, sys
retried = []
def walk(node, suite=None):
    kind = node.get("nodeType")
    if kind == "Test Suite":
        suite = node.get("name")
    elif kind == "Test Case":
        runs = [c for c in node.get("children", []) if c.get("nodeType") == "Repetition"]
        results = {run.get("result") for run in runs}
        if "Failed" in results and "Passed" in results:
            attempts = ", ".join("{} {}".format(run.get("name"), run.get("result").lower()) for run in runs)
            retried.append("{}/{}: {}".format(suite, node.get("name"), attempts))
    for child in node.get("children", []):
        walk(child, suite)
for node in json.load(sys.stdin)["testNodes"]:
    walk(node)
if retried:
    print(f"Retried tests: {len(retried)} passed only on a later attempt")
    for line in retried:
        print("  RETRY " + line)
    print(f"::warning::{len(retried)} UI tests passed only on a retry; see the step summary")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write("### Retried tests\n\n" + "".join(f"- {line}\n" for line in retried) + "\n")
' || echo "::warning::could not read the result bundle for retried tests"
exit $STATUS
