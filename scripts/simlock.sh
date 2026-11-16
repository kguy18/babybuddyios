# Sourced by scripts/ui-test.sh and scripts/unit-test.sh. When simlock
# (https://github.com/callstackincubator/simlock) is installed, they lease a fresh, booted simulator
# from it instead of creating, erasing and booting one of their own, so agents running tests side by
# side each get their own device and the Mac never boots more of them than simlock allows. CI has no
# simlock and keeps the named-device path; UI_TEST_NO_SIMLOCK=1 forces that path locally too.

simlock_wanted() {
  [ -z "${CI:-}" ] && [ -z "${UI_TEST_NO_SIMLOCK:-}" ] && command -v simlock >/dev/null
}

# simlock_lease <model> <os> leases a slim simulator and releases it when the script exits. It sets
#   UDID           the device, booted and never used before: don't erase it, which also undoes slim
#   SIMCTL         the simctl to reach it with
#   DEVICE_SET     simlock's own device set, or empty when simlock keeps devices in Xcode's
#   XCODEBUILD_SET the extra xcodebuild argument that finds a device in DEVICE_SET
#
# Slim mode stops the simulator's background services, by category. Four stay running:
#   widgets  liveactivitiesd and chronod: Live Activity tests fail without them
#   siri     siriactionsd, and
#   other    linkd: without these two the Live Activity's Stop button, a LiveActivityIntent, does nothing
#   store    StoreKit, for the tip jar
# A slim iPhone 17 Pro takes about 1.8 GB and a slim iPhone Duo 1.25 GB, against 4 GB and 2.7 GB stock.
simlock_lease() {
  local err out fields
  err=$(mktemp)
  echo "leasing an $1 on iOS $2 from simlock"
  out=$(simlock lease --platform ios --device "$1" --os "$2" --mode slim \
    --except widgets,store,siri,other --detach --ttl 2h --timeout 15m 2>"$err" | tail -n 1) || true
  # A failure prints {"error":{"code":...,"message":...}} on stderr and nothing on stdout.
  fields=$(python3 -c '
import json, sys
try:
    grant = json.loads(sys.argv[1])
    print(grant["device"]["address"], grant["lease"]["id"],
          grant.get("environment", {}).get("SIMLOCK_IOS_DEVICE_SET", ""), sep="\t")
except (ValueError, KeyError):
    lines = [l for l in open(sys.argv[2]).read().splitlines() if "\"error\"" in l]
    try:
        e = json.loads(lines[-1])["error"]
        sys.exit("::error::simlock lease failed: {} ({})".format(e["message"], e["code"]))
    except (IndexError, ValueError, KeyError):
        sys.exit("::error::simlock lease failed:\n" + open(sys.argv[2]).read())
' "$out" "$err") || { rm -f "$err"; exit 1; }
  rm -f "$err"
  IFS=$'\t' read -r UDID LEASE_ID DEVICE_SET <<<"$fields"
  trap 'simlock release "$LEASE_ID" >/dev/null || echo "::warning::could not release simlock lease $LEASE_ID"' EXIT
  echo "leased $UDID ($LEASE_ID)"
  SIMCTL=(simlock simctl)
  XCODEBUILD_SET=()
  if [ -n "$DEVICE_SET" ]; then
    XCODEBUILD_SET=(-DVTSimulatorSetLocation="$DEVICE_SET")
  fi
}
