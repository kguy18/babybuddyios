import XCTest
@testable import BabyBuddy

@MainActor
final class ServerURLNormalizationTests: XCTestCase {
    private func norm(_ s: String) -> String { AppSession.normalizedServerURLString(s) }

    func testUpgradesHTTPToHTTPS() {
        // Baby Buddy's add-device QR emits http:// behind a TLS proxy; iOS ATS blocks cleartext.
        XCTAssertEqual(norm("http://demo.baby-buddy.net/"), "https://demo.baby-buddy.net/")
    }

    func testPreservesHTTPS() {
        XCTAssertEqual(norm("https://baby.example.com"), "https://baby.example.com")
    }

    func testAddsSchemeToBareHost() {
        XCTAssertEqual(norm("baby.example.com"), "https://baby.example.com")
    }

    func testUpgradeIsCaseInsensitiveAndKeepsPathPortQuery() {
        XCTAssertEqual(norm("HTTP://Baby.Example.com:8000/sub/"), "https://Baby.Example.com:8000/sub/")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(norm("  http://baby.example.com \n"), "https://baby.example.com")
    }
}
