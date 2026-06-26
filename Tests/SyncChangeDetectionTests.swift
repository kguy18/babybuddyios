import XCTest
import SwiftData
@testable import BabyBuddy

/// Covers the change-detection that gates the `Sync.completed` analytics signal: unchanged
/// server records must not dirty the store on re-pull, and a running timer's volatile
/// `duration` must not register as a change.
@MainActor
final class SyncChangeDetectionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func json(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: payloadsEquivalent

    func testEquivalentIgnoresKeyOrder() {
        let a = json(["id": 1, "child": 2, "note": "hi"])
        let b = json(["note": "hi", "id": 1, "child": 2])
        XCTAssertTrue(LocalStore.payloadsEquivalent(a, b))
    }

    func testEquivalentIgnoresVolatileDuration() {
        let a = json(["id": 1, "child": 2, "start": "2024-01-15T10:00:00-05:00", "duration": "00:00:03"])
        let b = json(["id": 1, "child": 2, "start": "2024-01-15T10:00:00-05:00", "duration": "00:05:41"])
        XCTAssertTrue(LocalStore.payloadsEquivalent(a, b), "a running timer's drifting duration is not a change")
    }

    func testDifferentValuesAreNotEquivalent() {
        let a = json(["id": 1, "child": 2, "note": "hi"])
        let b = json(["id": 1, "child": 2, "note": "bye"])
        XCTAssertFalse(LocalStore.payloadsEquivalent(a, b))
    }

    // MARK: upsertFromServer change behavior

    func testUnchangedRepullDoesNotDirtyStore() throws {
        let payload = json(["id": 100, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "a"])
        _ = LocalStore.upsertFromServer(payload, kind: .note, in: context)
        try context.save()
        XCTAssertFalse(context.hasChanges)

        // Re-pulling the identical record must be a no-op (no write churn → meaningful hasChanges).
        _ = LocalStore.upsertFromServer(payload, kind: .note, in: context)
        XCTAssertFalse(context.hasChanges, "an unchanged re-pull should not dirty the store")
    }

    func testChangedRepullDirtiesStore() throws {
        let original = json(["id": 100, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "a"])
        _ = LocalStore.upsertFromServer(original, kind: .note, in: context)
        try context.save()
        XCTAssertFalse(context.hasChanges)

        let edited = json(["id": 100, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "edited"])
        _ = LocalStore.upsertFromServer(edited, kind: .note, in: context)
        XCTAssertTrue(context.hasChanges, "a real server change should dirty the store")
    }

    func testNewRecordDirtiesStore() {
        let payload = json(["id": 200, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "new"])
        _ = LocalStore.upsertFromServer(payload, kind: .note, in: context)
        XCTAssertTrue(context.hasChanges, "inserting a new record is a change")
    }
}
