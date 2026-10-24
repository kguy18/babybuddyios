import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class StartTimerTests: XCTestCase {
    func testQuickStartTracksAllRunningActivities() {
        let container = LocalStore.makeContainer(inMemory: true)
        let repo = LocalRepository(context: container.mainContext)
        let sleep = repo.create(kind: .timer, payload: ["name": "Nap"], timerActivity: .sleep)!
        let feeding = repo.create(kind: .timer, payload: ["name": "Feeding"])!
        let anotherSleep = repo.create(kind: .timer, payload: ["name": "Sleep"])!
        let unknown = repo.create(kind: .timer, payload: ["name": "Custom"])!

        func running(_ timers: [LocalEntity]) -> Set<TimerActivity> {
            Set(TimerActivity.runningActivities(in: timers, childID: nil).keys)
        }
        XCTAssertEqual(running([sleep, feeding, anotherSleep, unknown]), Set([.sleep, .feeding]))
        sleep.stoppedAt = .now
        XCTAssertEqual(running([sleep, anotherSleep]), Set([.sleep]))
        anotherSleep.syncState = .pendingDelete
        feeding.stoppedAt = .now
        XCTAssertTrue(running([sleep, feeding, anotherSleep, unknown]).isEmpty)
    }

    func testQuickStartIgnoresCompletedRecords() {
        let container = LocalStore.makeContainer(inMemory: true)
        let record = LocalRepository(context: container.mainContext).create(
            kind: .sleep, payload: ["name": "Sleep"])!
        XCTAssertTrue(TimerActivity.runningActivities(in: [record], childID: nil).isEmpty)
        XCTAssertTrue(TimerActivity.runningActivities(in: [], childID: nil).isEmpty)
    }

    /// Only the selected child's timers count; with no child selected (nil or 0) only unassigned
    /// ones do, since that's where `StartTimerIntent` puts a timer then.
    func testQuickStartCountsOnlySelectedChildsTimers() {
        let container = LocalStore.makeContainer(inMemory: true)
        let repo = LocalRepository(context: container.mainContext)
        let timers = [
            repo.create(kind: .timer, payload: ["name": "Sleep", "child": 1])!,
            repo.create(kind: .timer, payload: ["name": "Feeding", "child": 2])!,
            repo.create(kind: .timer, payload: ["name": "Pumping"])!,
        ]

        XCTAssertEqual(Set(TimerActivity.runningActivities(in: timers, childID: 1).keys), [.sleep])
        XCTAssertEqual(Set(TimerActivity.runningActivities(in: timers, childID: 2).keys), [.feeding])
        XCTAssertEqual(Set(TimerActivity.runningActivities(in: timers, childID: nil).keys), [.pumping])
        XCTAssertEqual(Set(TimerActivity.runningActivities(in: timers, childID: 0).keys), [.pumping])
        XCTAssertEqual(TimerActivity.runningTimers(in: timers, childID: 1).map(\.localID), [timers[0].localID])
    }

    /// A running tile and the Active Timer widget open the newest running timer.
    func testRunningTimerToOpenIsTheNewest() {
        let container = LocalStore.makeContainer(inMemory: true)
        let repo = LocalRepository(context: container.mainContext)
        func sleep(startedAgo seconds: TimeInterval, child: Int) -> LocalEntity {
            repo.create(kind: .timer, payload: [
                "name": "Sleep", "child": child,
                "start": APIDate.isoDateTime.string(from: .now.addingTimeInterval(-seconds)),
            ])!
        }
        let older = sleep(startedAgo: 3600, child: 1)
        let newer = sleep(startedAgo: 60, child: 1)
        let otherChild = sleep(startedAgo: 1, child: 2)
        let timers = [older, otherChild, newer]

        XCTAssertEqual(TimerActivity.runningActivities(in: timers, childID: 1)[.sleep], newer.localID)
        XCTAssertEqual(TimerActivity.runningTimers(in: timers, childID: 1).first?.localID, newer.localID)
        newer.stoppedAt = .now
        XCTAssertEqual(TimerActivity.runningActivities(in: timers, childID: 1)[.sleep], older.localID)
    }

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
    /// it creates the record, queues the timer's DELETE ahead of it and removes the local timer.
    /// Mirrors `LogTimerIntent`'s use of `convertTimer`.
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
        XCTAssertNil(sleeps.first?.payloadObject["timer"]) // the server would overwrite the end (#145)

        let mutations = try context.fetch(FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(mutations.map(\.kind), [.timer, .sleep])
        XCTAssertEqual(mutations.map(\.op), [.delete, .create])
    }
}
