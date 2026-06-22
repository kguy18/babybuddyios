import XCTest
@testable import BabyBuddy

final class DeviceLoginQRTests: XCTestCase {
    func testParsesValidPayload() {
        let raw = #"BABYBUDDY-LOGIN:{"url":"https://baby.example.com/","api_key":"abc123","session_cookies":{}}"#
        let creds = DeviceLoginQR.parse(raw)
        XCTAssertEqual(creds?.serverURL, "https://baby.example.com/")
        XCTAssertEqual(creds?.token, "abc123")
    }

    func testIgnoresSessionCookiesContent() {
        let raw = #"BABYBUDDY-LOGIN:{"url":"https://b.net","api_key":"tok","session_cookies":{"ingress_session":"xyz"}}"#
        XCTAssertEqual(DeviceLoginQR.parse(raw)?.token, "tok")
    }

    func testTrimsSurroundingWhitespace() {
        let raw = "  BABYBUDDY-LOGIN:{\"url\":\"https://b.net\",\"api_key\":\"tok\"}\n"
        XCTAssertEqual(DeviceLoginQR.parse(raw)?.serverURL, "https://b.net")
    }

    func testRejectsMissingPrefix() {
        let raw = #"{"url":"https://b.net","api_key":"tok"}"#
        XCTAssertNil(DeviceLoginQR.parse(raw))
    }

    func testRejectsUnrelatedQR() {
        XCTAssertNil(DeviceLoginQR.parse("https://example.com"))
    }

    func testRejectsMalformedJSON() {
        XCTAssertNil(DeviceLoginQR.parse("BABYBUDDY-LOGIN:{not json}"))
    }

    func testRejectsEmptyToken() {
        let raw = #"BABYBUDDY-LOGIN:{"url":"https://b.net","api_key":""}"#
        XCTAssertNil(DeviceLoginQR.parse(raw))
    }

    func testRejectsMissingURL() {
        let raw = #"BABYBUDDY-LOGIN:{"api_key":"tok"}"#
        XCTAssertNil(DeviceLoginQR.parse(raw))
    }
}
