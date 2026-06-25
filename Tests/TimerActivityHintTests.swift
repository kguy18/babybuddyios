import XCTest
import SwiftData
@testable import BabyBuddy

/// Covers the timer→activity hint that lets Stop auto-file a timer to the kind chosen at start,
/// and its hint-first / name-fallback resolution.
@MainActor
final class TimerActivityHintTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: LocalRepository!
    private let iso = "2024-01-15T10:00:00-05:00"

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
        repo = LocalRepository(context: context)
    }

    func testConvertKindInitMapsBackToActivity() {
        XCTAssertEqual(TimerActivity(convertKind: .feeding), .feeding)
        XCTAssertEqual(TimerActivity(convertKind: .tummyTime), .tummyTime)
        XCTAssertNil(TimerActivity(convertKind: .note))      // not a timer activity
        XCTAssertNil(TimerActivity(convertKind: .change))
    }

    func testCreatePersistsTimerActivityHint() {
        let timer = repo.create(kind: .timer, payload: ["child": 1, "start": iso], timerActivity: .sleep)
        XCTAssertEqual(timer?.timerActivityRaw, "sleep")
    }

    func testHintWinsOverCustomName() {
        // A sleep timer the user named "Afternoon nap" must still resolve to sleep for auto-filing.
        let timer = repo.create(kind: .timer,
                                payload: ["child": 1, "start": iso, "name": "Afternoon nap"],
                                timerActivity: .sleep)!
        XCTAssertEqual(TimerActivity(timer: timer), .sleep)
    }

    func testFallsBackToNameWhenNoHint() {
        // Timers from the Quick Start widget carry no hint but are named after their activity.
        let timer = repo.create(kind: .timer, payload: ["child": 1, "start": iso, "name": "Feeding"])!
        XCTAssertNil(timer.timerActivityRaw)
        XCTAssertEqual(TimerActivity(timer: timer), .feeding)
    }

    func testUncategorizedTimerResolvesToNil() {
        let timer = repo.create(kind: .timer, payload: ["child": 1, "start": iso])!
        XCTAssertNil(timer.timerActivityRaw)
        XCTAssertNil(TimerActivity(timer: timer))
    }

    func testHintSurvivesServerUpsert() throws {
        // The hint is local-only; a re-pull of the (generic) server timer must not wipe it.
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": 7, "child": 1, "name": "Sleep", "start": iso])
        let timer = LocalEntity(kind: .timer, serverID: 7, childID: 1, timestamp: .now,
                                payload: payload, syncState: .synced, timerActivityRaw: "tummyTime")
        context.insert(timer)

        LocalStore.upsertFromServer(payload, kind: .timer, in: context)   // server has no hint field
        XCTAssertEqual(timer.timerActivityRaw, "tummyTime")
        XCTAssertEqual(TimerActivity(timer: timer), .tummyTime)           // hint still wins over name
    }
}
