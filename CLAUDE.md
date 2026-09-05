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

## UI

- Design tokens live in `Sources/Shared/DesignSystem.swift` (`BBColor`, `BBFont`, `BBRadius`); shared components in `Sources/Features/Shared/DesignComponents.swift`. Use them rather than system styling — every screen is on the design system.
- **Don't use `confirmationDialog`.** On iOS 26 SwiftUI anchors it to its source button as a popover, and UIKit drops the cancel action in popover presentation — a destructive dialog then ships with no way back. Use `.alert`, or a design-system view (`SignOutDialog`, `StopTimerSheet`).
- Verify UI on an **iOS 26 simulator**. The default booted one here is often iOS 18.6, where dialogs and the tab bar behave differently.

## Running it

`BB_DEMO=1` runs against seeded local data with no network. `BB_START_TAB=settings|timeline|trends` opens a tab directly; other hooks are documented at their call sites.

```bash
SIMCTL_CHILD_BB_DEMO=1 SIMCTL_CHILD_BB_START_TAB=settings xcrun simctl launch booted com.kurtisguy.BabyBuddy
```
