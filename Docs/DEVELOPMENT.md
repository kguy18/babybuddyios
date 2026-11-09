# Development

Setup, signing and device builds are covered in the [README](../README.md#build-it-for-your-own-iphone).
This file covers what you need once the project builds.

## Building and testing

```bash
xcodegen generate
xcodebuild -project BabyBuddy.xcodeproj -scheme BabyBuddy \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

Swap `build` for `test` to run the unit tests.

The UI tests (XCUITest, `UITests/`) have their own scheme and a script that runs them on a
dedicated simulator, erased first — the same command CI runs:

```bash
scripts/ui-test.sh
scripts/ui-test.sh -only-testing:BabyBuddyUITests/DialogTests/testSignOutCard
```

A second lane signs into a real Baby Buddy server and checks what the app pushes and pulls. It takes
the server address and an API token from the environment (`BB_E2E_SERVER_URL`, `BB_E2E_TOKEN`) or the
login keychain, and skips when neither is set:

```bash
security add-generic-password -a "$USER" -s babybuddy-e2e-url -w    # prompts for the value
security add-generic-password -a "$USER" -s babybuddy-e2e-token -w
scripts/ui-test.sh --server
```

Use a token for a user of your own, on a server whose data you don't mind test records appearing in
and disappearing from; the tests clean up after themselves but they do write.

A third lane runs on iPhone Duo's open display, which XCUITest can't reach by itself. It needs Xcode
27.1 or later with the iPhone Duo simulator. The script clones that simulator as "BabyBuddy UI Tests
Duo", unfolds it with [duoctl](https://github.com/skarol/duoctl) and stops unless the inner screen
took over. With no `-only-testing` it runs `FoldTests` and `SmokeTests`; on a failure it saves the
open display to `build/duo-open.png`:

```bash
scripts/ui-test.sh --duo-open -only-testing:BabyBuddyUITests/FoldTests
```

`scripts/duoctl` fetches duoctl at the commit it names into `~/.cache/babybuddy-duoctl` and runs it;
change that commit to update it. duoctl uses private simulator interfaces, so treat it as a stopgap
until Apple ships a supported way to fold the simulator. `FoldTests` skip on any other display. To
run them on another simulator, force the open layouts with `TEST_RUNNER_BB_FOLD=1 scripts/ui-test.sh
-only-testing:BabyBuddyUITests/FoldTests`.

`Sources/Info.plist`, `Sources/BabyBuddy.entitlements` and `Widgets/BabyBuddyWidgets.entitlements`
are all generated from `project.yml`. Edit the YAML and re-run `xcodegen generate`; hand edits to
the generated files are overwritten.

The two privacy manifests — `Sources/PrivacyInfo.xcprivacy` and `Widgets/PrivacyInfo.xcprivacy` —
are the exception: they are hand-maintained and merely globbed in as resources, so edit them
directly. The app and the extension are scanned as separate bundles and so need one each; keep the
two in step. Adding a required-reason API (`UserDefaults`, file timestamps, disk space, boot time,
active keyboards) to code the widget also compiles means updating both.

## Build guard

`scripts/guard-build.sh` runs before every build of the app target. It fails the build when
`DEVELOPMENT_TEAM` is not `547DWTTFY6`, and fails a Release build on that team when
`REVENUECAT_API_KEY`, `TELEMETRYDECK_APP_ID` or `TELEMETRYDECK_SALT` is empty. Those come from
`Config/Secrets.xcconfig`, which is gitignored and included with `#include?`, so without the guard a
missing file builds silently. Debug builds and CI carry no secrets and are not checked for them.

Building a fork: set `EXPECTED_TEAM` at the top of the script to your own team, next to
`DEVELOPMENT_TEAM` in `project.yml`.

## Debug launch flags (simulator)

Pass these via `SIMCTL_CHILD_<NAME>` environment variables to `xcrun simctl launch`:

| Flag | Effect |
|------|--------|
| `BB_DEMO=1` | Seed sample data and skip the network (no server needed) |
| `BB_DEMO_DATE=yyyy-MM-dd` | Show this date in Home's header and in the date fields of a new record, for screenshots. The screenshot test passes it. Records still seed relative to the real clock |
| `BB_UITEST=1` | Start from a clean install: wipe the store, defaults, keychain and notifications first (seeding at once with `BB_DEMO`); no analytics or purchases. Every UI test launches with it |
| `BB_SEED_CONFLICT=1` | Also seed a sample sync conflict (into an empty store) |
| `BB_SEED_PENDING=1` | Also seed queued, blocked and photo changes for Pending Changes (into an empty store) |
| `BB_SEED_SICK=1\|clear` | Also seed a day and a half of fever, two medicines, wet diapers and feeds, with sick mode on (into an empty store). `clear` moves the fever and doses 30 hours back, so Home asks to end sick mode |
| `BB_SEED_SECOND_CHILD=1` | Also seed a second child with no records of her own, so the Editor's Baby picker and the ChildSwitcher have somewhere to reassign/switch to (into an empty store) |
| `BB_TEMP_UNIT=c\|f` | Stand in for the region's temperature unit, until one is picked in Settings |
| `BB_START_TAB=timeline\|trends\|settings` | Open on a specific tab |
| `BB_OPEN=timer\|feeding\|change\|…` | Auto-present Start Timer or a new-entry editor |
| `BB_OPEN_PENDING=1` / `BB_OPEN_CONFLICT=1` | Open Pending Changes / the first conflict from Settings |
| `BB_SUPPORTER=1` / `BB_SUPPORTER_SHEET=1` | Force supporter status on / open the supporter sheet from Settings |
| `BB_SCANNER_PREVIEW=1` | Open the QR scanner over a black backdrop, without the camera |
| `BB_GATE_PREVIEW=cloudflareAccess\|unknown` | Open Advanced configuration on sign-in as if that access gate had answered |
| `BB_PASTEBOARD=<text>` | Put `text` on the pasteboard at sign-in, as if copied from elsewhere, for the Paste buttons |
| `BB_LOAD_OLDER=<n>` | Auto-page the timeline back `n` history chunks on launch (with `BB_DEMO`) |
| `BB_LOCK=1` | Force the Face ID lock on |
| `BB_FOLD=1` | Lay out Home, the Timeline and the sheets as on iPhone Duo's open display, however narrow the screen. `FoldTests` pass it when the test runner has `BB_FOLD=1`, to run off the open display |
| `BB_WHATSNEW_UPGRADE=1` | Launch as an update from a release older than the What's New card, so the card presents (with `BB_DEMO`) |
| `BB_NUDGE=gentle\|milestone\|banner` | Force a support-nudge surface on the Dashboard |
| `BB_TIMER_ALERT_SECONDS=<n>` | Turn forgotten-timer alerts on and fire them `n` seconds after a timer starts, whatever Settings says |
| `BB_DOSE_ALERT_SECONDS=<n>` | Turn medication reminders on and shorten every next-dose interval to `n` seconds (the editor's shortest is 4 h) |
| `BB_TOAST_SECONDS=<n>` | Hold the undo toast open for `n` seconds instead of 5 |
| `BB_FEEDBACK=<url>` | Point Settings ▸ Feedback ▸ Send Feedback at another Quackback server instead of feedback.babybuddy.app. The UI tests pass an unreachable one to reach the Mail fallback |
| `BB_FEEDBACK_STUB=signed-out\|signed-in` | With `BB_UITEST`, the feedback sheet and its sign-in use stubs instead of the server. The widget is a small inline page that shows the view the app asks for and reports a user (before `ready`, as Quackback does) only while the app holds a session. The sign-in calls answer locally: an email starting `busy@` hits the rate limit, the code `000000` and the password `wrong` are refused, and anything else signs in. `signed-in` starts the launch with a stub session. The stub keeps the session in memory, not in WebKit's cookie store, whose first read after launch can take over a minute on a cold simulator. UI tests that open the sheet use it, so they need no network |
| `BB_FEEDBACK_COOKIE_STORE=1` | With `BB_FEEDBACK_STUB`, keep the stub's session in WebKit's cookie store as the real sign-in does, so a UI test can check that it survives a relaunch. Slow: see `cookieStoreTimeout` in `UITests/FeedbackTests.swift` |
| `BB_FEEDBACK_KEEP_SESSION=1` | With `BB_UITEST`, keep the feedback session the last launch left in the web view instead of clearing it, so a UI test can check that it survives a relaunch |
| `BB_FEEDBACK_DELETION_MAIL=sent` | With `BB_UITEST`, Send Feedback ▸ Delete Feedback Account's request counts as sent without the Mail composer, which the simulator can't show without a Mail account |

`BB_DEMO=1` is the fastest way to see the app without standing up a server — it seeds a child,
activity history and running timers entirely locally.

## Optional integrations

Both are **disabled by default**, and this repository ships without credentials for either. A
build made from a clone sends no data anywhere and reaches no purchase backend.

Both keys live in `Config/Secrets.xcconfig`, which is gitignored and must never be committed:

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

### Analytics — TelemetryDeck

[TelemetryDeck](https://telemetrydeck.com) is a privacy-focused, cookieless analytics service.
Set an App ID to switch it on:

```
TELEMETRYDECK_APP_ID = <your-app-id>
```

The value flows into the app's `TelemetryDeckAppID` Info.plist key (see
`Config/BabyBuddy.xcconfig`), and `Analytics.start()` initializes the SDK only when it is
non-empty. Analytics are also skipped automatically in `BB_DEMO` mode.

### Tips — RevenueCat

Every feature in the app is free. The [RevenueCat](https://www.revenuecat.com) SDK is integrated
only so customers can leave an optional one-time tip — three consumables, not a subscription.
Tipping marks someone a supporter and unlocks nothing.

```
REVENUECAT_API_KEY = <your-revenuecat-public-apple-sdk-key>   # begins with appl_
```

The key flows into the `RevenueCatAPIKey` Info.plist key, and `PurchaseManager.start()` configures
RevenueCat only when it is non-empty (and never in `BB_DEMO`). Supporter status is exposed
app-wide via the `PurchaseManager` observable (`isSupporter`), which drives the thank-you state
only — never access to a feature.

The `BabyBuddy` scheme also references `Config/BabyBuddy.storekit`, a synthetic local store that
lets tips be exercised in the simulator with no App Store Connect or RevenueCat account.

See [InAppPurchaseArchitecture.md](InAppPurchaseArchitecture.md) and
[InAppPurchaseTesting.md](InAppPurchaseTesting.md).
