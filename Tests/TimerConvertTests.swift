import XCTest
import SwiftData
@testable import BabyBuddy

/// Covers the timer-specific repository helpers: removing a record locally without a server
/// delete, and converting a running timer into a duration-based activity both before and
/// after the timer has synced.
@MainActor
final class TimerConvertTests: XCTestCase {
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

    /// A synced timer pulled from the server.
    private func syncedTimer(id: Int) throws -> LocalEntity {
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": id, "child": 1, "name": "Tummy time", "start": "2024-01-15T10:00:00-05:00"])
        return LocalStore.upsertFromServer(payload, kind: .timer, in: context)!
    }

    private func activityPayload() -> [String: Any] {
        ["child": 1, "start": "2024-01-15T10:00:00-05:00", "end": "2024-01-15T10:15:00-05:00",
         "type": "breast milk", "method": "left breast", "tags": []]
    }

    // MARK: removeLocally

    func testRemoveLocallyDropsUnsyncedEntityAndItsCreate() throws {
        let timer = repo.create(kind: .timer, payload: ["child": 1, "name": "x", "start": "2024-01-15T10:00:00-05:00"])!
        XCTAssertEqual(try mutations().count, 1)   // queued create

        repo.removeLocally(timer)
        XCTAssertEqual(try entities().count, 0)
        XCTAssertEqual(try mutations().count, 0)   // create dropped, no delete enqueued
    }

    func testRemoveLocallySyncedDoesNotEnqueueDelete() throws {
        let timer = try syncedTimer(id: 40)
        XCTAssertEqual(timer.syncState, .synced)

        repo.removeLocally(timer)
        XCTAssertEqual(try entities().count, 0)
        XCTAssertEqual(try mutations().count, 0)   // crucially: no pendingDelete mutation
    }

    // MARK: convertTimer — unsynced

    func testConvertUnsyncedTimerPostsPlainActivityAndRemovesTimer() throws {
        let timer = repo.create(kind: .timer, payload: [
            "child": 1, "name": "Tummy time", "start": "2024-01-15T10:00:00-05:00"])!

        let activity = repo.convertTimer(timer, to: .feeding, payload: activityPayload())

        // Timer is gone; only the new activity remains.
        let remaining = try entities()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.kind, .feeding)
        XCTAssertEqual(activity?.syncState, .pendingCreate)

        // No server timer existed, so the activity must NOT carry a `timer` id.
        XCTAssertNil(activity?.payloadObject["timer"])

        // Exactly one queued mutation: the activity create. The timer's create was dropped
        // (so it never reaches the server) and no delete was enqueued.
        let muts = try mutations()
        XCTAssertEqual(muts.count, 1)
        XCTAssertEqual(muts.first?.op, .create)
        XCTAssertEqual(muts.first?.kind, .feeding)
    }

    // MARK: convertTimer — synced

    func testConvertSyncedTimerCarriesTimerIDAndRemovesTimerLocally() throws {
        let timer = try syncedTimer(id: 42)

        let activity = repo.convertTimer(timer, to: .tummyTime, payload: [
            "child": 1, "start": "2024-01-15T10:00:00-05:00", "end": "2024-01-15T10:15:00-05:00",
            "milestone": "", "tags": []])

        // The activity payload carries the write-only timer id so the server converts + deletes.
        XCTAssertEqual(activity?.payloadObject["timer"] as? Int, 42)

        // The local timer is removed immediately (server will delete it during the POST).
        let remaining = try entities()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.kind, .tummyTime)

        // Only the activity create is queued — no DELETE racing the conversion.
        let muts = try mutations()
        XCTAssertEqual(muts.count, 1)
        XCTAssertEqual(muts.first?.op, .create)
        XCTAssertEqual(muts.first?.kind, .tummyTime)
    }

    func testConvertInheritsTimerStart() throws {
        // The convert flow pre-fills start from the timer; verify the payload we hand the
        // repository round-trips the timer's start onto the activity.
        let timer = try syncedTimer(id: 7)
        let timerStart = timer.payloadObject["start"] as? String

        let activity = repo.convertTimer(timer, to: .feeding, payload: activityPayload())
        XCTAssertEqual(activity?.payloadObject["start"] as? String, timerStart)
    }
}
