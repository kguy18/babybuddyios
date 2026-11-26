#!/usr/bin/env bash
# Tests scripts/check-build.py against made-up app bundles. Needs python3 only.
#
#   scripts/check-build.test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export REPO_ROOT="$T"
echo '{"projectYml": "project.yml"}' > "$T/appstore.json"
printf 'REVENUECAT_API_KEY =\nSAME_NAME =\nUNUSED =\n#include? "Config.local.xcconfig"\n' > "$T/Config.xcconfig"
printf '      properties:\n        RevenueCatAPIKey: "$(REVENUECAT_API_KEY)"\n        CFBundleVersion: $(CURRENT_PROJECT_VERSION)\n' > "$T/project.yml"

# bundle <app key> <widget key> <widget build> <SAME_NAME value>
bundle() {
  rm -rf "$T/App.app"
  python3 - "$T/App.app" "$@" <<'PY'
import plistlib, sys
from pathlib import Path
app, app_key, widget_key, widget_build, same = Path(sys.argv[1]), *sys.argv[2:]
base = {"CFBundleShortVersionString": "1.2", "CFBundleVersion": "7"}
for path, extra in ((app, {"RevenueCatAPIKey": app_key, "SAME_NAME": same}),
                    (app / "PlugIns/Widgets.appex", {"RevenueCatAPIKey": widget_key, "CFBundleVersion": widget_build})):
    path.mkdir(parents=True)
    (path / "Info.plist").write_bytes(plistlib.dumps({**base, **extra}))
PY
}
FAILED=0
expect() { # expect <pass|fail> <text in the output> <bundle arguments>
  local want="$1" text="$2" out status=pass; shift 2
  bundle "$@"
  out="$(scripts/check-build.py "$T/App.app" 2>&1)" || status=fail
  if [ "$status" != "$want" ] || ! grep -qF -- "$text" <<< "$out"; then
    echo "FAIL ($*): wanted $want with \"$text\", got $status: $out"; FAILED=1
  fi
}
expect pass 'Build check passed: App.app, Widgets.appex' key key 7 value
expect fail 'REVENUECAT_API_KEY is empty in the release build (App.app, Info.plist key RevenueCatAPIKey)' '' key 7 value
expect fail 'REVENUECAT_API_KEY is empty in the release build (Widgets.appex' key '' 7 value
expect fail 'SAME_NAME is empty in the release build (App.app' key key 7 ''
expect fail 'Widgets.appex has CFBundleVersion 6, but App.app has 7' key key 6 value
[ "$FAILED" = 0 ] && echo "check-build: all cases pass"
exit "$FAILED"
