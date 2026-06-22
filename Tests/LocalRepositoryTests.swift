import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class LocalRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: LocalRepository!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
        repo = LocalRepository(context: context)
    }

    private func mutations() throws -> [PendingMutation] {
        try context.fetch(FetchDescriptor<PendingMutation>())
    }
    private func entities() throws -> [LocalEntity] {
        try context.fetch(FetchDescriptor<LocalEntity>())
    }

    func testCreateInsertsPendingCreate() throws {
        let entity = repo.create(kind: .feeding, payload: [
            "child": 1, "start": "2024-01-15T10:00:00-05:00", "end": "2024-01-15T10:20:00-05:00",
            "type": "formula", "method": "bottle",
        ])
        XCTAssertEqual(entity?.syncState, .pendingCreate)
        XCTAssertNil(entity?.serverID)
        XCTAssertEqual(entity?.childID, 1)
        let muts = try mutations()
        XCTAssertEqual(muts.count, 1)
        XCTAssertEqual(muts.first?.op, .create)
    }

    func testUpdateCoalescesWithPendingCreate() throws {
        let entity = repo.create(kind: .note, payload: ["child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "a"])!
        repo.update(entity, payload: ["child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "b"])

        // Still a single create mutation, payload refreshed; state stays pendingCreate.
        let muts = try mutations()
        XCTAssertEqual(muts.count, 1)
        XCTAssertEqual(muts.first?.op, .create)
        XCTAssertEqual(entity.syncState, .pendingCreate)
        XCTAssertEqual(entity.payloadObject["note"] as? String, "b")
    }

    func testDeleteUnsyncedRemovesEverything() throws {
        let entity = repo.create(kind: .note, payload: ["child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "x"])!
        repo.delete(entity)
        XCTAssertEqual(try entities().count, 0)
        XCTAssertEqual(try mutations().count, 0)
    }

    func testDeleteSyncedEnqueuesDelete() throws {
        // Simulate a synced record pulled from the server.
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": 99, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "x"])
        let entity = LocalStore.upsertFromServer(payload, kind: .note, in: context)!
        XCTAssertEqual(entity.syncState, .synced)

        repo.delete(entity)
        XCTAssertEqual(entity.syncState, .pendingDelete)
        let muts = try mutations()
        XCTAssertEqual(muts.count, 1)
        XCTAssertEqual(muts.first?.op, .delete)
        XCTAssertEqual(muts.first?.serverID, 99)
    }

    func testPullDoesNotClobberLocalEdit() throws {
        // A locally edited (pendingUpdate) record must survive a re-pull of the server version.
        let original = try JSONSerialization.data(withJSONObject: [
            "id": 7, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "server"])
        let entity = LocalStore.upsertFromServer(original, kind: .note, in: context)!
        repo.update(entity, payload: ["id": 7, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "mine"])
        XCTAssertEqual(entity.syncState, .pendingUpdate)

        // Server still has the old value; a pull must not overwrite the local edit.
        LocalStore.upsertFromServer(original, kind: .note, in: context)
        XCTAssertEqual(entity.payloadObject["note"] as? String, "mine")
    }
}
