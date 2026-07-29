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
    private static let debugSupporterKey = "debug.forceSupporter"
    /// Debug-only manual override toggled from the Settings ▸ Developer switch, persisted so it
    /// survives relaunch during testing. Entirely compiled out of release (TestFlight/App Store)
    /// builds, so it can never affect production.
    private(set) var debugForcedSupporter = UserDefaults.standard.bool(forKey: PurchaseManager.debugSupporterKey)

    /// Debug-only: flip the forced-supporter override and recompute status immediately.
    func setDebugSupporter(_ on: Bool) {
        debugForcedSupporter = on
        UserDefaults.standard.set(on, forKey: Self.debugSupporterKey)
        recompute()
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

    /// User-presentable message for the most recent failure, or `nil` if the last operation
    /// succeeded (or was cancelled by the user, which is not treated as an error).
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
    /// state untouched) when purchases are not configured. Failures land in ``errorMessage``.
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
            handle(error)
        }
        #endif
    }

    /// Buys the given tip tier. Returns whether the customer is a supporter afterward. A no-op when
    /// purchases are off or the offering has no package for that tier; cancellation is silent, other
    /// failures land in ``errorMessage``.
    @discardableResult
    func purchase(tier: TipTier) async -> Bool {
        #if canImport(RevenueCat)
        guard isConfigured, let package = package(for: tier) else { return isSupporter }
        return await purchase(package: package)
        #else
        return isSupporter
        #endif
    }

    #if canImport(RevenueCat)
    /// Purchases the given ``Package``. Returns whether the customer is a supporter afterward. A
    /// silent no-op (returning the current value) when purchases are off or the user cancels; other
    /// failures land in ``errorMessage``.
    @discardableResult
    func purchase(package: Package) async -> Bool {
        guard isConfigured else { return isSupporter }
        isLoading = true
        defer { isLoading = false }
        // Tips are consumable and repeatable, so the tier — not "did they buy" — is the funnel's
        // dimension. An unrecognized package reports "unknown" rather than dropping the event.
        let tier = Self.tier(for: package)?.rawValue ?? "unknown"
        Analytics.tipPurchaseStarted(tier: tier)
        do {
            let result = try await Purchases.shared.purchase(package: package)
            // User cancellations are an expected outcome, not an error to surface.
            guard !result.userCancelled else {
                Analytics.purchaseCancelled()
                return isSupporter
            }
            apply(result.customerInfo)
            errorMessage = nil
            Analytics.tipPurchased(tier: tier)
        } catch ErrorCode.purchaseCancelledError {
            // Cancelled from the StoreKit sheet — leave state as-is, no error.
            Analytics.purchaseCancelled()
        } catch {
            handle(error)
            Analytics.purchaseFailed(reason: Self.analyticsReason(for: error))
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
        #if DEBUG
        value = value || debugForcedSupporter
        #endif
        #if canImport(RevenueCat)
        value = value || Self.isSupporter(from: customerInfo)
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
        TipTier.allCases.first { tier in
            package.identifier == tier.packageIdentifier
                || package.storeProduct.productIdentifier.hasSuffix(".\(tier.packageIdentifier)")
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
        }
        hasLoadedInitial = true
    }

    /// Map an SDK error onto ``errorMessage`` without leaking backend details.
    private func handle(_ error: Error) {
        errorMessage = (error as? ErrorCode)?.localizedDescription ?? error.localizedDescription
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
