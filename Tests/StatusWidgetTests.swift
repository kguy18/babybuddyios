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
