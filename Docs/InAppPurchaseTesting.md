# In-App Purchase — Testing Guide

This document covers **manual** verification of the RevenueCat / StoreKit purchase flow. The parts of
the system that are deterministic (the trial state machine, feature gating, and the manager's
offline/misconfigured resilience) are covered by automated unit tests:

- `Tests/TrialManagerTests.swift` — trial activation, expiration, no-restart, `daysRemaining`,
  once-only "trial ended", corrupt-`UserDefaults` handling.
- `Tests/FeatureAccessTests.swift` — the tiering truth table + `EntityKind → PremiumFeature` map.
- `Tests/PurchaseManagerTests.swift` — unconfigured/offline calls are safe no-ops that never touch
  `Purchases.shared`.

The scenarios below require live StoreKit and cannot be unit-tested, because RevenueCat's
`Purchases.shared` singleton is not mockable. Work top to bottom: **StoreKit Configuration** (fastest,
no accounts) → **RevenueCat Test Store** → **Sandbox** → **TestFlight** → **Production**.

## Prerequisites (one-time)

1. In the **RevenueCat dashboard**, create:
   - an entitlement with identifier **`premium`** (must match `PurchaseManager.entitlementID`),
   - one or more products attached to it,
   - an **Offering** (the paywall shows `currentOffering.availablePackages`).
2. In **App Store Connect**, create the matching **Non-Consumable** in-app purchase (Premium is a
   one-time "unlock forever" purchase, not a subscription) with the same product ID.
3. Put the **public Apple RevenueCat API key** in `Config/Secrets.xcconfig` (gitignored):
   ```
   REVENUECAT_API_KEY = appl_XXXXXXXXXXXXXXXXXXXX
   ```
   Rebuild so it lands in the app's `Info.plist` `RevenueCatAPIKey`. With no key the SDK never
   configures and everything stays free (by design).

> Demoing the premium UI without a purchase: launch with `BB_PREMIUM=1` (e.g.
> `SIMCTL_CHILD_BB_PREMIUM=1`) to force premium access on — every gated feature unlocks and the
> Settings status reads "Purchased". This is a screenshot/dev aid only; it can't be set on a shipped
> build. It does **not** exercise the real StoreKit path — use the scenarios below for that.

### What to watch during every scenario

- **Analytics funnel** (TelemetryDeck): `Paywall.viewed` → `Paywall.upgradePressed` → `Purchase.started`
  → `Purchase.completed` / `Purchase.failed` → `Premium.activated`; plus `Purchase.restored`,
  `Trial.started`, `Trial.ended`, and `Feature.locked` (with the `feature` name). Confirm **no PII**
  ever appears in event parameters — only coarse feature keys / error codes.
- **Gating flips live**: once `premium` is active, the Trends tab, Start Timer, premium activity
  editors, and timeline editing all unlock without relaunch (driven by `customerInfoStream`).
- **No crashes** in any state — offline, cancelled, expired trial, corrupt state.

---

## 1. StoreKit Configuration file (local, no accounts)

Fastest loop; runs entirely on-device/simulator with a synthetic store.

**Setup**
1. `Product ▸ Scheme ▸ Edit Scheme… ▸ Run ▸ Options ▸ StoreKit Configuration` → add/select a
   `.storekit` file. Create products whose IDs match the RevenueCat/App Store product IDs.
2. Run the app (not `BB_DEMO` — demo never configures the SDK).

**Steps**
1. As a free user, open **Settings ▸ Premium** — status reads **Free** (or **Trial available**),
   with **Start Free Trial** and **Upgrade** visible.
2. Tap a locked feature (e.g. **Trends** tab, or add a **Sleep** entry) → the lock panel appears and
   `Feature.locked` fires with the feature name. Tap **Upgrade** → paywall (`Paywall.viewed`).
3. Tap the purchase button → StoreKit test sheet → **confirm**. Expect `Purchase.started` then
   `Purchase.completed` + `Premium.activated`; the paywall reflects "You have Premium" and gating unlocks.
4. **Cancel** flow: repeat step 3 but cancel the sheet → no `Purchase.completed`, no error banner,
   status unchanged.
5. **Force a failure**: in the StoreKit config editor, enable *Ask to Buy* / a failing product, retry
   → expect `Purchase.failed` with a coarse `reason` code and a non-crashing error message.
6. **Restore**: delete + reinstall (or use *Debug ▸ StoreKit ▸ Manage Transactions* to clear), then
   **Settings ▸ Restore Purchases** → `Purchase.restored`; entitlement returns.
7. **Manage Purchase** screen shows the correct status and a working **Restore** (there is no
   subscription to cancel for a one-time purchase, so no management link is shown).

**StoreKit transaction manager** (`Debug ▸ StoreKit ▸ Manage Transactions`) lets you refund or
delete the transaction to re-exercise the purchase / restore path without reinstalling.

---

## 2. RevenueCat Test Store

Validates the RevenueCat layer (offerings, entitlement mapping, dashboard events) without App Store
Connect / Sandbox accounts.

**Steps**
1. Enable the **Test Store** for the app in the RevenueCat dashboard and use its test API key in
   `Secrets.xcconfig`.
2. Launch → confirm the paywall renders the **Offering's** packages (proves `currentOffering` loaded;
   if empty, the offering/entitlement isn't wired correctly).
3. Make a test purchase → verify in the RevenueCat dashboard that a customer + transaction appears and
   the **`premium`** entitlement is active. In-app, gating unlocks and `Premium.activated` fires.
4. **Offline launch**: enable Airplane Mode, cold-launch the app. Expect: app launches normally, no
   crash, previously-active `premium` still granted from RevenueCat's cached `CustomerInfo`; a free
   user simply stays free. Re-enable network → `refresh()` reconciles.
5. **Network timeout**: use a slow/blocked network (e.g. Network Link Conditioner "100% Loss") and tap
   purchase/restore → the call should fail gracefully with `Purchase.failed` / no entitlement change,
   spinner clears (`isLoading` returns to false), UI stays responsive.

---

## 3. Sandbox (real StoreKit, sandbox Apple ID)

Exercises the true App Store purchase pipeline end-to-end.

**Setup**
1. Create a **Sandbox Apple ID** in App Store Connect ▸ Users and Access ▸ Sandbox.
2. On a real device: **Settings ▸ App Store ▸ Sandbox Account** → sign in with the sandbox tester.
3. Install a **signed** build (device) using the production RevenueCat key + real product IDs.

**Steps**
1. Purchase the non-consumable → sandbox payment sheet → confirm. As a one-time purchase it does not
   renew or expire — once bought, `premium` stays active for that Apple ID permanently.
2. Verify `premium` activates in-app and in the RevenueCat dashboard (Sandbox customer).
3. **Restore**: delete/reinstall, then **Restore Purchases** → entitlement returns.
4. **Interrupted purchase**: trigger *Ask to Buy* (sandbox) and approve/deny → confirm pending and
   failure paths don't crash.
5. **Refund re-lock**: refund/delete the transaction via the StoreKit transaction manager (simulator
   build) → gating re-locks live once `customerInfoStream` pushes the inactive entitlement.
6. Confirm the **local trial is independent** of purchases: start the trial, verify all premium
   features unlock for 14 days (use `BB_*` note below to fast-forward via device date only for
   throwaway checks), and that after `hasStartedTrial` it can never restart.

> Note: the local trial uses the device clock and `UserDefaults`; it is intentionally **not** tied to
> StoreKit. Do not rely on changing the device date on a shared device — prefer the unit tests
> (`TrialManagerTests`) for expiry logic; use Sandbox only to confirm the trial grants access.

---

## 4. TestFlight (pre-release, real users)

Closest thing to production; uses the **Sandbox** billing environment automatically for testers.

**Steps**
1. Upload a build to **TestFlight**, add internal/external testers.
2. Testers install and purchase — billing runs in Sandbox (no real charge) but through the production
   signing/entitlement path. Confirm purchase, restore, and gating on multiple devices / Apple IDs.
3. Verify **Family Sharing** (if the product enables it) grants `premium` to family members.
4. Confirm analytics land in the TelemetryDeck dashboard from real devices (signed build required;
   debug builds are tagged as test signals).
5. Check upgrade/restore after **reinstall** and after **signing out/in** of the App Store account.

---

## 5. Production

Final verification after App Review approval.

**Steps**
1. Ensure the in-app purchase is **"Approved" / "Ready for Sale"** in App Store Connect and the
   RevenueCat production entitlement/offering is live.
2. With a **real** Apple ID, make one real purchase (refund it afterward via App Store Connect if
   desired) to confirm the production key + product IDs resolve and `premium` activates.
3. Confirm **Restore Purchases** works for a customer on a new device.
4. Monitor the RevenueCat + TelemetryDeck dashboards for the live funnel (`Purchase.completed`,
   `Premium.activated`) and error rates (`Purchase.failed` reason codes).

---

## Regression checklist (run before each release)

- [ ] Unit tests green (`TrialManager`, `FeatureAccess`, `PurchaseManager` + full suite).
- [ ] Free user: premium features show the lock + Upgrade, diaper logging works (feeding is gated), existing data is
      viewable (timeline editing shows the view-only banner).
- [ ] Trial: Start Free Trial (once only), unlocks everything for 14 days, expires to locked, cannot
      restart.
- [ ] Purchase: paywall → buy → unlock; cancel is a no-op; failure shows a message, no crash.
- [ ] Restore returns entitlement on a fresh install.
- [ ] Offline launch and network timeout never crash and never wrongly grant/deny access.
- [ ] No PII in any analytics event (feature keys / error codes only).
