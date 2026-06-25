import XCTest
@testable import BabyBuddy

/// Covers the pure timeline search + date-range matching used to filter the local cache.
final class TimelineFilteringTests: XCTestCase {

    private func entity(_ kind: EntityKind, _ payload: [String: Any], childID: Int = 1) -> LocalEntity {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return LocalEntity(kind: kind, serverID: payload["id"] as? Int, childID: childID,
                           timestamp: .now, payload: data, syncState: .synced)
    }

    // A UTC calendar so day-boundary assertions don't depend on the test machine's timezone.
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ hh: Int = 12) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: hh))!
    }

    // MARK: Search

    func testBlankQueryMatchesEverything() {
        let note = entity(.note, ["id": 1, "note": "anything"])
        XCTAssertTrue(TimelineFiltering.matchesSearch(note, query: "", childName: nil))
        XCTAssertTrue(TimelineFiltering.matchesSearch(note, query: "   ", childName: nil))
    }

    func testMatchesNoteTextCaseInsensitively() {
        let note = entity(.note, ["id": 1, "note": "First real smile!"])
        XCTAssertTrue(TimelineFiltering.matchesSearch(note, query: "smile", childName: nil))
        XCTAssertTrue(TimelineFiltering.matchesSearch(note, query: "FIRST", childName: nil))
        XCTAssertFalse(TimelineFiltering.matchesSearch(note, query: "frown", childName: nil))
    }

    func testMatchesTags() {
        let note = entity(.note, ["id": 1, "note": "x", "tags": ["milestone", "night"]])
        XCTAssertTrue(TimelineFiltering.matchesSearch(note, query: "milestone", childName: nil))
        XCTAssertTrue(TimelineFiltering.matchesSearch(note, query: "night", childName: nil))
    }

    func testMatchesFeedingTypeAndMethod() {
        let feeding = entity(.feeding, ["id": 2, "type": "formula", "method": "bottle",
                                        "start": "2024-01-15T10:00:00-05:00"])
        XCTAssertTrue(TimelineFiltering.matchesSearch(feeding, query: "formula", childName: nil))
        XCTAssertTrue(TimelineFiltering.matchesSearch(feeding, query: "bottle", childName: nil))
        // Multi-token AND: both words present (though not adjacent in the rendered subtitle).
        XCTAssertTrue(TimelineFiltering.matchesSearch(feeding, query: "formula bottle", childName: nil))
        XCTAssertFalse(TimelineFiltering.matchesSearch(feeding, query: "formula sleep", childName: nil))
    }

    func testMatchesActivityNotesField() {
        // Activities (not just Note records) can carry a free-text `notes` field.
        let feeding = entity(.feeding, ["id": 3, "type": "breast milk", "method": "left breast",
                                        "notes": "spit up a little", "start": "2024-01-15T10:00:00-05:00"])
        XCTAssertTrue(TimelineFiltering.matchesSearch(feeding, query: "spit", childName: nil))
    }

    func testMatchesChildName() {
        let change = entity(.change, ["id": 4, "wet": true, "time": "2024-01-15T10:00:00-05:00"])
        XCTAssertTrue(TimelineFiltering.matchesSearch(change, query: "maya", childName: "Maya Guy"))
        XCTAssertFalse(TimelineFiltering.matchesSearch(change, query: "maya", childName: nil))
    }

    // MARK: Date range

    func testNilBoundsMatchEverything() {
        XCTAssertTrue(TimelineFiltering.inDateRange(date(2024, 1, 15), from: nil, to: nil, calendar: utc))
    }

    func testFromBoundIsInclusiveFromStartOfDay() {
        let from = date(2024, 1, 10)
        XCTAssertFalse(TimelineFiltering.inDateRange(date(2024, 1, 9, 23), from: from, to: nil, calendar: utc))
        XCTAssertTrue(TimelineFiltering.inDateRange(date(2024, 1, 10, 0), from: from, to: nil, calendar: utc))
        XCTAssertTrue(TimelineFiltering.inDateRange(date(2024, 1, 11), from: from, to: nil, calendar: utc))
    }

    func testToBoundIncludesWholeDay() {
        let to = date(2024, 1, 20)
        XCTAssertTrue(TimelineFiltering.inDateRange(date(2024, 1, 20, 23), from: nil, to: to, calendar: utc))
        XCTAssertFalse(TimelineFiltering.inDateRange(date(2024, 1, 21, 0), from: nil, to: to, calendar: utc))
    }

    func testCombinedRangeIncludingSingleDay() {
        let day = date(2024, 3, 5)
        XCTAssertTrue(TimelineFiltering.inDateRange(date(2024, 3, 5, 8), from: day, to: day, calendar: utc))
        XCTAssertFalse(TimelineFiltering.inDateRange(date(2024, 3, 4, 23), from: day, to: day, calendar: utc))
        XCTAssertFalse(TimelineFiltering.inDateRange(date(2024, 3, 6, 1), from: day, to: day, calendar: utc))
    }
}
