import XCTest
@testable import BabyBuddy

final class ChartValueDetailsTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testDailySelectionIncludesZeroAndUsesCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let zero = TrendValue(date: date("2026-10-24T22:00:00Z"), text: "0")
        let next = TrendValue(date: date("2026-10-25T23:00:00Z"), text: "1")
        XCTAssertEqual(TrendValue.selected(at: date("2026-10-25T22:59:00Z"),
                                          in: [zero, next], daily: true, calendar: calendar), zero)
        XCTAssertEqual(TrendValue.selected(at: date("2026-10-25T23:01:00Z"),
                                          in: [zero, next], daily: true, calendar: calendar), next)
        XCTAssertNil(TrendValue.selected(at: date("2026-10-24T12:00:00Z"),
                                        in: [zero, next], daily: true, calendar: calendar))
    }

    func testReadingSelectionUsesNearestIncludingPaddedSingleReading() {
        let first = TrendValue(date: date("2026-06-15T08:00:00Z"), text: "36.72")
        let last = TrendValue(date: date("2026-06-15T10:00:00Z"), text: "37.15")
        XCTAssertEqual(TrendValue.selected(at: date("2026-06-15T09:30:00Z"),
                                          in: [last, first], daily: false), last)
        XCTAssertEqual(TrendValue.selected(at: first.date, in: [first], daily: false), first)
        XCTAssertEqual(TrendValue.selected(at: first.date.addingTimeInterval(-1), in: [first], daily: false), first)
        XCTAssertEqual(TrendValue.selected(at: last.date.addingTimeInterval(1), in: [first, last], daily: false), last)
        XCTAssertNil(TrendValue.selected(at: first.date, in: [], daily: true))
    }

    func testFractionalAmountsAreNotTruncated() {
        XCTAssertEqual(TrendValue.amount(12.75), 12.75.formatted(.number.precision(.fractionLength(0...6))))
        XCTAssertNotEqual(TrendValue.amount(12.75), TrendValue.amount(12))
    }

    func testReadingsAtSameTimeHaveSeparateIdentities() {
        let time = date("2026-06-15T08:00:00Z")
        let first = TrendValue(date: time, text: "37", recordID: UUID())
        let second = TrendValue(date: time, text: "37", recordID: UUID())
        XCTAssertNotEqual(first.id, second.id)
    }
}
