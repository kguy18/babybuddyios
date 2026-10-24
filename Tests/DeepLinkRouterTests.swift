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

    /// A running Quick start tile runs `OpenTimerIntent`, which leaves the timer in shared
    /// defaults; the app takes it once, on the intent's callback or its next activation.
    func testOpenTimerIntentRoutesPendingTimerOnce() async throws {
        let id = UUID()
        let router = DeepLinkRouter()
        OpenTimerIntent.didRequestOpen = { router.openPendingTimer() }
        defer { OpenTimerIntent.didRequestOpen = nil; SharedDefaults.pendingOpenTimerID = nil }

        _ = try await OpenTimerIntent(timerLocalID: id).perform()
        XCTAssertEqual(router.openTimerLocalID, id)
        XCTAssertNil(SharedDefaults.pendingOpenTimerID)

        router.openTimerLocalID = nil
        router.openPendingTimer() // the next activation finds nothing left to open
        XCTAssertNil(router.openTimerLocalID)

        OpenTimerIntent.didRequestOpen = nil // run in the widget's process: picked up on activation
        _ = try await OpenTimerIntent(timerLocalID: id).perform()
        XCTAssertNil(router.openTimerLocalID)
        router.openPendingTimer()
        XCTAssertEqual(router.openTimerLocalID, id)
    }

    /// Stop on a widget for an untyped timer; a body tap (`timer/`) must not stop it.
    func testStopLinkParsesLocalID() {
        let router = DeepLinkRouter()
        let id = UUID()
        XCTAssertTrue(router.handle(URL(string: "babybuddy://stop/\(id.uuidString)")!))
        XCTAssertEqual(router.stopTimerLocalID, id)
        XCTAssertNil(router.openTimerLocalID)
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

    /// A tapped medication reminder links `babybuddy://dose/<localID>` to log the next dose.
    func testDoseLinkParsesLocalID() {
        let router = DeepLinkRouter()
        let id = UUID()
        XCTAssertTrue(router.handle(URL(string: "babybuddy://dose/\(id.uuidString)")!))
        XCTAssertEqual(router.repeatDoseLocalID, id)
    }

    func testForeignSchemeIsRejected() {
        let router = DeepLinkRouter()
        XCTAssertFalse(router.handle(URL(string: "https://example.com")!))
    }
}
