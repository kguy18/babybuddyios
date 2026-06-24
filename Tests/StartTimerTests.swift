import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class StartTimerTests: XCTestCase {
    func testActivityMapping() {
        XCTAssertEqual(TimerActivity.tummyTime.timerName, "Tummy time")
        XCTAssertEqual(TimerActivity.feeding.convertKind, .feeding)
        XCTAssertEqual(TimerActivity.sleep.systemImage, EntityKind.sleep.systemImage)
    }

    /// The Quick Start widget relies on `LocalRepository.create` turning the timer payload
    /// into a pending-create timer with the right child — mirror the payload the intent builds.
    func testStartingTimerEnqueuesPendingCreate() throws {
        let container = LocalStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let payload: [String: Any] = [
            "start": APIDate.isoDateTime.string(from: .now),
            "name": TimerActivity.sleep.timerName,
            "child": 3,
        ]
        LocalRepository(context: context).create(kind: .timer, payload: payload)

        let timers = try context.fetch(
            FetchDescriptor<LocalEntity>(predicate: #Predicate { $0.kindRaw == "timer" }))
        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers.first?.childID, 3)
        XCTAssertEqual(timers.first?.syncState, .pendingCreate)
        XCTAssertNotEqual(timers.first?.timestamp, .distantPast) // start parsed → real timestamp

        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        XCTAssertEqual(mutations.count, 1)
        XCTAssertEqual(mutations.first?.op, .create)
        XCTAssertEqual(mutations.first?.kind, .timer)
    }

    func testInstantLoggableActivities() {
        // Verified against the live API: sleep/tummy time log from start+end alone; feeding
        // (type/method) and pumping (amount) need a form.
        XCTAssertTrue(TimerActivity.sleep.isInstantLoggable)
        XCTAssertTrue(TimerActivity.tummyTime.isInstantLoggable)
        XCTAssertFalse(TimerActivity.feeding.isInstantLoggable)
        XCTAssertFalse(TimerActivity.pumping.isInstantLoggable)
    }

    /// The Active Timer widget's Stop button logs a sleep/tummy timer as a completed activity:
    /// it creates the record (carrying the server `timer` id so the server deletes the timer)
    /// and removes the local timer. Mirrors `LogTimerIntent`'s use of `convertTimer`.
    func testLoggingSyncedSleepTimerCreatesActivityAndRemovesTimer() throws {
        let container = LocalStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let serverPayload = try JSONSerialization.data(withJSONObject: [
            "id": 7, "child": 1, "name": "Sleep", "start": "2026-06-24T09:00:00-05:00",
        ])
        let timer = LocalStore.upsertFromServer(serverPayload, kind: .timer, in: context)!

        LocalRepository(context: context).convertTimer(timer, to: .sleep, payload: [
            "child": 1,
            "start": "2026-06-24T09:00:00-05:00",
            "end": APIDate.isoDateTime.string(from: .now),
        ])

        // Timer removed locally; one sleep activity created as a pending create.
        XCTAssertTrue(try context.fetch(
            FetchDescriptor<LocalEntity>(predicate: #Predicate { $0.kindRaw == "timer" })).isEmpty)
        let sleeps = try context.fetch(
            FetchDescriptor<LocalEntity>(predicate: #Predicate { $0.kindRaw == "sleep" }))
        XCTAssertEqual(sleeps.count, 1)
        XCTAssertEqual(sleeps.first?.syncState, .pendingCreate)
        XCTAssertEqual(sleeps.first?.payloadObject["timer"] as? Int, 7) // server deletes the timer on POST

        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        XCTAssertEqual(mutations.map(\.kind), [.sleep])
        XCTAssertEqual(mutations.first?.op, .create)
    }
}
