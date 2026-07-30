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

Swap `build` for `test` to run the suite.

`Sources/Info.plist`, `Sources/BabyBuddy.entitlements` and `Widgets/BabyBuddyWidgets.entitlements`
are all generated from `project.yml`. Edit the YAML and re-run `xcodegen generate`; hand edits to
the generated files are overwritten.

## Debug launch flags (simulator)

Pass these via `SIMCTL_CHILD_<NAME>` environment variables to `xcrun simctl launch`:

| Flag | Effect |
|------|--------|
| `BB_DEMO=1` | Seed sample data and skip the network (no server needed) |
| `BB_SEED_CONFLICT=1` | Also seed a sample sync conflict |
| `BB_START_TAB=timeline\|trends\|settings` | Open on a specific tab |
| `BB_OPEN=feeding\|change\|…` | Auto-present a new-entry editor |
| `BB_LOAD_OLDER=<n>` | Auto-page the timeline back `n` history chunks on launch (with `BB_DEMO`) |
| `BB_LOCK=1` | Force the Face ID lock on |
| `BB_NUDGE=gentle\|milestone\|banner` | Force a support-nudge surface on the Dashboard |

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
