import Foundation
import Observation
#if canImport(RevenueCat)
import RevenueCat
#endif

/// App-wide in-app-purchase state, backed by RevenueCat and isolated from the UI.
///
/// `CustomerInfo` from RevenueCat is the single source of truth: ``hasPremium`` is derived from it
/// and never set by hand. Views observe this object (it is `@Observable`, so any `private(set)`
/// property drives SwiftUI updates — the codebase's equivalent of an `ObservableObject` with
/// `@Published` properties) and call the async ``refresh()`` / ``purchase(package:)`` / ``restore()``
/// methods; all errors are funneled into ``errorMessage`` rather than thrown to the UI.
///
/// RevenueCat only initializes when a public SDK key is configured. The key is injected at build
/// time from `Config/Secrets.xcconfig` (gitignored) into the `RevenueCatAPIKey` Info.plist key.
/// The public repository ships without a key, so open-source / forked builds run with purchases
/// disabled (``hasPremium`` stays `false`); the App Store build supplies the key locally / via CI.
/// Demo mode (`BB_DEMO`) never configures the SDK.
///
/// Product identifiers live only in the RevenueCat dashboard: callers purchase a ``Package`` taken
/// from ``currentOffering`` and never reference a raw product id, keeping store configuration
/// entirely inside this type.
@MainActor
@Observable
final class PurchaseManager {
    /// Entitlement identifier (configured in the RevenueCat dashboard) that unlocks premium features.
    static let entitlementID = "premium"

    // MARK: - Observable state

    /// Whether the current customer has the premium entitlement active. Derived solely from
    /// ``customerInfo``; `false` until the first `CustomerInfo` arrives and whenever purchases are off.
    private(set) var hasPremium = false

    /// A `true` once the SDK has been configured with an API key (purchases are available).
    private(set) var isConfigured = false

    /// A network request (refresh / purchase / restore) is in flight.
    private(set) var isLoading = false

    /// User-presentable message for the most recent failure, or `nil` if the last operation
    /// succeeded (or was cancelled by the user, which is not treated as an error).
    private(set) var errorMessage: String?

    #if canImport(RevenueCat)
    /// The latest `CustomerInfo` snapshot — the single source of truth for entitlement state.
    private(set) var customerInfo: CustomerInfo?

    /// The offering to present on the paywall, if any. Populated by ``refresh()``. Callers read its
    /// `availablePackages` and hand one back to ``purchase(package:)`` — no product ids leak out.
    private(set) var currentOffering: Offering?
    #endif

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
    /// entitlement changes and fetches the initial state. Safe to call once at launch; a no-op
    /// otherwise (no key, already configured, or demo mode).
    func start() {
        guard !isConfigured else { return }
        // Demo mode runs offline with seeded data — never reach the purchase backend.
        guard ProcessInfo.processInfo.environment["BB_DEMO"] != "1" else { return }
        #if canImport(RevenueCat)
        guard let key = Self.apiKey else { return }
        Purchases.configure(withAPIKey: key)
        isConfigured = true
        observe()
        Task { await refresh() }
        #endif
    }

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

    #if canImport(RevenueCat)
    /// Purchases the given ``Package``. Returns whether premium is active afterward. A silent no-op
    /// (returning the current value) when purchases are off or the user cancels; other failures land
    /// in ``errorMessage``.
    @discardableResult
    func purchase(package: Package) async -> Bool {
        guard isConfigured else { return hasPremium }
        isLoading = true
        defer { isLoading = false }
        Analytics.purchaseStarted()
        do {
            let result = try await Purchases.shared.purchase(package: package)
            // User cancellations are an expected outcome, not an error to surface.
            guard !result.userCancelled else { return hasPremium }
            apply(result.customerInfo)
            errorMessage = nil
            Analytics.purchaseCompleted()
        } catch ErrorCode.purchaseCancelledError {
            // Cancelled from the StoreKit sheet — leave state as-is, no error.
        } catch {
            handle(error)
            Analytics.purchaseFailed(reason: Self.analyticsReason(for: error))
        }
        return hasPremium
    }
    #endif

    /// Purchases the default package of ``currentOffering`` — a UI-friendly entry point so a paywall
    /// can offer a single "subscribe" action without handling ``Package`` types itself. A no-op when
    /// purchases are off or no offering is configured. Returns whether premium is active afterward.
    @discardableResult
    func purchase() async -> Bool {
        #if canImport(RevenueCat)
        guard isConfigured, let package = currentOffering?.availablePackages.first else {
            return hasPremium
        }
        return await purchase(package: package)
        #else
        return hasPremium
        #endif
    }

    /// Restores previously-purchased entitlements (e.g. a Settings "Restore Purchases" action).
    /// Returns whether premium is active afterward; a no-op returning `false` when purchases are off.
    @discardableResult
    func restore() async -> Bool {
        #if canImport(RevenueCat)
        guard isConfigured else { return false }
        isLoading = true
        defer { isLoading = false }
        Analytics.restorePurchases()
        do {
            apply(try await Purchases.shared.restorePurchases())
            errorMessage = nil
        } catch {
            handle(error)
        }
        #endif
        return hasPremium
    }

    // MARK: - Private

    #if canImport(RevenueCat)
    /// Stream `CustomerInfo` updates (the cached value is delivered immediately, then any changes).
    private func observe() {
        observer = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    /// Whether the first `CustomerInfo` snapshot has been applied. Used so `Premium.activated` fires
    /// only on a genuine mid-session transition, not on the initial stream snapshot at every launch.
    private var hasLoadedInitial = false

    /// Store the latest `CustomerInfo` and re-derive ``hasPremium`` from it — the one place premium
    /// state is computed. Emits `Premium.activated` when the entitlement flips on after launch.
    private func apply(_ info: CustomerInfo) {
        let wasPremium = hasPremium
        customerInfo = info
        hasPremium = info.entitlements[Self.entitlementID]?.isActive == true
        if hasLoadedInitial, hasPremium, !wasPremium {
            Analytics.premiumActivated()
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
