import XCTest
@testable import BabyBuddy

final class PinnedDateTests: XCTestCase {
    func testPinnedDayKeepsTheTimeOfDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        let real = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9, minute: 41))!
        let pinned = PinnedDate.now(pinned: "2026-03-17", real: real, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: pinned)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 3, 17, 9, 41])
    }

    func testNoPinOrABadOneLeavesTheRealDate() {
        let real = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(PinnedDate.now(pinned: nil, real: real), real)
        XCTAssertEqual(PinnedDate.now(pinned: "soon", real: real), real)
    }
}
