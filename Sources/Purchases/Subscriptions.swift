import Foundation
import Observation
#if canImport(RevenueCat)
import RevenueCat
#endif

/// App-wide in-app-purchase state, backed by RevenueCat.
///
/// RevenueCat only initializes when a public SDK key is configured. The key is injected at build
/// time from `Config/Secrets.xcconfig` (gitignored) into the `RevenueCatAPIKey` Info.plist key.
/// The public repository ships without a key, so open-source / forked builds run with purchases
/// disabled (and `isSubscribed` stays `false`); the App Store build supplies the key locally / via
/// CI. Mirrors the ``Analytics`` wrapper. Demo mode (`BB_DEMO`) never configures the SDK.
///
/// This is the single source of entitlement truth for the UI: views read ``isSubscribed`` and it
/// updates live as RevenueCat pushes new `CustomerInfo`.
@MainActor
@Observable
final class Subscriptions {
    /// Entitlement identifier (configured in the RevenueCat dashboard) that unlocks Pro features.
    static let entitlementID = "pro"

    /// Whether the current customer has the Pro entitlement active. `false` until the SDK is
    /// configured and the first `CustomerInfo` arrives — and always `false` when purchases are off.
    private(set) var isSubscribed = false

    /// `true` once the SDK has been configured with an API key (purchases are available).
    private(set) var isConfigured = false

    private var observer: Task<Void, Never>?

    /// The public Apple SDK key injected into Info.plist, or `nil` if none was configured.
    private static var apiKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Configures RevenueCat if a key is present and we're not in demo mode, then begins observing
    /// entitlement changes. Safe to call once at launch; a no-op otherwise.
    func start() {
        guard !isConfigured else { return }
        // Demo mode runs offline with seeded data — never reach the purchase backend.
        guard ProcessInfo.processInfo.environment["BB_DEMO"] != "1" else { return }
        #if canImport(RevenueCat)
        guard let key = Self.apiKey else { return }
        Purchases.configure(withAPIKey: key)
        isConfigured = true
        observe()
        #endif
    }

    /// Restore previously-purchased entitlements (e.g. a Settings "Restore Purchases" action).
    /// Returns whether Pro is active afterward; a no-op returning `false` when purchases are off.
    @discardableResult
    func restorePurchases() async -> Bool {
        #if canImport(RevenueCat)
        guard isConfigured else { return false }
        if let info = try? await Purchases.shared.restorePurchases() {
            apply(info)
        }
        #endif
        return isSubscribed
    }

    #if canImport(RevenueCat)
    /// Stream `CustomerInfo` updates (the cached value is delivered immediately, then any changes).
    private func observe() {
        observer = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    private func apply(_ info: CustomerInfo) {
        isSubscribed = info.entitlements[Self.entitlementID]?.isActive == true
    }
    #endif
}
