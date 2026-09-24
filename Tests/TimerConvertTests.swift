import XCTest
import SwiftData
@testable import BabyBuddy

/// Covers the timer-specific repository helpers: stopping, resuming and discarding a timer, and
/// converting one into a duration-based activity both before and after the timer has synced.
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

    func testConvertSyncedTimerQueuesDeleteThenCreateWithoutTimerID() throws {
        let timer = try syncedTimer(id: 42)

        let activity = repo.convertTimer(timer, to: .tummyTime, payload: [
            "child": 1, "start": "2024-01-15T10:00:00-05:00", "end": "2024-01-15T10:15:00-05:00",
            "milestone": "", "tags": []])

        // With `timer` set the server would overwrite start and end (#145).
        XCTAssertNil(activity?.payloadObject["timer"])
        XCTAssertEqual(activity?.payloadObject["end"] as? String, "2024-01-15T10:15:00-05:00")

        let remaining = try entities()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.kind, .tummyTime)

        // The timer's own DELETE, ahead of the create and linked to it.
        let muts = try mutations().sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(muts.map(\.op), [.delete, .create])
        XCTAssertEqual(muts[0].serverID, 42)
        let link = try JSONSerialization.jsonObject(with: muts[0].payload) as? [String: Any]
        XCTAssertEqual(link?["loggedAs"] as? String, activity?.localID.uuidString)
    }

    // MARK: Stop

    func testStopFreezesTimerAndQueuesItsDelete() throws {
        let timer = try syncedTimer(id: 42)
        let tapped = Date(timeIntervalSince1970: 1_705_331_700)

        repo.stopTimer(timer, at: tapped)

        XCTAssertEqual(timer.stoppedAt, tapped)
        XCTAssertFalse(timer.isRunningTimer)
        XCTAssertEqual(try entities().count, 1, "a stopped draft until it's logged")
        XCTAssertEqual(try mutations().map(\.op), [.delete])
        XCTAssertEqual(timer.stoppedTimerPayload()["end"] as? String, APIDate.isoDateTime.string(from: tapped))

        repo.stopTimer(timer, at: .now) // a second Stop changes nothing
        XCTAssertEqual(timer.stoppedAt, tapped)
        XCTAssertEqual(try mutations().count, 1)
    }

    func testResumeBeforeTheDeleteGoesOutCancelsIt() throws {
        let timer = try syncedTimer(id: 42)
        repo.stopTimer(timer)

        repo.resumeTimer(timer)

        XCTAssertTrue(timer.isRunningTimer)
        XCTAssertEqual(timer.serverID, 42)
        XCTAssertTrue(try mutations().isEmpty)
    }

    func testStopUnsyncedTimerDropsItsCreate() throws {
        let timer = repo.create(kind: .timer, payload: [
            "child": 1, "name": "Sleep", "start": "2024-01-15T10:00:00-05:00"])!

        repo.stopTimer(timer)
        XCTAssertTrue(try mutations().isEmpty, "the server never saw it")

        repo.resumeTimer(timer)
        XCTAssertEqual(try mutations().map(\.op), [.create], "so Resume files it afresh")
    }

    func testDiscardStoppedTimerKeepsItsDelete() throws {
        let timer = try syncedTimer(id: 42)
        repo.stopTimer(timer)

        repo.discardStoppedTimer(timer)

        XCTAssertTrue(try entities().isEmpty)
        XCTAssertEqual(try mutations().map(\.op), [.delete])
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
