import XCTest
import SwiftData
@testable import BabyBuddy

/// Pure-logic coverage for the running-timer Live Activity: the Stop-route selection shared with
/// the Active Timer widget, and building the activity attributes/content from a timer entity.
/// The Live Activity presentation itself and `Activity.request`/reconcile need a signed device.
@MainActor
final class LiveActivityTests: XCTestCase {
    private let iso = "2024-01-15T10:00:00-05:00"
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        // Hold the container for the test's lifetime — its `mainContext` dangles if it deallocates.
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    // MARK: Stop route (mirrors the ActiveTimerWidget Stop button)

    func testStopRouteLogsInstantLoggableActivities() {
        XCTAssertEqual(TimerStopRoute.resolve(localID: "A", activity: .sleep), .log(localID: "A"))
        XCTAssertEqual(TimerStopRoute.resolve(localID: "A", activity: .tummyTime), .log(localID: "A"))
    }

    func testStopRouteOpensFormForFieldActivities() {
        XCTAssertEqual(TimerStopRoute.resolve(localID: "A", activity: .feeding),
                       .convertForm(localID: "A", kind: .feeding))
        XCTAssertEqual(TimerStopRoute.resolve(localID: "A", activity: .pumping),
                       .convertForm(localID: "A", kind: .pumping))
    }

    func testStopRouteOpensActionsForUncategorizedTimer() {
        XCTAssertEqual(TimerStopRoute.resolve(localID: "A", activity: nil), .openActions(localID: "A"))
    }

    func testStopRouteDeepLinks() {
        XCTAssertNil(TimerStopRoute.log(localID: "A").deepLink) // in-process intent, no app launch
        XCTAssertEqual(TimerStopRoute.convertForm(localID: "A", kind: .feeding).deepLink,
                       URL(string: "babybuddy://convert/A/feeding"))
        XCTAssertEqual(TimerStopRoute.openActions(localID: "A").deepLink,
                       URL(string: "babybuddy://timer/A"))
    }

    // MARK: Attribute construction

    func testAttributesFromHintedTimerCarryActivityNameAndStart() {
        // A sleep timer the user named "Afternoon nap" — the hint must win over the custom name.
        let timer = LocalRepository(context: context).create(
            kind: .timer, payload: ["child": 1, "start": iso, "name": "Afternoon nap"],
            timerActivity: .sleep)!
        let built = RunningTimerAttributes.from(timer: timer)
        XCTAssertEqual(built?.attributes.timerLocalID, timer.localID.uuidString)
        XCTAssertEqual(built?.state.timerName, "Afternoon nap")
        XCTAssertEqual(built?.state.activityRaw, "sleep")
        XCTAssertEqual(built?.state.activity, .sleep)
        XCTAssertEqual(built?.state.start, timer.timestamp)
    }

    func testAttributesFallBackToNameWhenNoHint() {
        // Quick Start / widget timers carry no hint but are named after their activity.
        let timer = LocalRepository(context: context).create(
            kind: .timer, payload: ["child": 1, "start": iso, "name": "Feeding"])!
        XCTAssertEqual(RunningTimerAttributes.from(timer: timer)?.state.activity, .feeding)
    }

    func testAttributesFromUncategorizedTimerHaveNoActivity() {
        let timer = LocalRepository(context: context).create(
            kind: .timer, payload: ["child": 1, "start": iso])!
        let built = RunningTimerAttributes.from(timer: timer)
        XCTAssertNil(built?.state.activityRaw)
        XCTAssertNil(built?.state.activity)
        XCTAssertEqual(built?.state.timerName, "Timer") // default when the payload has no name
    }

    func testFromReturnsNilForNonTimerEntity() {
        let feeding = LocalRepository(context: context).create(kind: .feeding, payload: ["child": 1])!
        XCTAssertNil(RunningTimerAttributes.from(timer: feeding))
    }

    // MARK: Header title (child-name prefix)

    func testTitlePrefixesChildNameWhenPresent() {
        let timer = LocalRepository(context: context).create(
            kind: .timer, payload: ["child": 1, "start": iso, "name": "Sleep"], timerActivity: .sleep)!
        let built = RunningTimerAttributes.from(timer: timer, childName: "Patrick")
        XCTAssertEqual(built?.state.childName, "Patrick")
        XCTAssertEqual(built?.state.title, "Patrick · Sleep")
    }

    func testTitleFallsBackToTimerNameWithoutChild() {
        let timer = LocalRepository(context: context).create(
            kind: .timer, payload: ["child": 1, "start": iso, "name": "Feeding"])!
        let built = RunningTimerAttributes.from(timer: timer) // no child name resolved
        XCTAssertNil(built?.state.childName)
        XCTAssertEqual(built?.state.title, "Feeding")
    }
}
