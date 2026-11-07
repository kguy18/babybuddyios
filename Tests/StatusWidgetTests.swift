import XCTest
import SwiftData
@testable import BabyBuddy

/// Exercises the pure ``ChildStatus.compute`` behind the status widget — last-event-of-kind,
/// today counts, child scoping, and the no-child fallback.
@MainActor
final class StatusWidgetTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: LocalRepository!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
        repo = LocalRepository(context: context)
    }

    private func entities() throws -> [LocalEntity] {
        try context.fetch(FetchDescriptor<LocalEntity>())
    }

    private func iso(_ date: Date) -> String { APIDate.isoDateTime.string(from: date) }

    /// Insert a child record so `childName` resolves.
    private func seedChild(id: Int, first: String) {
        let e = repo.create(kind: .child, payload: ["first_name": first])!
        e.serverID = id
        // A child record's own FK isn't itself; clear it so it isn't counted as an event.
        e.childID = nil
    }

    func testNoSelectedChildIsUnavailable() throws {
        let status = ChildStatus.compute(from: try entities(), childID: nil)
        XCTAssertFalse(status.hasChild)
        XCTAssertNil(status.childName)
        XCTAssertNil(status.feeding.last)
        XCTAssertEqual(status.feeding.todayCount, 0)
    }

    func testLastEventAndTodayCount() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000) // fixed "now"
        let earlierToday = now.addingTimeInterval(-2 * 3600)
        let alsoToday = now.addingTimeInterval(-30 * 60)
        let yesterday = now.addingTimeInterval(-26 * 3600)

        seedChild(id: 1, first: "Ada")
        _ = repo.create(kind: .feeding, payload: ["child": 1, "start": iso(yesterday), "end": iso(yesterday)])
        _ = repo.create(kind: .feeding, payload: ["child": 1, "start": iso(earlierToday), "end": iso(earlierToday)])
        _ = repo.create(kind: .feeding, payload: ["child": 1, "start": iso(alsoToday), "end": iso(alsoToday)])

        let status = ChildStatus.compute(from: try entities(), childID: 1, now: now)
        XCTAssertTrue(status.hasChild)
        XCTAssertEqual(status.childName, "Ada")
        // Most recent feeding wins.
        XCTAssertEqual(status.feeding.last.map { Int($0.timeIntervalSince1970) },
                       Int(alsoToday.timeIntervalSince1970))
        // Two of the three feedings are "today".
        XCTAssertEqual(status.feeding.todayCount, 2)
        // Kinds with no events read empty.
        XCTAssertNil(status.sleep.last)
        XCTAssertEqual(status.change.todayCount, 0)
    }

    func testScopedToSelectedChild() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        seedChild(id: 1, first: "Ada")
        seedChild(id: 2, first: "Bo")
        _ = repo.create(kind: .change, payload: ["child": 1, "time": iso(now), "wet": true])
        _ = repo.create(kind: .change, payload: ["child": 2, "time": iso(now), "wet": true])
        _ = repo.create(kind: .change, payload: ["child": 2, "time": iso(now), "solid": true])

        let child1 = ChildStatus.compute(from: try entities(), childID: 1, now: now)
        let child2 = ChildStatus.compute(from: try entities(), childID: 2, now: now)
        XCTAssertEqual(child1.change.todayCount, 1)
        XCTAssertEqual(child2.change.todayCount, 2)
        XCTAssertEqual(child2.childName, "Bo")
    }

    func testRunningTimerSurfaced() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        seedChild(id: 1, first: "Patrick")
        XCTAssertNil(ChildStatus.compute(from: try entities(), childID: 1, now: now).runningTimer)

        let started = now.addingTimeInterval(-22 * 60)
        _ = repo.create(kind: .timer, payload: ["child": 1, "name": "Sleep", "start": iso(started)])
        let running = ChildStatus.compute(from: try entities(), childID: 1, now: now).runningTimer
        XCTAssertEqual(running?.name, "Sleep")
        XCTAssertEqual(running.map { Int($0.start.timeIntervalSince1970) },
                       Int(started.timeIntervalSince1970))
    }

    func testCompactAgeFormatting() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        func age(_ seconds: TimeInterval) -> String {
            ChildStatus.compactAge(from: now.addingTimeInterval(-seconds), to: now)
        }
        XCTAssertEqual(age(30), "now")
        XCTAssertEqual(age(20 * 60), "20m")
        XCTAssertEqual(age(2 * 3600), "2h")
        XCTAssertEqual(age(2 * 3600 + 15 * 60), "2h 15m")
        XCTAssertEqual(age(44 * 3600), "1d 20h")
        XCTAssertEqual(age(48 * 3600), "2d")
    }

    func testPendingDeleteExcluded() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        seedChild(id: 1, first: "Ada")
        let a = repo.create(kind: .sleep, payload: ["child": 1, "start": iso(now), "end": iso(now)])!
        repo.delete(a) // marks pendingDelete (or removes if never synced)

        let status = ChildStatus.compute(from: try entities(), childID: 1, now: now)
        XCTAssertNil(status.sleep.last)
        XCTAssertEqual(status.sleep.todayCount, 0)
    }
}

@MainActor
final class CompletedActivityStatusTests: XCTestCase {
    private func entity(_ kind: EntityKind, child: Int = 1, start: Date, end: Date? = nil) -> LocalEntity {
        var payload: [String: Any] = ["child": child, kind.timeField: APIDate.isoDateTime.string(from: start)]
        if let end { payload["end"] = APIDate.isoDateTime.string(from: end) }
        return LocalEntity(kind: kind, serverID: nil, childID: child, timestamp: start,
                           payload: try! JSONSerialization.data(withJSONObject: payload), syncState: .synced)
    }

    func testSleepUsesWakeTimeAndFeedingUsesFinishTime() {
        let now = Date(), start = now.addingTimeInterval(-5400), end = now.addingTimeInterval(-1800)
        let sleep = entity(.sleep, start: start, end: end), feed = entity(.feeding, start: start, end: end)
        let payload = sleep.payload
        let result = ChildStatus.compute(from: [sleep, feed], childID: 1, now: now)
        XCTAssertEqual(result.sleep.last!.timeIntervalSince1970, end.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(result.feeding.last!.timeIntervalSince1970, end.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(result.sleep.timing?.basis, .woke)
        XCTAssertEqual(result.feeding.timing?.basis, .feedEnded)
        XCTAssertEqual(sleep.timestamp, start)
        XCTAssertEqual(sleep.payload, payload)
    }

    func testLatestEndWinsEvenIfAnotherSessionStartedLater() {
        let now = Date()
        let long = entity(.sleep, start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-600))
        let short = entity(.sleep, start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800))
        XCTAssertEqual(ChildStatus.compute(from: [long, short], childID: 1, now: now).sleep.last!,
                       long.startEndDates.end!)
    }

    func testOvernightSessionKeepsItsOriginalDayCountAndChildScope() {
        let today = Calendar.current.startOfDay(for: Date()).addingTimeInterval(1800)
        let start = today.addingTimeInterval(-7200), end = today.addingTimeInterval(-600)
        let mine = entity(.sleep, start: start, end: end)
        let other = entity(.sleep, child: 2, start: today.addingTimeInterval(-120), end: today)
        let result = ChildStatus.compute(from: [mine, other], childID: 1, now: today)
        XCTAssertEqual(result.sleep.last!, mine.startEndDates.end!)
        XCTAssertEqual(result.sleep.todayCount, 0)
    }

    func testRunningSleepReplacesAwakeStatusAndStoppedDraftRemainsExplicit() {
        // Midday, so the sleep two hours earlier starts today whenever this runs.
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let earlier = now.addingTimeInterval(-7200)
        let sleep = entity(.sleep, start: earlier, end: earlier.addingTimeInterval(1800))
        let timer = entity(.timer, start: now.addingTimeInterval(-1200))
        timer.timerActivityRaw = EntityKind.sleep.rawValue
        var result = ChildStatus.compute(from: [sleep, timer], childID: 1, now: now)
        XCTAssertEqual(result.sleep.timing?.basis, .sleeping)
        XCTAssertEqual(result.sleep.last!, timer.timestamp)
        timer.stoppedAt = now.addingTimeInterval(-30)
        timer.syncState = .pendingDelete
        result = ChildStatus.compute(from: [sleep, timer], childID: 1, now: now)
        XCTAssertEqual(result.sleep.timing?.basis, .sleepStopped)
        XCTAssertEqual(result.sleep.last!, timer.stoppedAt!)
        XCTAssertEqual(result.sleep.todayCount, 1)
    }

    func testInvalidEndAndDeletedRecordsDoNotClaimTheChildWoke() {
        let now = Date(), start = now.addingTimeInterval(-600)
        let invalid = entity(.sleep, start: start, end: start.addingTimeInterval(-30))
        let deleted = entity(.sleep, start: start, end: now)
        deleted.syncState = .pendingDelete
        let result = ChildStatus.compute(from: [invalid, deleted], childID: 1, now: now)
        XCTAssertEqual(result.sleep.timing?.basis, .sleepStarted)
        XCTAssertEqual(result.sleep.last!, invalid.timestamp)
    }
}
