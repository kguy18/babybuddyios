import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class QuickLogFeedbackTests: XCTestCase {
    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private var domain: String!
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        domain = "QuickLogFeedbackTests.\(UUID())"
        defaults = UserDefaults(suiteName: domain)!
    }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: domain) }

    private func record(_ action: QuickLogAction = .wetDiaper, child: Int = 1) throws -> LocalEntity {
        let entity = LocalRepository(context: container.mainContext).create(
            kind: action.kind, payload: action.payload(childID: child, now: now))!
        try container.mainContext.save()
        QuickLogFeedback.record(action: action, entityID: entity.localID, childID: child, now: now, in: defaults)
        return entity
    }
    private func receipt(child: Int? = 1, after seconds: Double = 0) -> QuickLogReceipt? {
        QuickLogFeedback.visible(in: container.mainContext, childID: child,
                                 now: now.addingTimeInterval(seconds), defaults: defaults)
    }

    func testOfflineSavedEntryGetsReceiptAndStillQueuesSync() throws {
        let entity = try record()
        XCTAssertEqual(receipt()?.entityID, entity.localID)
        XCTAssertEqual(receipt()?.action, .wetDiaper)
        XCTAssertEqual(entity.syncState, .pendingCreate)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PendingMutation>()).count, 1)
    }

    func testReceiptExpiresAndRejectsFutureClock() throws {
        _ = try record()
        XCTAssertNotNil(receipt(after: 119))
        XCTAssertNil(receipt(after: 120))
        XCTAssertNil(receipt(after: -1))
    }

    func testChildSwitchHidesPreviousReceipt() throws {
        _ = try record()
        XCTAssertNil(receipt(child: 2))
        XCTAssertNil(receipt(child: nil))
        XCTAssertNotNil(receipt(child: 1))
    }

    func testUndoOrDeletionHidesReceipt() throws {
        let entity = try record()
        entity.syncState = .pendingDelete
        XCTAssertNil(receipt())
        container.mainContext.delete(entity)
        try container.mainContext.save()
        XCTAssertNil(receipt())
    }

    func testLatestActionReplacesReceipt() throws {
        _ = try record()
        let second = try record(.quickFeed)
        XCTAssertEqual(receipt()?.action, .quickFeed)
        XCTAssertEqual(receipt()?.entityID, second.localID)
    }

    func testTurnOffAndClear() throws {
        _ = try record()
        defaults.set(false, forKey: QuickLogFeedback.enabledKey)
        XCTAssertNil(receipt())
        defaults.set(true, forKey: QuickLogFeedback.enabledKey)
        XCTAssertNotNil(receipt())
        QuickLogFeedback.clear(in: defaults)
        XCTAssertNil(receipt())
    }

    func testCorruptOrMissingReceiptDoesNotShowSuccess() {
        XCTAssertNil(receipt())
        defaults.set(Data("invalid".utf8), forKey: QuickLogFeedback.receiptKey)
        XCTAssertNil(receipt())
        QuickLogFeedback.record(action: .wetDiaper, entityID: UUID(), childID: 1, now: now, in: defaults)
        XCTAssertNil(receipt())
    }

    func testLeavingServerClearsReceipt() throws {
        let old = SharedDefaults.suite.data(forKey: QuickLogFeedback.receiptKey)
        let child = SharedDefaults.selectedChildID
        defer {
            SharedDefaults.suite.set(old, forKey: QuickLogFeedback.receiptKey)
            SharedDefaults.selectedChildID = child
        }
        QuickLogFeedback.record(action: .wetDiaper, entityID: UUID(), childID: 1, now: now)
        LocalStore.wipe(in: container.mainContext)
        XCTAssertNil(SharedDefaults.suite.data(forKey: QuickLogFeedback.receiptKey))
    }
}
