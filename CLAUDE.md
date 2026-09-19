# BabyBuddy

An offline-first iOS client for a self-hosted [Baby Buddy](https://github.com/babybuddy/babybuddy) server. SwiftUI + SwiftData, a widget/App Intents extension, no backend of its own.

## Versioning and releases

- **Never bump `MARKETING_VERSION` unprompted.** It is the App Store version, and a new one sends the next TestFlight build through App Store review instead of straight to testers. It changes only when the owner asks for a release — ask first, every time.
- **"Bump the version" means `CURRENT_PROJECT_VERSION`** — the build number. Bump it for every upload; a build number may only be used once per marketing version.
- Both live in `project.yml` and apply to the app and the widget alike; App Store Connect rejects an upload whose extension version doesn't match the app's.

## Build

- The project is generated: **run `xcodegen generate` after adding or removing a Swift file.** `BabyBuddy.xcodeproj` is gitignored.
- The repo lives under `~/Documents`, which iCloud manages — it stamps `com.apple.FinderInfo` on the built `.appex` and codesigning then fails with "resource fork… detritus not allowed". **Build to a `-derivedDataPath` outside `~/Documents`.**
- `Sources/Shared` and `Sources/Persistence` compile into the widget target too — keep app-only dependencies out of them.

## CI

- `.github/workflows/pr.yml` builds and tests every PR that touches code, on **GitHub's
  runners**, which are free because this repository is public: `macos-26` for
  `build-and-test`, `ubuntu-latest` for the docs-only filter and the attribution check.
  Pinned to `macos-26`, not `macos-latest` — the suite needs iOS 26+, and `-latest` moves to
  the next major on GitHub's schedule.
- The self-hosted runners (`scripts/runner.sh` on the Mac, `scripts/runner-linux.sh` on the
  Linux box) are no longer used by this workflow. They were free too, but a job only ran when
  that machine was awake, reachable and not already busy, and a wedged runner connection or a
  simulator another process had upset both read as CI failures.
- CI runs `xcodegen generate` then `xcodebuild ... test CODE_SIGNING_ALLOWED=NO` against the
  newest available iPhone simulator. The scheme builds the widget as a dependency, so an
  app-only import added to `Sources/Shared` or `Sources/Persistence` fails there.
- Then, if the unit tests pass, the UI tests (`scripts/ui-test.sh`, below) with one retry per
  test. A failed run uploads `UITests.xcresult`, with a screenshot of each failure.
- Both run unsigned on purpose: without the App Group the store and the keychain fall back to
  app-only locations, which is all the app itself needs. Only Home Screen widgets need signing.
- Docs-only PRs (`*.md`, `Docs/`) skip the macOS job. Any other path builds.
- `release-notes` runs on every PR, docs-only ones included: `node scripts/release.mjs validate`
  checks that each version in `Docs/release-notes.md` has a non-empty `appstore` and `whatsnew`
  block and that the store text fits App Store Connect's 4,000 characters. It reports through
  `build-and-test`, the one check the ruleset requires. `node --test scripts/release.test.mjs`
  runs its tests; both need nothing installed.

## UI tests

- **Every user-visible change adds or updates a UI test** in `UITests/`, or its PR says why not
  (a widget, a purchase, the camera, nothing visible). Home Screen widgets aren't UI-tested — driving
  SpringBoard is too brittle — so their logic lives in unit tests.
- Run them with `scripts/ui-test.sh` — the same command CI runs, on its own simulator ("BabyBuddy
  UI Tests"), erased first. Extra `xcodebuild` arguments pass through, e.g.
  `-only-testing:BabyBuddyUITests/DialogTests`. They have their own scheme, `BabyBuddyUITests`, so
  `xcodebuild test` on `BabyBuddy` stays unit-only.
- Tests subclass `UITestCase` and `launch()` a clean install: `BB_UITEST=1` wipes the store, both
  defaults domains, the keychain and pending notifications before anything reads them, and
  `BB_DEMO=1` seeds. Pass other `BB_*` hooks to `launch`.
- `scripts/ui-test.sh --server` is the second lane: `UITests/Server` signs into the demo Baby Buddy
  server (the one App Review uses) and checks pushes, pulls, conflicts and rejections against its
  API. CI passes the repo secrets `BB_E2E_SERVER_URL` and `BB_E2E_TOKEN`; locally they come from the
  login keychain (`security add-generic-password -a "$USER" -s babybuddy-e2e-url -w`, and
  `…-s babybuddy-e2e-token -w`). Without them the tests skip, so the default lane needs nothing but
  the simulator. Those tests only ever touch records carrying their own marker, and delete them
  afterwards; that bundle is never uploaded, because the sign-in types the token.
- Query by what VoiceOver reads; add an `accessibilityIdentifier` only for a label that repeats.
  Demo data is relative to launch time: compare before and after, never a clock time or a "Today"
  total. Reach editors through "+" ▸ More… — the quick-add rows are due to log in one tap (#78).
- The keyboard covers the tab bar, so a tab tap with it up lands on a key: type `\n` first. An
  active search also hides the Timeline toolbar until its "Close" button ends it.
- Notifications and Live Activities live outside the app, in SpringBoard: `UITestCase` has
  `springboard`, `pressHome()` and `openNotificationCenter()` for them. A Live Activity is
  `springboard.otherElements["activity-content-view"]`; a delivered alert is matched by its text,
  on its banner or its Notification Center row. `BB_TIMER_ALERT_SECONDS` and
  `BB_DOSE_ALERT_SECONDS` shorten the waits — 30 minutes and 4 hours otherwise.

## UI

- Design tokens live in `Sources/Shared/DesignSystem.swift` (`BBColor`, `BBFont`, `BBRadius`); shared components in `Sources/Features/Shared/DesignComponents.swift`. Use them rather than system styling — every screen is on the design system.
- **Don't use `confirmationDialog`.** On iOS 26 SwiftUI anchors it to its source button as a popover, and UIKit drops the cancel action in popover presentation — a destructive dialog then ships with no way back. Use `.alert`, or a design-system view (`SignOutDialog`, `StopTimerSheet`).
- Verify UI on an **iOS 26 simulator**. The default booted one here is often iOS 18.6, where dialogs and the tab bar behave differently.
- **Put `.accessibilityElement(children: .contain)` before an `.accessibilityLabel` on a container.** On a plain stack or card the label is stamped onto every child: the sign-out dialog read both its buttons, and the Trends period picker all three segments, as that one label.

## Running it

`BB_DEMO=1` runs against seeded local data with no network. `BB_START_TAB=settings|timeline|trends` opens a tab directly; other hooks are documented at their call sites.

```bash
SIMCTL_CHILD_BB_DEMO=1 SIMCTL_CHILD_BB_START_TAB=settings xcrun simctl launch booted com.kurtisguy.BabyBuddy
```
