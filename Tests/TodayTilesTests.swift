import XCTest
@testable import BabyBuddy

/// The stored Today tiles list (#188): never set is the default four, empty is none.
final class TodayTilesTests: XCTestCase {
    func testNeverSetIsTheDefaultFour() {
        XCTAssertEqual(TodayTiles.decode(nil), [.feeding, .sleep, .change, .tummyTime])
    }

    func testEmptyMeansNoTiles() {
        XCTAssertEqual(TodayTiles.decode(""), [])
    }

    func testKeepsOrderAndDropsUnknownRepeatedAndIneligibleKinds() {
        XCTAssertEqual(TodayTiles.decode("pumping,bogus,feeding,weight,pumping,note"), [.pumping, .feeding, .note])
    }

    func testRoundTrips() {
        let kinds: [EntityKind] = [.temperature, .medication, .sleep]
        XCTAssertEqual(TodayTiles.decode(TodayTiles.encode(kinds)), kinds)
        XCTAssertEqual(TodayTiles.decode(TodayTiles.encode([])), [])
    }
}
