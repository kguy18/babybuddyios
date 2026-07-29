import XCTest
import RevenueCat
@testable import BabyBuddy

/// Covers the two halves of ``PurchaseManager`` that *can* be tested without live StoreKit:
///
/// 1. **Resilience when purchases are not configured** — the state a build is in before `start()`
///    runs, when no API key is present (open-source/clone builds), in demo mode, and effectively
///    when launched offline before the SDK has any cached customer info. Every entry point must be
///    a safe, non-crashing no-op that never touches `Purchases.shared`.
/// 2. **The supporter rule** — ``PurchaseManager/isSupporter(from:)``, the pure derivation of
///    supporter status from a `CustomerInfo` snapshot.
///
/// The purchase/restore/refresh flows themselves run against RevenueCat's `Purchases.shared`
/// singleton, which cannot be mocked in a unit test (it would require live StoreKit + network).
/// Those paths — a successful tip, a restore, RevenueCat errors, and network timeouts — are covered
/// by the manual procedures in `Docs/InAppPurchaseTesting.md`.
@MainActor
final class PurchaseManagerTests: XCTestCase {

    #if DEBUG
    private var savedDebugOverride = false

    /// The DEBUG "Supporter mode" switch persists in `UserDefaults`, and these tests are hosted by
    /// the app — so they share its defaults. Without this, a developer who left the switch on in the
    /// simulator would fail every assertion about the default (non-supporter) state. Neutralize it
    /// for the duration and put it back afterwards, so running tests doesn't silently change their
    /// setting either.
    override func setUp() async throws {
        savedDebugOverride = PurchaseManager().debugForcedSupporter
        PurchaseManager().setDebugSupporter(false)
    }

    override func tearDown() async throws {
        PurchaseManager().setDebugSupporter(savedDebugOverride)
    }
    #endif

    func testInitialStateIsUnconfiguredAndNotSupporter() {
        let manager = PurchaseManager()
        XCTAssertFalse(manager.isSupporter)
        XCTAssertFalse(manager.isConfigured)
        XCTAssertFalse(manager.isLoading)
        XCTAssertNil(manager.errorMessage)
        XCTAssertTrue(manager.tips.isEmpty)
    }

    func testPurchaseWhenUnconfiguredIsSafeNoOp() async {
        let manager = PurchaseManager()
        let result = await manager.purchase() // must not touch Purchases.shared / crash
        XCTAssertFalse(result)
        XCTAssertFalse(manager.isSupporter)
        XCTAssertFalse(manager.isLoading)
    }

    /// Every tier must be an equally safe no-op, not just the one the shim buys.
    func testPurchaseTierWhenUnconfiguredIsSafeNoOp() async {
        let manager = PurchaseManager()
        for tier in TipTier.allCases {
            let result = await manager.purchase(tier: tier)
            XCTAssertFalse(result, "\(tier) should be a no-op when unconfigured")
            XCTAssertFalse(manager.isSupporter)
            XCTAssertFalse(manager.isLoading)
        }
    }

    func testRestoreWhenUnconfiguredReturnsFalse() async {
        let manager = PurchaseManager()
        let result = await manager.restore()
        XCTAssertFalse(result)
        XCTAssertFalse(manager.isSupporter)
        XCTAssertFalse(manager.isLoading)
    }

    func testRefreshWhenUnconfiguredCompletesWithoutHanging() async {
        let manager = PurchaseManager()
        await manager.refresh() // returns immediately; no spinner left on, no crash
        XCTAssertFalse(manager.isLoading)
        XCTAssertFalse(manager.isSupporter)
    }

    /// The entitlement identifier the app reads must match what is configured in the RevenueCat
    /// dashboard, and the package identifiers must match the offering's custom packages.
    func testStoreIdentifiers() {
        XCTAssertEqual(PurchaseManager.entitlementID, "supporter")
        XCTAssertEqual(TipTier.small.packageIdentifier, "tip.small")
        XCTAssertEqual(TipTier.medium.packageIdentifier, "tip.medium")
        XCTAssertEqual(TipTier.large.packageIdentifier, "tip.large")
        XCTAssertEqual(TipTier.allCases, [.small, .medium, .large]) // ordered small → large
    }

    // MARK: - The supporter rule

    /// No customer info yet (launch, offline, or purchases disabled) → not a supporter. Nothing is
    /// gated on this, but the thank-you state must not appear for someone who hasn't tipped.
    func testIsSupporterDefaultsToFalse() {
        XCTAssertFalse(PurchaseManager.isSupporter(from: nil))
    }

    /// An active `supporter` entitlement is the intended signal.
    func testIsSupporterWhenEntitlementIsActive() {
        let info = Self.customerInfo(entitlements: [
            PurchaseManager.entitlementID: Self.entitlement(isActive: true)
        ])
        XCTAssertTrue(PurchaseManager.isSupporter(from: info))
    }

    /// An entitlement that has lapsed (or one we don't read) must not grant supporter status.
    func testIsSupporterWhenEntitlementIsInactiveOrUnrelated() {
        let expired = Self.customerInfo(entitlements: [
            PurchaseManager.entitlementID: Self.entitlement(isActive: false)
        ])
        XCTAssertFalse(PurchaseManager.isSupporter(from: expired))

        let other = Self.customerInfo(entitlements: [
            "something-else": Self.entitlement(isActive: true)
        ])
        XCTAssertFalse(PurchaseManager.isSupporter(from: other))
    }

    /// Belt and braces: a tip recorded as a non-subscription purchase counts even when the dashboard
    /// hasn't attached the product to the entitlement, so a misconfiguration can't strand a tipper.
    func testIsSupporterWhenNonSubscriptionPurchaseExistsWithNoEntitlement() throws {
        let info = try Self.customerInfoWithTip(productID: "com.kurtisguy.BabyBuddy.tip.small")
        XCTAssertTrue(info.entitlements.all.isEmpty, "fixture should carry no entitlement")
        XCTAssertFalse(info.nonSubscriptions.isEmpty, "fixture should carry the tip")
        XCTAssertTrue(PurchaseManager.isSupporter(from: info))
    }

    // MARK: - Fixtures

    private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Built with RevenueCat's public unit-testing initializers — no wire format involved.
    private static func customerInfo(entitlements: [String: EntitlementInfo]) -> CustomerInfo {
        CustomerInfo(
            entitlements: EntitlementInfos(entitlements: entitlements),
            requestDate: referenceDate,
            firstSeen: referenceDate,
            originalAppUserId: "test-user"
        )
    }

    private static func entitlement(isActive: Bool) -> EntitlementInfo {
        EntitlementInfo(
            identifier: PurchaseManager.entitlementID,
            isActive: isActive,
            willRenew: false,
            periodType: .normal,
            store: .appStore,
            productIdentifier: "com.kurtisguy.BabyBuddy.tip.medium",
            isSandbox: true,
            ownershipType: .purchased
        )
    }

    /// A customer whose only purchase is a consumable tip, and who has **no** entitlements.
    ///
    /// Decoded from a backend payload because RevenueCat's public test initializer above can only
    /// populate entitlements — `nonSubscriptions` has no public constructor. `CustomerInfo` is
    /// `Codable`, so this decodes the same shape the SDK receives from the server; the decoder is
    /// configured to match (snake-case keys, ISO-8601 dates).
    private static func customerInfoWithTip(productID: String) throws -> CustomerInfo {
        let json = """
        {
          "request_date": "2023-11-14T22:13:20Z",
          "subscriber": {
            "original_app_user_id": "test-user",
            "first_seen": "2023-11-14T22:13:20Z",
            "management_url": null,
            "subscriptions": {},
            "entitlements": {},
            "non_subscriptions": {
              "\(productID)": [
                {
                  "id": "test-transaction",
                  "store_transaction_id": "2000000000000001",
                  "purchase_date": "2023-11-14T22:13:20Z",
                  "original_purchase_date": "2023-11-14T22:13:20Z",
                  "store": "app_store",
                  "is_sandbox": true
                }
              ]
            }
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CustomerInfo.self, from: Data(json.utf8))
    }
}
