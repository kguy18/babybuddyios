import Foundation
import Observation
import WidgetKit
#if canImport(RevenueCat)
import RevenueCat
#endif

/// One of the three optional supporter tips, smallest to largest. Every feature in the app is free;
/// tipping only marks the customer as a supporter (a thank-you state, plus cosmetic perks later).
///
/// The raw value is the analytics/dev-facing name; ``packageIdentifier`` is the identifier the
/// matching custom package carries in the RevenueCat offering. Tiers are always resolved by
/// identifier — never by position in `availablePackages`, whose order is dashboard-configurable.
enum TipTier: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: String { rawValue }

    /// The package identifier configured on the offering (products are `…BabyBuddy.tip.<tier>`).
    var packageIdentifier: String { "tip.\(rawValue)" }
}

/// A tip the customer can buy right now: the tier plus its store-localized price string.
///
/// A plain value type on purpose — it lets the supporter UI render real, currency-localized prices
/// without importing RevenueCat or handling a `Package`.
struct TipProduct: Identifiable, Equatable, Sendable {
    let tier: TipTier
    /// The store-localized price (e.g. "$4.99", "4,99 €").
    let localizedPrice: String

    var id: TipTier { tier }
}

/// App-wide in-app-purchase state, backed by RevenueCat and isolated from the UI.
///
/// The app is entirely free. Purchases exist only so customers can leave an optional tip; buying one
/// marks them a supporter (``isSupporter``) — a thank-you state and, later, cosmetic perks. Nothing
/// is ever gated on it.
///
/// `CustomerInfo` from RevenueCat is the single source of truth: ``isSupporter`` is derived from it
/// and never set by hand. Views observe this object (it is `@Observable`, so any `private(set)`
/// property drives SwiftUI updates — the codebase's equivalent of an `ObservableObject` with
/// `@Published` properties) and call the async ``refresh()`` / ``purchase(tier:)`` / ``restore()``
/// methods; all errors are funneled into ``errorMessage`` rather than thrown to the UI.
///
/// RevenueCat only initializes when a public SDK key is configured. The key is injected at build
/// time from `Config/Secrets.xcconfig` (gitignored) into the `RevenueCatAPIKey` Info.plist key.
/// The public repository ships without a key, so open-source / forked builds run with purchases
/// disabled (``isSupporter`` stays `false`) and the app stays fully functional; the App Store build
/// supplies the key locally / via CI. Demo mode (`BB_DEMO`) never configures the SDK.
///
/// Product identifiers live only in the RevenueCat dashboard: callers pick a ``TipTier`` (or hand
/// back a ``Package`` from ``currentOffering``) and never reference a raw product id, keeping store
/// configuration entirely inside this type.
@MainActor
@Observable
final class PurchaseManager {
    /// Entitlement identifier (configured in the RevenueCat dashboard) that marks a supporter. All
    /// three tip products attach to it: RevenueCat unlocks an entitlement forever once an attached
    /// consumable is purchased, so supporter status survives without any server-side logic.
    static let entitlementID = "supporter"

    /// Dev/demo override: launching with `BB_SUPPORTER=1` forces supporter status on, so `BB_DEMO`
    /// (and dev builds) can showcase the thank-you state. Environment variables can't be set on a
    /// shipped App Store build, so this is inert in production.
    static let forcedSupporter = ProcessInfo.processInfo.environment["BB_SUPPORTER"] == "1"

    #if DEBUG
    /// Debug-only override for supporter status, set from Settings ▸ Developer.
    ///
    /// Three-way rather than a switch, because both directions are needed: ``on`` shows the
    /// thank-you state without paying, and ``off`` is the only way to exercise the ask — and the
    /// support nudges — on a device or account that has genuinely tipped, since a real purchase
    /// otherwise pins ``isSupporter`` on forever.
    enum DebugSupporterOverride: String, CaseIterable, Identifiable {
        /// No override: whatever the store says. The shipping behavior.
        case store
        /// Force supporter on.
        case on
        /// Force supporter off, real purchase or not.
        case off

        var id: String { rawValue }

        /// How the override reads in the Settings row.
        var label: String {
            switch self {
            case .store: return "Store"
            case .on: return "Forced on"
            case .off: return "Forced off"
            }
        }
    }

    private static let debugOverrideKey = "debug.supporterOverride"

    /// Debug-only manual override, persisted so it survives relaunch during testing. Entirely
    /// compiled out of release (TestFlight/App Store) builds, so it can never affect production.
    private(set) var debugSupporterOverride = UserDefaults.standard.string(forKey: PurchaseManager.debugOverrideKey)
        .flatMap(DebugSupporterOverride.init(rawValue:)) ?? .store

    /// Debug-only: change the override and recompute status immediately.
    func setDebugSupporter(_ override: DebugSupporterOverride) {
        debugSupporterOverride = override
        UserDefaults.standard.set(override.rawValue, forKey: Self.debugOverrideKey)
        recompute()
    }

    /// How the override combines with what the store says — pure, so the precedence the whole
    /// device-testing story rests on (``DebugSupporterOverride/off`` outranking a genuine purchase) is
    /// unit-testable, rather than only reachable by actually tipping on a real device.
    static func resolveSupporter(storeSays: Bool, override: DebugSupporterOverride) -> Bool {
        switch override {
        case .store: return storeSays
        case .on: return true
        case .off: return false
        }
    }
    #endif

    // MARK: - Observable state

    /// Whether the customer has tipped at least once. Recomputed from the RevenueCat entitlement
    /// (the source of truth) plus the ``forcedSupporter`` / debug overrides. Never gates a feature.
    private(set) var isSupporter = false

    init() {
        recompute()
    }

    /// A `true` once the SDK has been configured with an API key (purchases are available).
    private(set) var isConfigured = false

    /// A network request (refresh / purchase / restore) is in flight.
    private(set) var isLoading = false

    /// User-presentable message for the most recent failure of something the customer *asked* for — a
    /// tip or a restore — or `nil` if the last operation succeeded (or was cancelled by the user, which
    /// is not treated as an error). A background ``refresh()`` never populates it; see that method.
    private(set) var errorMessage: String?

    #if canImport(RevenueCat)
    /// The latest `CustomerInfo` snapshot — the single source of truth for supporter status.
    private(set) var customerInfo: CustomerInfo?

    /// The offering holding the tip packages, if any. Populated by ``refresh()``. Callers read
    /// ``tips`` rather than this — no product ids or RevenueCat types leak out.
    private(set) var currentOffering: Offering?
    #endif

    /// The tips available to buy, ordered small → large, each with its store-localized price. Empty
    /// when purchases aren't configured, no offering has loaded yet, or the dashboard offering is
    /// missing the tip packages.
    ///
    /// Prices come from the store, so they localize correctly and never drift from App Store Connect.
    /// Derived from the observed ``currentOffering``, so SwiftUI updates when the offering loads.
    var tips: [TipProduct] {
        #if canImport(RevenueCat)
        return TipTier.allCases.compactMap { tier in
            guard let package = package(for: tier) else { return nil }
            return TipProduct(tier: tier, localizedPrice: package.storeProduct.localizedPriceString)
        }
        #else
        return []
        #endif
    }

    /// The serving offering's identifier, or `nil` when none has loaded. A dashboard-side label
    /// (e.g. "default"), never anything about the customer — it rides along on the supporter funnel
    /// signals so those can be sliced by offering, and so by Experiments variant.
    var offeringIdentifier: String? {
        #if canImport(RevenueCat)
        return currentOffering?.identifier
        #else
        return nil
        #endif
    }

    /// Remote tuning for the supporter sheet and the support nudges, read from the serving
    /// offering's metadata. Compiled defaults whenever there is no offering, no metadata, or no
    /// RevenueCat at all — see ``SupporterRemoteConfig``. Derived from the observed
    /// ``currentOffering``, so SwiftUI re-reads it when the offering lands.
    var supporterConfig: SupporterRemoteConfig {
        #if canImport(RevenueCat)
        return SupporterRemoteConfig(metadata: currentOffering?.metadata)
        #else
        return .defaults
        #endif
    }

    private var observer: Task<Void, Never>?

    /// The public Apple SDK key injected into Info.plist, or `nil` if none was configured.
    private static var apiKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Configuration

    /// Configures RevenueCat if a key is present and we're not in demo mode, then begins observing
    /// customer changes and fetches the initial state. Safe to call once at launch; a no-op
    /// otherwise (no key, already configured, or demo mode).
    func start() {
        guard !isConfigured else { return }
        // Demo mode runs offline with seeded data — never reach the purchase backend.
        guard ProcessInfo.processInfo.environment["BB_DEMO"] != "1" else { return }
        #if canImport(RevenueCat)
        guard let key = Self.apiKey else { return }
        Purchases.configure(withAPIKey: key)
        isConfigured = true
        linkTelemetryDeck()
        observe()
        Task { await refresh() }
        #endif
    }

    #if canImport(RevenueCat)
    /// Tag this RevenueCat customer with the TelemetryDeck App ID + anonymous hashed user, so
    /// RevenueCat's server-side webhook can route its purchase events into TelemetryDeck and
    /// correlate them with our client signals. A no-op when analytics are disabled (no App ID), so
    /// open-source / forked builds send nothing. The attribute keys are RevenueCat's reserved
    /// integration keys (see TelemetryDeck's RevenueCat integration guide).
    private func linkTelemetryDeck() {
        guard let identity = Analytics.telemetryDeckIdentity else { return }
        Purchases.shared.attribution.setAttributes([
            "$telemetryDeckUserId": identity.hashedUser,
            "$telemetryDeckAppId": identity.appID
        ])
    }
    #endif

    // MARK: - Actions

    /// Refreshes the cached `CustomerInfo` and the current offering from RevenueCat. A no-op (leaving
    /// state untouched) when purchases are not configured.
    ///
    /// Unlike a tip or a restore, a failure here is **not** reported through ``errorMessage``: nobody
    /// asked for this work — it runs at launch, and again when the supporter sheet opens — and its only
    /// consequence is already visible in the right place, as ``tips`` being empty and the sheet saying
    /// so in plain language. Surfacing it too would put a red error under copy that explains the same
    /// thing. The SDK logs the underlying error either way.
    func refresh() async {
        #if canImport(RevenueCat)
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let info = Purchases.shared.customerInfo()
            async let offerings = Purchases.shared.offerings()
            apply(try await info)
            currentOffering = try await offerings.current
            errorMessage = nil
        } catch {
            // Intentionally silent — see above.
        }
        #endif
    }

    /// Buys the given tip tier. Returns whether the customer is a supporter afterward. A no-op when
    /// purchases are off or the offering has no package for that tier; cancellation is silent, other
    /// failures land in ``errorMessage``.
    ///
    /// `source` is the entry point that led here (Settings, a deep link, or one of the nudges). It
    /// is carried onto every signal this flow emits, which is how a tip is attributed back to the
    /// door it came through — see ``Analytics/SupporterSource``.
    @discardableResult
    func purchase(tier: TipTier, source: Analytics.SupporterSource) async -> Bool {
        #if canImport(RevenueCat)
        guard isConfigured, let package = package(for: tier) else { return isSupporter }
        return await purchase(package: package, source: source)
        #else
        return isSupporter
        #endif
    }

    #if canImport(RevenueCat)
    /// Purchases the given ``Package``. Returns whether the customer is a supporter afterward. A
    /// silent no-op (returning the current value) when purchases are off or the user cancels; other
    /// failures land in ``errorMessage``.
    @discardableResult
    func purchase(package: Package, source: Analytics.SupporterSource) async -> Bool {
        guard isConfigured else { return isSupporter }
        isLoading = true
        defer { isLoading = false }
        // Tips are consumable and repeatable, so the tier — not "did they buy" — is the funnel's
        // dimension. An unrecognized package reports "unknown" rather than dropping the event.
        let tier = Self.tier(for: package)?.rawValue ?? "unknown"
        let offering = offeringIdentifier
        let wasSupporter = isSupporter
        Analytics.tipPurchaseStarted(tier: tier, source: source)
        do {
            let result = try await Purchases.shared.purchase(package: package)
            // User cancellations are an expected outcome, not an error to surface.
            guard !result.userCancelled else {
                Analytics.purchaseCancelled(source: source)
                return isSupporter
            }
            apply(result.customerInfo)
            errorMessage = nil
            Analytics.tipPurchased(tier: tier, source: source, offering: offering)
        } catch ErrorCode.purchaseCancelledError {
            // Cancelled from the StoreKit sheet — leave state as-is, no error.
            Analytics.purchaseCancelled(source: source)
        } catch {
            // This call can throw over a tip that actually went through — sandbox especially, where a
            // slow hand-off to RevenueCat's backend outlives the request while the transaction itself
            // completes. The entitlement then lands on `customerInfoStream`, sometimes before this
            // `catch` even runs. Supporter status comes from `CustomerInfo` alone, so if it flipped on
            // during the call the purchase demonstrably succeeded: thank the customer instead of
            // apologising, and never invite them to pay a second time for something they already
            // bought. (A repeat tip can't be told apart this way — its entitlement is already
            // active — so that keeps reporting the failure.)
            if isSupporter, !wasSupporter {
                errorMessage = nil
                Analytics.tipPurchased(tier: tier, source: source, offering: offering)
            } else {
                handle(error)
                Analytics.purchaseFailed(reason: Self.analyticsReason(for: error), source: source)
            }
        }
        return isSupporter
    }
    #endif

    /// Restores previously-purchased entitlements (e.g. a Settings "Restore Purchases" action).
    /// Returns whether the customer is a supporter afterward; a no-op returning `false` when
    /// purchases are off.
    @discardableResult
    func restore() async -> Bool {
        #if canImport(RevenueCat)
        guard isConfigured else { return false }
        isLoading = true
        defer { isLoading = false }
        do {
            apply(try await Purchases.shared.restorePurchases())
            errorMessage = nil
            // `apply` already emits `Supporter.activated` on a genuine flip; this reports the
            // restore's own outcome so "restored but nothing found" is distinguishable from a real
            // activation.
            Analytics.restorePurchases(result: isSupporter ? .activated : .nothing)
        } catch {
            handle(error)
            Analytics.restorePurchases(result: .failed)
        }
        #endif
        return isSupporter
    }

    // MARK: - Private

    /// Re-derive ``isSupporter`` from every source: the RevenueCat customer (the source of truth)
    /// plus the launch (`forcedSupporter`) and debug overrides. The single place status is computed.
    private func recompute() {
        let previous = isSupporter
        var value = Self.forcedSupporter
        #if canImport(RevenueCat)
        value = value || Self.isSupporter(from: customerInfo)
        #endif
        #if DEBUG
        // The developer override is last, and wins in *both* directions — a plain OR could only ever
        // force supporter on, which leaves a device that has really tipped with no way back to the ask.
        value = Self.resolveSupporter(storeSays: value, override: debugSupporterOverride)
        #endif
        isSupporter = value
        // Bridge supporter status to the widget / App-Intents process. Nothing is gated on it today;
        // it's here for supporter-only cosmetics later. Widgets are refreshed on a change so those
        // will pick it up live.
        SharedDefaults.isSupporter = value
        if value != previous { WidgetCenter.shared.reloadAllTimelines() }
    }

    #if canImport(RevenueCat)
    /// Whether a customer snapshot makes someone a supporter — the whole rule, in one pure function
    /// so it is unit-testable (the surrounding SDK flows need live StoreKit and are not).
    ///
    /// The `supporter` entitlement is the intended signal. Belt and braces: any non-subscription
    /// purchase (all three tips are consumables) counts too, so a misconfigured dashboard can't
    /// leave someone who paid without their thank-you.
    static func isSupporter(from info: CustomerInfo?) -> Bool {
        guard let info else { return false }
        return info.entitlements[entitlementID]?.isActive == true || !info.nonSubscriptions.isEmpty
    }

    /// The offering's package for a tier, matched by package identifier (the dashboard's
    /// `tip.small` / `tip.medium` / `tip.large`) and falling back to the product id's suffix, so a
    /// package renamed in the dashboard still resolves. Never positional.
    private func package(for tier: TipTier) -> Package? {
        guard let packages = currentOffering?.availablePackages else { return nil }
        return packages.first { Self.tier(for: $0) == tier }
    }

    /// The tier a package represents, or `nil` if it isn't one of the tips.
    private static func tier(for package: Package) -> TipTier? {
        tier(packageIdentifier: package.identifier,
             productIdentifier: package.storeProduct.productIdentifier)
    }

    /// The matching rule itself, over the two identifiers it actually reads.
    ///
    /// Split out from the `Package` overload because this is what decides the `tier` band on every
    /// signal in the tip funnel, and a `Package` can't be built in a unit test without live
    /// StoreKit. Getting it wrong doesn't break buying — it silently mislabels the analytics.
    static func tier(packageIdentifier: String, productIdentifier: String) -> TipTier? {
        TipTier.allCases.first { tier in
            packageIdentifier == tier.packageIdentifier
                || productIdentifier.hasSuffix(".\(tier.packageIdentifier)")
        }
    }

    /// Stream `CustomerInfo` updates (the cached value is delivered immediately, then any changes).
    private func observe() {
        observer = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    /// Whether the first `CustomerInfo` snapshot has been applied. Used so `Supporter.activated`
    /// fires only on a genuine mid-session transition, not on the initial stream snapshot at every
    /// launch.
    private var hasLoadedInitial = false

    /// Store the latest `CustomerInfo` and re-derive ``isSupporter``. Emits `Supporter.activated`
    /// when status flips on after launch.
    private func apply(_ info: CustomerInfo) {
        let wasSupporter = isSupporter
        customerInfo = info
        recompute()
        if hasLoadedInitial, isSupporter, !wasSupporter {
            Analytics.supporterActivated()
            // The other half of the slow-hand-off case in ``purchase(package:)``: when the entitlement
            // arrives *after* that call gave up, an apology is already on screen. Whatever failed
            // plainly didn't stop the tip, so retract it rather than leave it contradicting the
            // thank-you right above it.
            errorMessage = nil
        }
        hasLoadedInitial = true
    }

    /// Map an SDK error onto ``errorMessage`` without leaking backend details.
    private func handle(_ error: Error) {
        errorMessage = Self.userMessage(for: error)
    }

    /// Generic copy for a failure we can't say anything more useful about. Names neither a cause nor
    /// an operation, because ``handle(_:)`` is reached from a tip and a restore alike.
    static let genericFailureMessage = "Something went wrong. Please try again."

    /// The sentence shown to the customer when a tip or a restore fails — pure, so the whole mapping
    /// is unit-testable (the SDK flows that produce these errors need live StoreKit and aren't).
    ///
    /// RevenueCat's public API throws a `PublicError`: an `NSError` in `ErrorCode.errorDomain` whose
    /// `userInfo` carries a developer-facing `NSLocalizedDescriptionKey` — the code's description plus
    /// an internal message, naming "your configuration" and "the RevenueCat dashboard" and linking to
    /// rev.cat. Casting that to ``ErrorCode`` succeeds but is **lossy**: the runtime re-derives the
    /// bare enum from the error's domain and code and drops the `userInfo` entirely, and `ErrorCode`'s
    /// own `CustomNSError` supplies only `NSDebugDescriptionErrorKey` — never a localized description.
    /// So asking the cast value for `localizedDescription` gets Foundation's placeholder instead,
    /// "The operation couldn't be completed. (RevenueCat.ErrorCode error 23.)", which is exactly what
    /// used to reach the screen. Neither string belongs in front of a parent, so codes are translated
    /// into our own copy here.
    static func userMessage(for error: Error) -> String {
        // Everything the SDK hands back carries a code. Anything else would be a programming error
        // rather than something to explain, and a foreign `NSError` with no description of its own
        // would land us back on the same Foundation placeholder — so it takes the generic sentence.
        guard let code = error as? ErrorCode else { return genericFailureMessage }
        switch code {
        case .networkError, .offlineConnectionError, .productRequestTimedOut, .apiEndpointBlockedError:
            return "Couldn't reach the App Store. Check your connection and try again."
        case .purchaseNotAllowedError, .insufficientPermissionsError:
            return "Purchases aren't allowed on this device. Check Screen Time restrictions and try again."
        case .paymentPendingError:
            return "Your tip needs approval before it completes. It'll be applied once that's done."
        case .productNotAvailableForPurchaseError, .configurationError, .unsupportedError:
            // Deliberately the same sentence the supporter sheet shows when it has no amounts to
            // offer, so the two can never contradict each other.
            return "Tips aren't available right now — please try again later."
        default:
            // Store outages, backend hiccups, receipt problems, and whatever a future SDK adds: the
            // customer can only retry, so don't name a cause we aren't sure of.
            return genericFailureMessage
        }
    }

    /// A coarse, non-identifying reason string for analytics — the RevenueCat error code only,
    /// never the (potentially user-containing) error message.
    private static func analyticsReason(for error: Error) -> String {
        if let code = error as? ErrorCode {
            return "code-\(code.rawValue)"
        }
        return "unknown"
    }
    #endif
}
