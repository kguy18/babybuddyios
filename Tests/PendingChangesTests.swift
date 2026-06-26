import XCTest
import SwiftData
@testable import BabyBuddy

/// Covers `LocalRepository.discardPending` — cancelling a queued write reverts the cached
/// record to the server's last-known state, per op type.
@MainActor
final class PendingChangesTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: LocalRepository!
    private let iso = "2024-01-15T10:00:00-05:00"

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
        repo = LocalRepository(context: context)
    }

    private func pendingCount() -> Int {
        (try? context.fetch(FetchDescriptor<PendingMutation>()))?.count ?? 0
    }

    private func data(_ o: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
    }

    func testDiscardCreateDropsRecordAndMutation() throws {
        // A never-synced create: the record exists only locally.
        let entity = LocalEntity(kind: .feeding, serverID: nil, childID: 1, timestamp: .now,
                                 payload: data(["child": 1, "start": iso]), syncState: .pendingCreate)
        context.insert(entity)
        let mutation = PendingMutation(localID: entity.localID, kind: .feeding, op: .create,
                                       payload: entity.payload)
        context.insert(mutation)
        try context.save()

        repo.discardPending(mutation)

        XCTAssertEqual(pendingCount(), 0)
        XCTAssertNil(LocalStore.fetch(localID: entity.localID, in: context))  // record gone
    }

    func testDiscardUpdateRevertsToBaseSnapshot() throws {
        let base = data(["id": 5, "child": 1, "amount": 90, "start": iso])
        let entity = LocalEntity(kind: .feeding, serverID: 5, childID: 1, timestamp: .now,
                                 payload: base, syncState: .synced, baseSnapshot: base)
        context.insert(entity)

        repo.update(entity, payload: ["id": 5, "child": 1, "amount": 150, "start": iso])
        XCTAssertEqual(entity.syncState, .pendingUpdate)
        XCTAssertEqual(entity.payloadObject["amount"] as? Int, 150)

        let mutation = try XCTUnwrap((try context.fetch(FetchDescriptor<PendingMutation>())).first)
        repo.discardPending(mutation)

        XCTAssertEqual(pendingCount(), 0)
        XCTAssertEqual(entity.syncState, .synced)
        XCTAssertEqual(entity.payloadObject["amount"] as? Int, 90)  // restored to the server value
    }

    func testDiscardDeleteRestoresRecord() throws {
        let payload = data(["id": 7, "child": 1, "start": iso])
        let entity = LocalEntity(kind: .sleep, serverID: 7, childID: 1, timestamp: .now,
                                 payload: payload, syncState: .synced, baseSnapshot: payload)
        context.insert(entity)

        repo.delete(entity)
        XCTAssertEqual(entity.syncState, .pendingDelete)

        let mutation = try XCTUnwrap((try context.fetch(FetchDescriptor<PendingMutation>())).first)
        XCTAssertEqual(mutation.op, .delete)
        repo.discardPending(mutation)

        XCTAssertEqual(pendingCount(), 0)
        XCTAssertEqual(entity.syncState, .synced)  // un-hidden, still on the server
        XCTAssertNotNil(LocalStore.fetch(localID: entity.localID, in: context))
    }
}
