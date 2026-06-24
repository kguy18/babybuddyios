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
}
