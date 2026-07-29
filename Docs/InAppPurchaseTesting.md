# In-App Purchase — Testing Guide

This document covers **manual** verification of the RevenueCat / StoreKit tip flow. Everything in the
app is free; purchases only mark the customer a **supporter** (see
`Docs/InAppPurchaseArchitecture.md`). The deterministic parts are covered by automated unit tests:

- `Tests/PurchaseManagerTests.swift` — unconfigured/offline calls are safe no-ops that never touch
  `Purchases.shared`, the store identifiers, the supporter rule (`isSupporter` defaults to false,
  flips on an active `supporter` entitlement, and flips on a non-subscription purchase even with no
  entitlement), and the error copy (`userMessage(for:)` maps every `ErrorCode` to a customer-readable
  sentence — never Foundation's "(RevenueCat.ErrorCode error 23.)" placeholder, and never the SDK's
  own developer-facing text with its `rev.cat` links).

The scenarios below require live StoreKit and cannot be unit-tested, because RevenueCat's
`Purchases.shared` singleton is not mockable. Work top to bottom: **StoreKit Configuration** (fastest,
no accounts) → **RevenueCat Test Store** → **Sandbox** → **TestFlight** → **Production**.

## Prerequisites (one-time)

1. In the **RevenueCat dashboard**, create:
   - an entitlement with identifier **`supporter`** (must match `PurchaseManager.entitlementID`),
   - the three tip products, **all attached to that entitlement** (a consumable attached to an
     entitlement unlocks it permanently — that is what makes supporter status stick),
   - an **Offering** (`default`) with three **custom** packages identified `tip.small`, `tip.medium`,
     `tip.large`. The app resolves tiers by package identifier, never by position, so the order the
     packages appear in the dashboard doesn't matter.
2. In **App Store Connect**, create the three matching **Consumable** in-app purchases:

   | Product ID                            | Price  |
   |---------------------------------------|--------|
   | `com.kurtisguy.BabyBuddy.tip.small`   | $4.99  |
   | `com.kurtisguy.BabyBuddy.tip.medium`  | $9.99  |
   | `com.kurtisguy.BabyBuddy.tip.large`   | $19.99 |

3. Put the **public Apple RevenueCat API key** in `Config/Secrets.xcconfig` (gitignored):
   ```
   REVENUECAT_API_KEY = appl_XXXXXXXXXXXXXXXXXXXX
   ```
   Rebuild so it lands in the app's `Info.plist` `RevenueCatAPIKey`. With no key the SDK never
   configures, nobody is a supporter, and **the app stays fully functional** (by design — this is the
   invariant that keeps open-source / forked builds working).

> Demoing the supporter thank-you state without a purchase: launch with `BB_SUPPORTER=1` (e.g.
> `SIMCTL_CHILD_BB_SUPPORTER=1`), or flip **Settings ▸ Developer ▸ Supporter mode** in a DEBUG build.
> Both are screenshot/dev aids only and can't be set on a shipped build. Neither exercises the real
> StoreKit path — use the scenarios below for that.

### What to watch during every scenario

- **Analytics funnel** (TelemetryDeck): `Supporter.sheetViewed` → `Supporter.ctaPressed` →
  `Tip.purchaseStarted` (with `tier`) → `Tip.purchased` (with `tier`) / `Purchase.failed` /
  `Purchase.cancelled` → `Supporter.activated`; plus `Purchase.restored`. Confirm **no PII** ever
  appears in event parameters — only coarse tip tiers / error codes.
- **Nothing is gated.** Every feature must work identically before and after a tip. The only visible
  change is the supporter/thank-you state.
- **Status flips live**: once a tip completes, the Settings status changes without relaunch (driven
  by `customerInfoStream`), and persists across a cold launch.
- **No crashes** in any state — offline, cancelled, unconfigured.

---

## 1. StoreKit Configuration file (local, no accounts)

Fastest loop; runs entirely on-device/simulator with a synthetic store. The repo ships
`Config/BabyBuddy.storekit` with the three consumables at the right prices, already wired into the
**BabyBuddy** scheme's Run action (`storeKitConfiguration` in `project.yml` — re-run
`xcodegen generate` after editing it, since the scheme is generated).

**Setup**
1. Confirm the file is active: *Product ▸ Scheme ▸ Edit Scheme… ▸ Run ▸ Options ▸ StoreKit
   Configuration* reads `BabyBuddy.storekit`.
2. Run the app (not `BB_DEMO` — demo never configures the SDK). Note that RevenueCat still needs an
   API key to produce an *offering*; without one, use this file to exercise raw StoreKit only.

**Steps**
1. As a non-supporter, open **Settings ▸ Support** — status reads **Free**.
2. Open the supporter screen → `Supporter.sheetViewed` fires and the tiers show **store-localized
   prices** ($4.99 / $9.99 / $19.99), proving the offering resolved by package identifier.
3. Tip a tier → StoreKit test sheet → **confirm**. Expect `Tip.purchaseStarted` then `Tip.purchased`
   (both carrying the right `tier`) + `Supporter.activated`; the status flips to supporter.
4. **Repeat the tip** — consumables are repeatable, so a second purchase of the *same* tier must
   succeed rather than being rejected as "already purchased".
5. **Relaunch** — supporter status persists (RevenueCat's cached `CustomerInfo`).
6. **Cancel** flow: start a tip and cancel the sheet → `Purchase.cancelled`, no error banner, status
   unchanged.
7. **Force a failure**: in the StoreKit config editor, enable a *Purchase* error under **Settings ▸
   Enable Errors**, retry → expect `Purchase.failed` with a coarse `reason` code and a non-crashing
   error message.
8. **Restore**: **Restore Purchases** → `Purchase.restored`. Note that consumables are *not* restored
   by StoreKit; supporter status survives via the RevenueCat entitlement, so restore is meaningful
   only once the products are attached to `supporter` in the dashboard.

**StoreKit transaction manager** (*Debug ▸ StoreKit ▸ Manage Transactions*) lets you delete the
transaction to re-exercise the purchase path without reinstalling.

---

## 2. RevenueCat Test Store

Validates the RevenueCat layer (offerings, entitlement mapping, dashboard events) without App Store
Connect / Sandbox accounts.

**Steps**
1. Enable the **Test Store** for the app in the RevenueCat dashboard and use its test API key in
   `Secrets.xcconfig`.
2. Launch → confirm all three tiers render with prices (proves the `default` offering loaded and its
   packages carry the `tip.*` identifiers; if a tier is missing, that package is misidentified).
3. Make a test purchase → verify in the RevenueCat dashboard that a customer + transaction appears
   and the **`supporter`** entitlement is active. In-app, `Supporter.activated` fires.
4. **Entitlement-misconfiguration safety net**: detach the products from `supporter` in the dashboard
   and tip with a fresh customer → the app must *still* treat them as a supporter, because
   `PurchaseManager` also counts any non-subscription purchase. Re-attach afterwards.
5. **Offline launch**: enable Airplane Mode, cold-launch. Expect: app launches normally, every
   feature works, supporter status still granted from RevenueCat's cached `CustomerInfo`.
   Re-enable network → `refresh()` reconciles.
6. **Network timeout**: use a slow/blocked network (e.g. Network Link Conditioner "100% Loss") and
   tap tip/restore → the call fails gracefully with `Purchase.failed`, spinner clears (`isLoading`
   returns to false), UI stays responsive.

---

## 3. Sandbox (real StoreKit, sandbox Apple ID)

Exercises the true App Store purchase pipeline end-to-end.

**Setup**
1. Create a **Sandbox Apple ID** in App Store Connect ▸ Users and Access ▸ Sandbox.
2. On a real device: **Settings ▸ App Store ▸ Sandbox Account** → sign in with the sandbox tester.
3. Install a **signed** build (device) using the production RevenueCat key + real product IDs.

**Steps**
1. Tip each tier → sandbox payment sheet → confirm. Each is a consumable, so the same tier can be
   bought again immediately.
2. Verify `supporter` activates in-app and in the RevenueCat dashboard (Sandbox customer).
3. **Reinstall**: delete/reinstall, then **Restore Purchases** → supporter status returns from the
   entitlement.
4. **Interrupted purchase**: trigger *Ask to Buy* (sandbox) and approve/deny → confirm pending and
   failure paths don't crash.
5. **Refund**: refund/delete the transaction via the StoreKit transaction manager (simulator build) →
   confirm the app doesn't crash and **no feature stops working** (nothing is gated).

---

## 4. TestFlight (pre-release, real users)

Closest thing to production; uses the **Sandbox** billing environment automatically for testers.

**Steps**
1. Upload a build to **TestFlight**, add internal/external testers.
2. Testers tip — billing runs in Sandbox (no real charge) but through the production
   signing/entitlement path. Confirm purchase, repeat purchase, and restore on multiple devices /
   Apple IDs.
3. Confirm analytics land in the TelemetryDeck dashboard from real devices (signed build required;
   debug builds are tagged as test signals).
4. Check supporter status after **reinstall** and after **signing out/in** of the App Store account.

---

## 5. Production

Final verification after App Review approval.

**Steps**
1. Ensure the three in-app purchases are **"Approved" / "Ready for Sale"** in App Store Connect and
   the RevenueCat production entitlement/offering is live.
2. With a **real** Apple ID, make one real purchase (refund it afterward via App Store Connect if
   desired) to confirm the production key + product IDs resolve and `supporter` activates.
3. Confirm **Restore Purchases** works for a customer on a new device.
4. Monitor the RevenueCat + TelemetryDeck dashboards for the live funnel (`Tip.purchased`,
   `Supporter.activated`) and error rates (`Purchase.failed` reason codes).

---

## Regression checklist (run before each release)

- [ ] Unit tests green (`PurchaseManagerTests` + full suite).
- [ ] **No key configured** (fresh clone, no `Secrets.xcconfig`): app launches and every feature works;
      purchase UI shows the "not available in this build" state; nothing crashes.
- [ ] All three tiers show store-localized prices and buy the tier that was tapped.
- [ ] A second tip of the same tier succeeds (consumables are repeatable).
- [ ] Supporter status flips live and survives a relaunch.
- [ ] Cancel is a silent no-op; failure shows a message, no crash.
- [ ] Offline launch and network timeout never crash and never wrongly grant/deny supporter status.
- [ ] No PII in any analytics event (tip tiers / error codes only).
