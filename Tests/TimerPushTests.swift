import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class TimerPushTests: XCTestCase {
    /// Reconcile applies the server's create response onto the local entity: server id, synced
    /// state, and the payload/base snapshot. Shared with SyncEngine, used after an immediate push.
    func testReconcileAppliesServerResponse() throws {
        let container = LocalStore.makeContainer(inMemory: true)
        let context = container.mainContext
        LocalRepository(context: context).create(kind: .timer, payload: [
            "name": "Sleep", "start": "2026-06-24T09:00:00-05:00", "child": 1,
        ])
        let entity = try XCTUnwrap(try context.fetch(
            FetchDescriptor<LocalEntity>(predicate: #Predicate { $0.kindRaw == "timer" })).first)
        XCTAssertNil(entity.serverID)

        let response = try JSONSerialization.data(withJSONObject: [
            "id": 99, "name": "Sleep", "start": "2026-06-24T09:05:00-05:00", "child": 1,
        ])
        TimerPush.reconcile(response, into: entity)

        XCTAssertEqual(entity.serverID, 99)
        XCTAssertEqual(entity.syncState, .synced)
        XCTAssertEqual(entity.baseSnapshot, response)
        XCTAssertEqual(entity.payload, response)
    }

    func testNewMutationIsUnclaimed() throws {
        let container = LocalStore.makeContainer(inMemory: true)
        let context = container.mainContext
        LocalRepository(context: context).create(kind: .timer, payload: ["name": "Sleep", "child": 1])
        let mutation = try context.fetch(FetchDescriptor<PendingMutation>()).first
        XCTAssertNil(mutation?.claimedAt)
    }
}
