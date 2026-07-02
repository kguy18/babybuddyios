# In-App Purchase — Architecture

Five layers, each with one job. Dependencies point downward only; nothing lower knows about the UI.

```
        ┌────────────────────────── UI (SwiftUI) ──────────────────────────┐
        │ PremiumScreen · TrialOfferView · ManagePurchaseView · PremiumGate │
        │ PremiumLockView/Banner · UpgradeButton · SettingsView (Premium)   │
        └───────┬───────────────┬───────────────┬───────────────┬──────────┘
                │ reads/actions  │ gate decision  │ status/actions │ fire events
                ▼                ▼                ▼                ▼
        PurchaseManager    FeatureAccess     TrialManager        Analytics
        (RevenueCat)       (pure rules)      (UserDefaults)      (TelemetryDeck)
                │                                                    ▲
                └──────────────── emits funnel events ───────────────┘
```

## Layer contracts

- **Purchase logic — `PurchaseManager`** (`Sources/Purchases/PurchaseManager.swift`)
  `@MainActor @Observable`. The *only* type that imports RevenueCat. `CustomerInfo` is the single
  source of truth for `hasPremium`. Exposes `start()`, `refresh()`, `purchase()` /
  `purchase(package:)`, `restore()`. Fires the purchase funnel to Analytics. RevenueCat types never
  leave this file (the no-arg `purchase()` lets the UI buy without touching `Package`).

- **Trial logic — `TrialManager`** (`Sources/Purchases/TrialManager.swift`)
  `@MainActor @Observable`. Local 14-day trial in `UserDefaults`, independent of StoreKit. One-shot
  (`hasStartedTrial` guards restart). Injectable clock (`now`) + `defaults` for testing.

- **Feature gating — `FeatureAccess`** (`Sources/Purchases/FeatureAccess.swift`)
  A **pure** decision function: `isUnlocked(feature:hasPremium:isTrial:)`. No dependency on RevenueCat,
  SwiftUI, or the managers — callers pass plain booleans. `PremiumFeature` is the capability catalog;
  `EntityKind.premiumFeature` maps records onto it. Default-deny: a new `PremiumFeature` case is
  premium unless added to `freeFeatures`.

- **Analytics** (`Sources/Analytics/Analytics.swift`)
  TelemetryDeck wrapper. Purchase/premium events fire from the managers (business layer); the UI only
  emits what it alone knows (`Paywall.viewed`, `Paywall.upgradePressed`, `Feature.locked`). Params are
  coarse (feature key / error code) — never PII.

- **UI** (`Sources/Features/…`)
  Reads managers via `@Environment` only; routes every *gate* decision through `FeatureAccess`. No
  view constructs a manager (except `#Preview`s) and no view references a RevenueCat purchase API.

## Invariants (enforced by review / tests)

1. `import RevenueCat` appears only in `PurchaseManager.swift`; `import RevenueCatUI` only in
   `RevenueCatPaywallView.swift` (the sole UI boundary). No feature view names a RevenueCat type.
2. Managers are constructed once, at the composition root (`BabyBuddyApp`), and injected with
   `.environment(...)`; everything else reads them from the environment.
3. Feature **gating** always goes through `FeatureAccess.isUnlocked`. Direct reads of `hasPremium` /
   `isTrialActive` are allowed only to **display status** (Settings/Manage/Paywall/TrialOffer), never
   to decide access.
4. Configuration is key-driven: no key → SDK never configures, `hasPremium` stays false, app is fully
   functional (free tier). `BB_DEMO` never configures.

See `Docs/InAppPurchaseTesting.md` for the test matrix.
