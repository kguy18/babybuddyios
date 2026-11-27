import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class DailyRhythmTests: XCTestCase {
    private var container: ModelContainer!
    private var records: [LocalEntity] = []
    private var calendar: Calendar!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        records = []
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func sleep(_ start: String, _ end: String, child: Int = 1) {
        records.append(LocalRepository(context: container.mainContext).create(
            kind: .sleep, payload: ["child": child, "start": start, "end": end])!)
    }
    private func days(_ now: String, period: ChartPeriod = .week) -> [RhythmDay] {
        DailyRhythmAggregator(calendar: calendar).days(records, childID: 1, period: period, now: date(now))
    }

    func testMidnightSleepSplitsAndPreservesDuration() throws {
        sleep("2026-06-14T23:30:00+02:00", "2026-06-15T01:15:00+02:00")
        let rows = days("2026-06-15T12:00:00+02:00")
        let segments = rows.flatMap(\.sleeps)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].startHour, 23.5, accuracy: 0.00001)
        XCTAssertEqual(segments[0].endHour, 24, accuracy: 0.00001)
        XCTAssertEqual(segments[1].startHour, 0, accuracy: 0.00001)
        XCTAssertEqual(segments[1].endHour, 1.25, accuracy: 0.00001)
        XCTAssertEqual(segments.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }, 105 * 60)
        XCTAssertEqual(rows.count, 7)
    }

    func testMidnightEndDoesNotCreateNextDaySegment() {
        sleep("2026-06-14T23:00:00+02:00", "2026-06-15T00:00:00+02:00")
        let rows = days("2026-06-15T12:00:00+02:00")
        XCTAssertEqual(rows.flatMap(\.sleeps).count, 1)
        XCTAssertTrue(rows.last!.sleeps.isEmpty)
    }

    func testClipsToWindowAndNow() {
        sleep("2026-06-08T23:00:00+02:00", "2026-06-09T01:00:00+02:00")
        sleep("2026-06-15T11:00:00+02:00", "2026-06-15T14:00:00+02:00")
        let rows = days("2026-06-15T12:00:00+02:00")
        XCTAssertEqual(rows.first!.sleeps.first!.startHour, 0, accuracy: 0.00001)
        XCTAssertEqual(rows.first!.sleeps.first!.endHour, 1, accuracy: 0.00001)
        XCTAssertEqual(rows.last!.sleeps.first!.endHour, 12, accuracy: 0.00001)
    }

    func testSpringClockChangeLeavesSkippedHourEmpty() {
        sleep("2026-03-29T01:30:00+01:00", "2026-03-29T03:30:00+02:00")
        let segments = days("2026-03-29T12:00:00+02:00").flatMap(\.sleeps)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].endHour, 2, accuracy: 0.00001)
        XCTAssertEqual(segments[1].startHour, 3, accuracy: 0.00001)
        XCTAssertEqual(segments.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }, 3600)
    }

    func testAutumnRepeatedHourKeepsPositiveSegments() {
        sleep("2026-10-25T02:30:00+02:00", "2026-10-25T02:15:00+01:00")
        let segments = days("2026-10-25T12:00:00+01:00").flatMap(\.sleeps)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].endHour, 3, accuracy: 0.00001)
        XCTAssertEqual(segments[1].startHour, 2, accuracy: 0.00001)
        XCTAssertTrue(segments.allSatisfy { $0.endHour > $0.startHour })
        XCTAssertEqual(segments.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }, 45 * 60)
        XCTAssertEqual(Set(segments.map(\.id)).count, 2)
    }

    func testExcludesDeletedOtherChildAndMalformedSleep() {
        sleep("2026-06-15T08:00:00+02:00", "2026-06-15T09:00:00+02:00", child: 2)
        sleep("2026-06-15T08:00:00+02:00", "2026-06-15T09:00:00+02:00")
        records.last!.syncState = .pendingDelete
        sleep("2026-06-15T09:00:00+02:00", "2026-06-15T08:00:00+02:00")
        sleep("invalid", "2026-06-15T08:00:00+02:00")
        XCTAssertTrue(days("2026-06-15T12:00:00+02:00").flatMap(\.sleeps).isEmpty)
    }

    func testFeedingUsesStartAndMethodAndExcludesFuture() {
        let repo = LocalRepository(context: container.mainContext)
        for (start, child) in [("2026-06-15T08:15:00+02:00", 1),
                               ("2026-06-15T13:00:00+02:00", 1),
                               ("2026-06-15T08:00:00+02:00", 2)] {
            records.append(repo.create(kind: .feeding, payload: ["child": child, "start": start,
                           "end": "2026-06-15T09:00:00+02:00", "method": "bottle"])!)
        }
        let feedings = days("2026-06-15T12:00:00+02:00").flatMap(\.feedings)
        XCTAssertEqual(feedings.count, 1)
        XCTAssertEqual(feedings[0].hour, 8.25)
        XCTAssertEqual(feedings[0].method, .bottle)
    }

    func testEmptyDaysAndAllPeriodsRemainVisible() {
        for period in ChartPeriod.allCases {
            let rows = days("2026-06-15T12:00:00+02:00", period: period)
            XCTAssertEqual(rows.count, period.days)
            XCTAssertEqual(Set(rows.map(\.axisID)).count, period.days)
            XCTAssertTrue(rows.allSatisfy { $0.sleeps.isEmpty && $0.feedings.isEmpty })
        }
    }
}
