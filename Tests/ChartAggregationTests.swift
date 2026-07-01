import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class ChartAggregationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var nextID = 1

    /// A UTC calendar so day bucketing is deterministic regardless of the test machine's zone.
    private let aggregator = ChartAggregator(calendar: {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }())

    /// Fixed "now": 2026-06-15T12:00Z. A trailing 7-day window is 2026-06-09 … 2026-06-15.
    private let now = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
        nextID = 1
    }

    @discardableResult
    private func add(_ kind: EntityKind, _ payload: [String: Any],
                     child: Int = 1, deleted: Bool = false) -> LocalEntity {
        var p = payload
        p["id"] = nextID; nextID += 1
        p["child"] = child
        let data = try! JSONSerialization.data(withJSONObject: p)
        let entity = LocalStore.upsertFromServer(data, kind: kind, in: context)!
        if deleted { entity.syncState = .pendingDelete }
        return entity
    }

    private func all() -> [LocalEntity] {
        (try? context.fetch(FetchDescriptor<LocalEntity>())) ?? []
    }

    // MARK: days()

    func testDaysCoverPeriodEndingToday() {
        let days = aggregator.days(for: .week, now: now)
        XCTAssertEqual(days.count, 7)
        // Ascending, ending on today's start-of-day (UTC).
        XCTAssertEqual(days, days.sorted())
        XCTAssertEqual(ISO8601DateFormatter().string(from: days.last!), "2026-06-15T00:00:00Z")
        XCTAssertEqual(ISO8601DateFormatter().string(from: days.first!), "2026-06-09T00:00:00Z")

        XCTAssertEqual(aggregator.days(for: .twoWeeks, now: now).count, 14)
        XCTAssertEqual(aggregator.days(for: .month, now: now).count, 30)
    }

    // MARK: Sleep

    func testSleepHoursSummedPerDayFromStartEnd() {
        add(.sleep, ["start": "2026-06-14T01:00:00Z", "end": "2026-06-14T03:00:00Z"]) // 2h
        add(.sleep, ["start": "2026-06-14T10:00:00Z", "end": "2026-06-14T11:30:00Z"]) // 1.5h
        add(.sleep, ["start": "2026-06-10T08:00:00Z", "end": "2026-06-10T12:00:00Z"]) // 4h

        let series = aggregator.sleepHoursByDay(all(), childID: 1, period: .week, now: now)
        XCTAssertEqual(series.count, 7)
        XCTAssertEqual(hours(series, "2026-06-14T00:00:00Z"), 3.5, accuracy: 0.001)
        XCTAssertEqual(hours(series, "2026-06-10T00:00:00Z"), 4.0, accuracy: 0.001)
        XCTAssertEqual(hours(series, "2026-06-12T00:00:00Z"), 0, accuracy: 0.001)
    }

    func testSleepIgnoresOutOfWindowAndMalformed() {
        add(.sleep, ["start": "2026-06-01T01:00:00Z", "end": "2026-06-01T05:00:00Z"]) // before window
        add(.sleep, ["start": "2026-06-13T05:00:00Z", "end": "2026-06-13T04:00:00Z"]) // end < start
        add(.sleep, ["start": "2026-06-13T05:00:00Z"])                                // no end

        let series = aggregator.sleepHoursByDay(all(), childID: 1, period: .week, now: now)
        XCTAssertEqual(series.reduce(0) { $0 + $1.hours }, 0, accuracy: 0.001)
    }

    // MARK: Feedings

    func testFeedingsCountAndAmountPerDay() {
        add(.feeding, ["start": "2026-06-15T08:00:00Z", "end": "2026-06-15T08:15:00Z", "amount": 100])
        add(.feeding, ["start": "2026-06-15T12:00:00Z", "end": "2026-06-15T12:10:00Z", "amount": NSNull()])
        add(.feeding, ["start": "2026-06-13T09:00:00Z", "end": "2026-06-13T09:10:00Z", "amount": 50])

        let series = aggregator.feedingsByDay(all(), childID: 1, period: .week, now: now)
        let today = bucket(series, "2026-06-15T00:00:00Z")
        XCTAssertEqual(today?.count, 2)
        XCTAssertEqual(today?.totalAmount, 100)          // null amount not summed
        let d13 = bucket(series, "2026-06-13T00:00:00Z")
        XCTAssertEqual(d13?.count, 1)
        XCTAssertEqual(d13?.totalAmount, 50)
        XCTAssertEqual(series.reduce(0) { $0 + $1.count }, 3)
    }

    // MARK: Diapers

    func testDiaperWetSolidTalliedIndependently() {
        add(.change, ["time": "2026-06-12T06:00:00Z", "wet": true, "solid": false])
        add(.change, ["time": "2026-06-12T09:00:00Z", "wet": true, "solid": true])   // counts in both
        add(.change, ["time": "2026-06-12T15:00:00Z", "wet": false, "solid": true])

        let series = aggregator.diaperChangesByDay(all(), childID: 1, period: .week, now: now)
        let day = series.first { iso($0.day) == "2026-06-12T00:00:00Z" }
        XCTAssertEqual(day?.wet, 2)
        XCTAssertEqual(day?.solid, 2)
        XCTAssertEqual(day?.total, 4)
    }

    // MARK: Scoping & empty

    func testExcludesOtherChildrenAndDeleted() {
        add(.feeding, ["start": "2026-06-15T08:00:00Z", "end": "2026-06-15T08:15:00Z", "amount": 90], child: 2)
        add(.feeding, ["start": "2026-06-15T09:00:00Z", "end": "2026-06-15T09:15:00Z", "amount": 90], deleted: true)
        add(.change, ["time": "2026-06-15T10:00:00Z", "wet": true, "solid": false], child: 2)

        XCTAssertEqual(aggregator.feedingsByDay(all(), childID: 1, period: .week, now: now)
            .reduce(0) { $0 + $1.count }, 0)
        XCTAssertEqual(aggregator.diaperChangesByDay(all(), childID: 1, period: .week, now: now)
            .reduce(0) { $0 + $1.total }, 0)
    }

    func testEmptyDatasetYieldsAllZeroDays() {
        let series = aggregator.feedingsByDay(all(), childID: 1, period: .month, now: now)
        XCTAssertEqual(series.count, 30)
        XCTAssertTrue(series.allSatisfy { $0.count == 0 && $0.totalAmount == 0 })
    }

    // MARK: Helpers

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func hours(_ series: [DailySleep], _ dayISO: String) -> Double {
        series.first { iso($0.day) == dayISO }?.hours ?? -1
    }
    private func bucket(_ series: [DailyFeeding], _ dayISO: String) -> DailyFeeding? {
        series.first { iso($0.day) == dayISO }
    }
}
