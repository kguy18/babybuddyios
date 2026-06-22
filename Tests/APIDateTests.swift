import XCTest
@testable import BabyBuddy

final class APIDateTests: XCTestCase {
    func testParsesDateTimeWithOffset() {
        XCTAssertNotNil(APIDate.parse("2024-01-15T10:30:00-05:00"))
    }

    func testParsesDateTimeWithFractionalSeconds() {
        XCTAssertNotNil(APIDate.parse("2024-01-15T10:30:00.123456-05:00"))
    }

    func testParsesDateOnly() {
        XCTAssertNotNil(APIDate.parse("2024-01-15"))
    }

    func testRejectsGarbage() {
        XCTAssertNil(APIDate.parse("not-a-date"))
    }

    func testFeedingDecodesFromServerJSON() throws {
        let json = """
        {"id": 5, "child": 1, "start": "2024-01-15T10:00:00-05:00",
         "end": "2024-01-15T10:20:00-05:00", "duration": "00:20:00",
         "type": "breast milk", "method": "left breast", "amount": null,
         "notes": "", "tags": []}
        """.data(using: .utf8)!
        let feeding = try APICoders.decoder.decode(FeedingDTO.self, from: json)
        XCTAssertEqual(feeding.id, 5)
        XCTAssertEqual(feeding.type, .breastMilk)
        XCTAssertEqual(feeding.method, .leftBreast)
    }
}
