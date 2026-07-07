# Implementing the Premium In-App Purchase

This is the end-to-end runbook for turning on Baby Buddy's premium purchase. The **app code is
already complete** — `PurchaseManager`, the paywall, gating, trial, and analytics all ship today.
What is missing is the external configuration (App Store Connect + RevenueCat) and one build-time
secret. Do the steps **in order**; later steps depend on IDs created in earlier ones.

## What already exists in the code (do not rebuild)

- `Sources/Purchases/PurchaseManager.swift` — the only file that imports RevenueCat. `CustomerInfo`
  is the single source of truth; `hasPremium` is derived from the entitlement.
- **Entitlement identifier is hard-coded to `premium`** (`PurchaseManager.entitlementID`). Your
  RevenueCat entitlement **must** use exactly this identifier or nothing unlocks.
- The app reads a public RevenueCat key from the `RevenueCatAPIKey` Info.plist entry, which
  `project.yml` maps from `$(REVENUECAT_API_KEY)` (see `Config/BabyBuddy.xcconfig`). **No key → SDK
  never configures → app runs as a fully-functional free tier.** This is by design for the
  open-source repo.
- The paywall (`Sources/Features/Paywall/PremiumScreen.swift`) buys via the no-argument
  `purchase()`, which purchases `currentOffering.availablePackages.first`. So your RevenueCat
  **Offering's first/default package must be the premium product.**
- **Product is a one-time non-consumable**, presented as **"Unlock forever · one-time purchase."**
  The price shown is the **live, currency-localized App Store price** (`purchases.localizedPrice`),
  with `$9.99` used only as a fallback before the offering loads (`PremiumScreen.swift:186`). Not a
  subscription.

### Key facts to reuse verbatim

| Thing | Value |
| --- | --- |
| App bundle ID | `com.kurtisguy.BabyBuddy` |
| RevenueCat entitlement identifier | `premium` (must match exactly) |
| Product type | Non-consumable (one-time) |
| Suggested product ID | `com.kurtisguy.BabyBuddy.premium` |
| Price | Your choice (paywall shows the live store price) |
| Secret key name | `REVENUECAT_API_KEY` in `Config/Secrets.xcconfig` |

> ✅ **The paywall shows the live App Store price** (`purchases.localizedPrice`, currency-localized
> per region), so whatever price tier you pick in App Store Connect is what users see — no code
> change needed to change the price. The `$9.99` in `PremiumScreen.swift:186` is only a fallback
> shown before the offering loads (or in open-source builds with no key); pick a US tier at/near
> $9.99 if you want the pre-load flash to match.

---

## Part A — App Store Connect (create the product)

You need: an Apple Developer Program membership, the **Account Holder or Admin** role, and completed
**Agreements, Tax, and Banking** for **Paid Apps** (App Store Connect ▸ Business). Without the active
Paid Apps agreement, products stay stuck in "Missing Metadata" and never load.

1. **Confirm the app record exists.** App Store Connect ▸ **Apps**. If Baby Buddy isn't there, create
   it with bundle ID `com.kurtisguy.BabyBuddy` (register the App ID in the Developer portal first if
   needed).
2. **Create the in-app purchase.** Open the app ▸ **Monetization ▸ In-App Purchases** ▸ **+**.
   - Type: **Non-Consumable**.
   - Reference Name: `Baby Buddy Premium` (internal only).
   - Product ID: `com.kurtisguy.BabyBuddy.premium` — **this string is permanent; copy it exactly, you
     will paste it into RevenueCat in Part B.**
3. **Set the price.** Pick any price point (the paywall displays whatever you choose, localized per
   region). $9.99 USD keeps it consistent with the pre-load fallback text. Review the auto-generated
   worldwide prices.
4. **Add localization.** At least one language (e.g. English U.S.):
   - Display Name: `Premium` (this can appear on the App Store payment sheet).
   - Description: e.g. `Unlock every activity, live timers, trends, and widgets forever.`
5. **Add a review screenshot + review notes.** Apple requires a screenshot of the paywall for review.
   Run the app, open the paywall (`PremiumScreen`), screenshot it, and upload. In review notes,
   explain it's a one-time unlock of premium tracking features.
6. **Create a Sandbox tester.** Users and Access ▸ **Sandbox ▸ Testers ▸ +**. Use an email you do
   **not** already use for a real Apple ID. You'll need this in Part D.
7. **Generate the App-Specific Shared Secret.** App ▸ (In-App Purchases area) ▸ **App-Specific Shared
   Secret** ▸ generate/copy. RevenueCat needs this in Part B.
8. Leave the product state as **"Ready to Submit."** A non-consumable can be submitted **with the
   first app version that contains it** — you do not submit it separately, but it must exist now so
   sandbox/StoreKit can resolve it.

**App Store Connect API key for RevenueCat (strongly recommended over the shared secret alone):**
Users and Access ▸ **Integrations ▸ App Store Connect API** ▸ generate an **In-App Purchase** or
**Admin** key ▸ download the `.p8` (one-time download), and note the **Key ID** and **Issuer ID**.
RevenueCat uses this to read products and receive Server Notifications automatically.

---

## Part B — RevenueCat (wire products → entitlement → offering)

Create a free account at <https://app.revenuecat.com> if you don't have one.

1. **Create a Project** (or open the existing Baby Buddy project).
2. **Add the App.** Project Settings ▸ **Apps ▸ + New ▸ App Store**.
   - App name + **bundle ID `com.kurtisguy.BabyBuddy`**.
   - Paste the **App-Specific Shared Secret** from Part A step 7.
   - (Recommended) Upload the **App Store Connect API key** `.p8` + Key ID + Issuer ID from Part A so
     RevenueCat can import products and get server notifications automatically.
3. **Grab the public SDK key.** Project Settings ▸ **API Keys** ▸ copy the **Public app-specific
   Apple key** — it **begins with `appl_`**. (Use the *public* SDK key, **never** a secret key.) You
   will paste this in Part C.
4. **Add the Product.** **Product Catalog ▸ Products ▸ + New**.
   - Store: **App Store**.
   - Product ID: paste `com.kurtisguy.BabyBuddy.premium` exactly from Part A step 2.
   - Type: **Non-consumable / one-time**. Import it (if the App Store Connect API key is connected,
     RevenueCat can list and confirm it).
5. **Create the Entitlement — this is the critical one.**
   - **Product Catalog ▸ Entitlements ▸ + New**.
   - Identifier: **`premium`** — must match `PurchaseManager.entitlementID` **character for
     character**. (Not "Premium", not "pro".)
   - **Attach** the `com.kurtisguy.BabyBuddy.premium` product to this entitlement.
6. **Create the Offering.**
   - **Product Catalog ▸ Offerings ▸ + New**. Identifier e.g. `default`. Mark it the **Current**
     offering.
   - Add a **Package** inside it and attach the premium product. Because the app buys
     `availablePackages.first`, if you add only this one package you're safe. (You can use the
     "Lifetime" package identifier or a custom one — the app doesn't care about the identifier, only
     that it's first/default.)
7. *(Optional)* **Build a remote Paywall.** The app renders RevenueCat's `PaywallView` **only if the
   `RevenueCatUI` product is linked** in the Xcode project; otherwise it shows the hand-built
   `PremiumScreen`. Today `project.yml` links only the `RevenueCat` product, so the **hand-built
   paywall is what ships** — you can skip building a RevenueCat paywall. (To switch to the remote
   paywall later, add `product: RevenueCatUI` to the app target's packages in `project.yml`, then
   design the paywall here.)
8. *(Optional, for the analytics funnel)* **TelemetryDeck integration.** The code already tags each
   customer with `$telemetryDeckUserId` / `$telemetryDeckAppId` (`PurchaseManager.linkTelemetryDeck`).
   To route RevenueCat's server-side purchase events into TelemetryDeck, add the **TelemetryDeck
   integration / webhook** in RevenueCat ▸ Integrations. Not required for purchases to work.

---

## Part C — Put the key into the build

1. Copy the template if you haven't already:
   ```bash
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   ```
   `Config/Secrets.xcconfig` is **gitignored** — never commit it.
2. Set the public key from Part B step 3:
   ```
   REVENUECAT_API_KEY = appl_XXXXXXXXXXXXXXXXXXXXXXXX
   ```
   (Also set `TELEMETRYDECK_APP_ID` / `TELEMETRYDECK_SALT` here if you use analytics.)
3. **Regenerate the Xcode project** so the xcconfig → Info.plist mapping is picked up (this repo uses
   XcodeGen):
   ```bash
   xcodegen generate
   ```
4. Build and run. On launch, `PurchaseManager.start()` sees the non-empty key and calls
   `Purchases.configure`; `isConfigured` flips true and the paywall's **Buy Premium** button enables.
   If the button stays disabled and the paywall shows "Purchases aren't available in this build," the
   key didn't reach `Info.plist` (re-check steps 2–3).

**CI / App Store builds:** don't commit the key. Inject `REVENUECAT_API_KEY` from a CI secret (write
the `Secrets.xcconfig` in the pipeline, or pass it as a build setting) before `xcodegen generate` +
`xcodebuild`.

---

## Part D — Test the purchase (fastest → most realistic)

Full detail lives in `Docs/InAppPurchaseTesting.md`; the short path:

1. **StoreKit configuration file (no accounts, fastest).** Create a `.storekit` file in Xcode with a
   non-consumable whose product ID is `com.kurtisguy.BabyBuddy.premium`, then
   **Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Options ▸ StoreKit Configuration** → select it. Run, open
   the paywall, tap **Buy Premium**, confirm the synthetic sheet. Expect gating to unlock live and the
   footer to read "You have Premium." Use **Debug ▸ StoreKit ▸ Manage Transactions** to delete the
   purchase and re-test **Restore Purchases**.
2. **RevenueCat Test Store.** Enable the Test Store in RevenueCat, use its test key, and confirm the
   paywall renders your **Offering's** package (proves `currentOffering` loaded) and that a test buy
   shows up as a customer with the `premium` entitlement active in the dashboard.
3. **Sandbox (real StoreKit).** On a device, sign into the **Sandbox Apple ID** from Part A step 6
   (Settings ▸ App Store ▸ Sandbox Account), install a signed build with the production key, and buy.
   Verify `premium` activates in-app and a **Sandbox** customer appears in RevenueCat.
4. **TestFlight.** Upload a build; testers purchase through the production entitlement path (billed in
   sandbox, no real charge). Confirm purchase + restore across devices/Apple IDs.

**Sanity checks each time:** free user sees the lock + Upgrade (diapers work, feeding is gated);
cancel is a silent no-op; failures show a message and never crash; offline launch keeps a
previously-active entitlement from RevenueCat's cache. Run the unit tests too:
`TrialManagerTests`, `FeatureAccessTests`, `PurchaseManagerTests`.

---

## Part E — Ship it

1. Confirm the App Store Connect product is **"Ready to Submit"** and the RevenueCat `premium`
   entitlement + Current offering are live with the real product attached.
2. Verify `Config/Secrets.xcconfig` on the release machine/CI has the **production public key** and is
   **not** committed.
3. Archive the app and, in the version's **In-App Purchases** section of App Store Connect, **attach
   the `com.kurtisguy.BabyBuddy.premium` product to the build** so it's reviewed with the app.
4. Ensure the paywall's **Restore Purchases**, **Privacy Policy**, and **Terms of Service** links work
   (Apple requires restore + terms for a purchase). These are already wired in `PremiumScreen`.
5. Submit for review. After approval, do one **real** production purchase to confirm the live key +
   product ID resolve and `premium` activates (refund it afterward from App Store Connect if desired),
   then watch the RevenueCat + TelemetryDeck dashboards for the live funnel.

---

## Quick reference — the three IDs that must line up

```
App Store Connect product ID   ──►  RevenueCat Product   ──►  attached to Entitlement "premium"
   com.kurtisguy.BabyBuddy.premium        (same ID)                     │
                                                                        ▼
                                              PurchaseManager.entitlementID == "premium"
```

If premium never unlocks after a successful purchase, it's almost always one of:
`premium` entitlement misspelled, the product not attached to the entitlement, the offering not set
as **Current**, or the `appl_` key missing from `Secrets.xcconfig`.
</content>
</invoke>
