import XCTest
@testable import BabyBuddy

@MainActor
final class DeepLinkRouterTests: XCTestCase {
    /// The Active Timer widget builds `babybuddy://convert/<localID>/<kindRaw>` for feeding/
    /// pumping Stop; the router must parse it back into a convert target.
    func testConvertLinkParsesTimerAndKind() {
        let router = DeepLinkRouter()
        let id = UUID()
        XCTAssertTrue(router.handle(URL(string: "babybuddy://convert/\(id.uuidString)/feeding")!))
        XCTAssertEqual(router.convertTarget, .init(localID: id, kind: .feeding))
    }

    func testTimerLinkParsesLocalID() {
        let router = DeepLinkRouter()
        let id = UUID()
        XCTAssertTrue(router.handle(URL(string: "babybuddy://timer/\(id.uuidString)")!))
        XCTAssertEqual(router.openTimerLocalID, id)
    }

    func testConvertLinkWithUnknownKindIsIgnored() {
        let router = DeepLinkRouter()
        XCTAssertTrue(router.handle(URL(string: "babybuddy://convert/\(UUID().uuidString)/notakind")!))
        XCTAssertNil(router.convertTarget)
    }

    /// The status widget builds `babybuddy://day/<kindRaw>` for a tile tap; the router must parse
    /// it into the day kind.
    func testDayLinkParsesKind() {
        let router = DeepLinkRouter()
        XCTAssertTrue(router.handle(URL(string: "babybuddy://day/change")!))
        XCTAssertEqual(router.openDayKind, .change)
    }

    func testDayLinkWithUnknownKindIsIgnored() {
        let router = DeepLinkRouter()
        XCTAssertTrue(router.handle(URL(string: "babybuddy://day/notakind")!))
        XCTAssertNil(router.openDayKind)
    }

    func testForeignSchemeIsRejected() {
        let router = DeepLinkRouter()
        XCTAssertFalse(router.handle(URL(string: "https://example.com")!))
    }
}
