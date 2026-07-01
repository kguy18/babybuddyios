import XCTest
import SwiftUI
@testable import BabyBuddy

/// Covers `RemoteImage.resolve` — how a serialized media URL is turned into a fetchable URL plus
/// the token to send: same-host `http`→`https` upgrade, same-origin-only token, `file://`
/// passthrough, and server-relative resolution.
final class RemoteImageTests: XCTestCase {
    private let config = ServerConfig(baseURL: URL(string: "https://baby.example.com")!, token: "TICKET")

    private func resolve(_ s: String?) -> (url: URL, token: String?)? {
        RemoteImage<EmptyView>.resolve(s, config: config)
    }

    func testNilAndEmptyReturnNil() {
        XCTAssertNil(resolve(nil))
        XCTAssertNil(resolve(""))
        XCTAssertNil(resolve("   "))
    }

    func testSameHostHTTPSCarriesToken() {
        let r = resolve("https://baby.example.com/media/child/picture/a.jpg")
        XCTAssertEqual(r?.url.absoluteString, "https://baby.example.com/media/child/picture/a.jpg")
        XCTAssertEqual(r?.token, "TICKET")
    }

    func testSameHostHTTPUpgradedToHTTPS() {
        // Behind a TLS-terminating proxy the API can serialize media as http; ATS blocks cleartext.
        let r = resolve("http://baby.example.com/media/notes/images/b.png")
        XCTAssertEqual(r?.url.scheme, "https")
        XCTAssertEqual(r?.url.absoluteString, "https://baby.example.com/media/notes/images/b.png")
        XCTAssertEqual(r?.token, "TICKET")
    }

    func testDifferentHostGetsNoToken() {
        // Never leak the token to a host that isn't the configured server.
        let r = resolve("https://cdn.othersite.com/x.jpg")
        XCTAssertEqual(r?.url.absoluteString, "https://cdn.othersite.com/x.jpg")
        XCTAssertNil(r?.token)
    }

    func testRelativePathResolvesAgainstServerWithToken() {
        let r = resolve("/media/child/picture/c.jpg")
        XCTAssertEqual(r?.url.absoluteString, "https://baby.example.com/media/child/picture/c.jpg")
        XCTAssertEqual(r?.token, "TICKET")
    }

    func testFileURLPassesThroughWithoutToken() {
        let r = resolve("file:///var/mobile/Caches/bbdemo_child.png")
        XCTAssertEqual(r?.url.scheme, "file")
        XCTAssertNil(r?.token)
    }
}
