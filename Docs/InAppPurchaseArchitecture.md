# In-App Purchase — Architecture

**Every feature in the app is free.** Purchases exist only so customers can leave an optional tip.
Buying one marks them a *supporter* — a thank-you state today, cosmetic perks (themes, alternate app
icons) later. Nothing is ever gated on it.

Three layers, each with one job. Dependencies point downward only; nothing lower knows about the UI.

```
        ┌───────────────────── UI (SwiftUI) ─────────────────────┐
        │ Supporter screen · SettingsView (Support section)      │
        └───────────────┬────────────────────────┬───────────────┘
                        │ reads / actions         │ fire events
                        ▼                         ▼
                 PurchaseManager  ──────────►  Analytics
                   (RevenueCat)   funnel        (TelemetryDeck)
```

## Layer contracts

- **Purchase logic — `PurchaseManager`** (`Sources/Purchases/PurchaseManager.swift`)
  `@MainActor @Observable`. The *only* type that imports RevenueCat. `CustomerInfo` is the single
  source of truth for `isSupporter`. Exposes `start()`, `refresh()`, `tips`, `purchase(tier:)` /
  `purchase(package:)`, `restore()`. Fires the tip funnel to Analytics. RevenueCat types never leave
  this file — the UI picks a `TipTier` and renders `TipProduct` values (tier + localized price).

- **Analytics** (`Sources/Analytics/Analytics.swift`)
  TelemetryDeck wrapper. Tip events fire from `PurchaseManager` (business layer); the UI only emits
  what it alone knows (`Supporter.sheetViewed`, `Supporter.ctaPressed`). Params are coarse (tip tier
  / error code) — never PII. `PurchaseManager` also hands RevenueCat the TelemetryDeck App ID +
  anonymous hashed user so RevenueCat's server-side webhook can correlate purchase events.

- **UI** (`Sources/Features/…`)
  Reads `PurchaseManager` via `@Environment` only. No view constructs a manager (except `#Preview`s)
  and no view references a RevenueCat purchase API.

## The supporter model

- **Three consumable tips**, repeatable — a customer can tip as many times as they like:

  | Tier     | Product ID                            | Price  | Package identifier |
  |----------|---------------------------------------|--------|--------------------|
  | `small`  | `com.kurtisguy.BabyBuddy.tip.small`   | $4.99  | `tip.small`        |
  | `medium` | `com.kurtisguy.BabyBuddy.tip.medium`  | $9.99  | `tip.medium`       |
  | `large`  | `com.kurtisguy.BabyBuddy.tip.large`   | $19.99 | `tip.large`        |

- **Supporter status is forever after the first tip.** All three products attach to the single
  RevenueCat entitlement **`supporter`**: RevenueCat unlocks an entitlement permanently once an
  attached consumable is purchased (consumables have no expiration), so no server-side logic is
  needed.
- Tiers are resolved from the offering **by package identifier** (falling back to the product id's
  suffix) — never by position in `availablePackages`, whose order is dashboard-configurable.
- `SharedDefaults.isSupporter` bridges the status to the widget / App-Intents process across the App
  Group. Nothing reads it to gate anything; it is there for supporter-only cosmetics later.

## Invariants (enforced by review / tests)

1. `import RevenueCat` appears only in `PurchaseManager.swift`; `import RevenueCatUI` only in
   `RevenueCatPaywallView.swift` (the sole UI boundary). No feature view names a RevenueCat type.
2. Managers are constructed once, at the composition root (`BabyBuddyApp`), and injected with
   `.environment(...)`; everything else reads them from the environment.
3. **Nothing is gated.** `isSupporter` is display-only (a thank-you state, later cosmetics); it must
   never decide whether a feature works.
4. Configuration is key-driven: no key → SDK never configures, `isSupporter` stays false, and the app
   is **fully functional**. `BB_DEMO` never configures.

See `Docs/InAppPurchaseTesting.md` for the test matrix.
