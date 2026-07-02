import Foundation

/// The single source of truth for which ``PremiumFeature`` cases are available to a customer.
///
/// This is a pure decision function — it takes the customer's tier as plain booleans and returns a
/// verdict, so it has no dependency on RevenueCat, SwiftUI, or any manager and is trivially unit
/// testable. Call sites wire it to live state, e.g.:
///
/// ```swift
/// FeatureAccess.isUnlocked(feature: .sleep,
///                          hasPremium: purchases.hasPremium,
///                          isTrial: trial.isTrialActive)
/// ```
///
/// **Tiering rules**
/// - Premium customers: everything unlocked.
/// - Trial customers: everything unlocked.
/// - Free customers: only the features in ``freeFeatures`` (feeding and diapers). Viewing existing
///   data is never gated here — reads are always allowed; this function governs active use of a
///   feature, not read access.
///
/// **Adding a feature is trivial:** add a `case` to ``PremiumFeature`` and it is premium by default
/// (locked for free users). To make a new feature free instead, add it to ``freeFeatures``. There is
/// no per-feature branching to maintain — the default is "deny for free," which is the safe default.
enum FeatureAccess {
    /// Features available on the free tier. Everything not listed here is premium-only.
    static let freeFeatures: Set<PremiumFeature> = [
        .feeding,
        .diapers
    ]

    /// The premium-only features, in catalog order — the complement of ``freeFeatures``. Lets a
    /// paywall list what upgrading unlocks without re-deriving the free/premium split in the UI.
    static let premiumFeatures: [PremiumFeature] = PremiumFeature.allCases.filter {
        !freeFeatures.contains($0)
    }

    /// Whether `feature` is available to a customer with the given tier.
    static func isUnlocked(feature: PremiumFeature, hasPremium: Bool, isTrial: Bool) -> Bool {
        // Premium and trial customers get everything.
        if hasPremium || isTrial { return true }
        // Free customers get only the allow-listed features.
        return freeFeatures.contains(feature)
    }
}
