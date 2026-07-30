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

    /// Every tier must be an equally safe no-op.
    func testPurchaseTierWhenUnconfiguredIsSafeNoOp() async {
        let manager = PurchaseManager()
        for tier in TipTier.allCases {
            // must not touch Purchases.shared / crash
            let result = await manager.purchase(tier: tier, source: .settings)
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

    // MARK: - Error messages

    /// The regression this exists for: the supporter sheet renders ``PurchaseManager/errorMessage``
    /// verbatim, and a misconfigured store used to put *"The operation couldn't be completed.
    /// (RevenueCat.ErrorCode error 23.)"* on screen — Foundation's placeholder, produced because a
    /// bare `ErrorCode` carries no `NSLocalizedDescriptionKey`.
    func testMessageForConfigurationErrorIsNotTheFoundationPlaceholder() {
        let message = PurchaseManager.userMessage(for: Self.publicError(.configurationError))
        XCTAssertEqual(message, "Tips aren't available right now — please try again later.")
    }

    /// Every code the SDK can throw must map to customer-readable copy: no Foundation placeholder, no
    /// RevenueCat internals, no documentation links. Covers codes added by future SDK versions too,
    /// since it walks `ErrorCode.allCases`.
    func testMessageForEveryErrorCodeIsPresentableToACustomer() {
        for code in ErrorCode.allCases {
            let message = PurchaseManager.userMessage(for: Self.publicError(code))
            XCTAssertFalse(message.isEmpty, "\(code) produced an empty message")
            XCTAssertFalse(
                message.contains("RevenueCat") || message.contains("couldn't be completed"),
                "\(code) leaked Foundation's placeholder: \(message)"
            )
            XCTAssertFalse(
                message.localizedCaseInsensitiveContains("rev.cat")
                    || message.contains("http")
                    || message.contains("API key")
                    || message.contains("dashboard"),
                "\(code) leaked developer-facing detail: \(message)"
            )
            XCTAssertTrue(message.hasSuffix("."), "\(code) should read as a sentence: \(message)")
        }
    }

    /// A few codes get their own copy because the customer can act on them; assert the distinctions
    /// hold rather than collapsing into the generic fallback.
    func testMessagesDistinguishTheActionableFailures() {
        let offline = PurchaseManager.userMessage(for: Self.publicError(.offlineConnectionError))
        XCTAssertEqual(offline, PurchaseManager.userMessage(for: Self.publicError(.networkError)))
        XCTAssertTrue(offline.contains("connection"))

        let notAllowed = PurchaseManager.userMessage(for: Self.publicError(.purchaseNotAllowedError))
        XCTAssertTrue(notAllowed.contains("Screen Time"))

        let pending = PurchaseManager.userMessage(for: Self.publicError(.paymentPendingError))
        XCTAssertTrue(pending.contains("approval"))

        // …and the buckets really are different messages.
        XCTAssertEqual(Set([offline, notAllowed, pending]).count, 3)
    }

    /// An error the SDK didn't produce takes the generic sentence rather than its own description.
    /// Asserting the literal copy matters: forwarding `localizedDescription` is what produced the bug
    /// in the first place, and a foreign `NSError` carrying no description of its own would land right
    /// back on Foundation's "(SomeDomain error -1234.)" placeholder.
    func testMessageForNonRevenueCatErrorIsGeneric() {
        XCTAssertEqual(PurchaseManager.userMessage(for: URLError(.notConnectedToInternet)),
                       "Something went wrong. Please try again.")

        let descriptionless = NSError(domain: "com.example.Whatever", code: -1234, userInfo: [:])
        XCTAssertTrue(descriptionless.localizedDescription.contains("error -1234"),
                      "precondition: a userInfo-less NSError yields Foundation's placeholder")
        XCTAssertEqual(PurchaseManager.userMessage(for: descriptionless),
                       "Something went wrong. Please try again.")
    }

    /// Guards the assumption the mapping is built on, straight from the SDK: a thrown `PublicError`
    /// **is** castable to `ErrorCode` (`PurchasesError.asPublicError`), yet the cast value's
    /// `localizedDescription` is the useless placeholder — which is exactly why
    /// ``PurchaseManager/userMessage(for:)`` can't just forward it. If a future SDK release gives
    /// `ErrorCode` an `NSLocalizedDescriptionKey`, this fails and the mapping can be reconsidered.
    func testRevenueCatPublicErrorBridgingAssumptions() throws {
        let error = Self.publicError(.configurationError)
        let code = try XCTUnwrap(error as? ErrorCode, "PublicError must be castable to ErrorCode")
        XCTAssertEqual(code, .configurationError)
        XCTAssertTrue(
            code.localizedDescription.contains("RevenueCat.ErrorCode error 23"),
            "unexpected bare-ErrorCode description: \(code.localizedDescription)"
        )
        // The rich text does exist on the thrown error — it's just not customer-facing.
        XCTAssertTrue(error.localizedDescription.contains("rev.cat"))
    }

    // MARK: - Fixtures

    /// A stand-in for what RevenueCat actually throws. `Purchases.offerings()` surfaces
    /// `result.error?.asPublicError`, and `PurchasesError.asPublicError` builds exactly this:
    /// `NSError(domain: ErrorCode.errorDomain, code: <code>, userInfo:)` with the code's description
    /// plus the internal message under `NSLocalizedDescriptionKey`. The message used here is the real
    /// one the SDK emits for this app's symptom (an offering whose products don't resolve), so the
    /// test exercises the true bridging behaviour rather than a synthetic error.
    private static func publicError(_ code: ErrorCode) -> Error {
        let internalMessage = """
        You have configured the SDK with an App Store API key, but there are no App Store products \
        registered in the RevenueCat dashboard for your offerings. \
        More information: https://rev.cat/why-are-offerings-empty
        """
        return NSError(
            domain: ErrorCode.errorDomain,
            code: code.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "\(code.description) \(internalMessage)",
                "readable_error_code": code.description
            ]
        )
    }

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
