import XCTest
@testable import BabyBuddy

/// Covers ``PurchaseManager``'s resilience when purchases are **not configured** — the state a build
/// is in before `start()` runs, when no API key is present (open-source/clone builds), in demo mode,
/// and effectively when launched offline before the SDK has any cached customer info.
///
/// The real purchase/restore/refresh flows run against RevenueCat's `Purchases.shared` singleton,
/// which cannot be mocked in a unit test (it would require live StoreKit + network). Those paths —
/// a successful purchase, a restore, RevenueCat errors, and network timeouts — are covered by the
/// manual procedures in `Docs/InAppPurchaseTesting.md`. These tests pin down the invariant that
/// matters for correctness and safety: **when the SDK isn't configured, every entry point is a safe,
/// non-crashing no-op that never touches `Purchases.shared`.**
@MainActor
final class PurchaseManagerTests: XCTestCase {

    func testInitialStateIsUnconfiguredAndNotPremium() {
        let manager = PurchaseManager()
        XCTAssertFalse(manager.hasPremium)
        XCTAssertFalse(manager.isConfigured)
        XCTAssertFalse(manager.isLoading)
        XCTAssertNil(manager.errorMessage)
    }

    func testPurchaseWhenUnconfiguredIsSafeNoOp() async {
        let manager = PurchaseManager()
        let result = await manager.purchase() // must not touch Purchases.shared / crash
        XCTAssertFalse(result)
        XCTAssertFalse(manager.hasPremium)
        XCTAssertFalse(manager.isLoading)
    }

    func testRestoreWhenUnconfiguredReturnsFalse() async {
        let manager = PurchaseManager()
        let result = await manager.restore()
        XCTAssertFalse(result)
        XCTAssertFalse(manager.hasPremium)
        XCTAssertFalse(manager.isLoading)
    }

    func testRefreshWhenUnconfiguredCompletesWithoutHanging() async {
        let manager = PurchaseManager()
        await manager.refresh() // returns immediately; no spinner left on, no crash
        XCTAssertFalse(manager.isLoading)
        XCTAssertFalse(manager.hasPremium)
    }

    /// The entitlement identifier the app gates on must match what will be configured in the
    /// RevenueCat dashboard.
    func testEntitlementIdentifier() {
        XCTAssertEqual(PurchaseManager.entitlementID, "premium")
    }
}
