import XCTest
@testable import BabyBuddy

/// Custom headers for a server behind an access gate (#148): which rows are accepted, that every
/// request to the server carries them, that no other host ever gets them, and that a gate's 403
/// isn't read as Baby Buddy rejecting the token.
final class CustomHeaderTests: XCTestCase {
    private let gate = [CustomHeader(name: "CF-Access-Client-Id", value: "id.access"),
                        CustomHeader(name: "CF-Access-Client-Secret", value: "s3cret")]

    private func client(serving bodies: [String], headers: [CustomHeader]? = nil) -> APIClient {
        let session = StubProtocol.install(bodies)
        return APIClient(config: ServerConfig(baseURL: URL(string: "https://baby.example.com")!,
                                              token: "t", headers: headers ?? gate),
                         session: session)
    }

    private func assertCarriesGate(_ request: URLRequest?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(request?.value(forHTTPHeaderField: "CF-Access-Client-Id"), "id.access", file: file, line: line)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "CF-Access-Client-Secret"), "s3cret", file: file, line: line)
    }

    // MARK: - Validation

    func testRowsAreTrimmed() throws {
        let rows = try CustomHeader.validated([CustomHeader(name: " X-Gate ", value: "\topen \n")])
        XCTAssertEqual(rows, [CustomHeader(name: "X-Gate", value: "open")])
    }

    func testNamesTheAppSetsItselfAreRejected() {
        for name in ["Authorization", "authorization", "Host", "Content-Type", "Content-Length", "Accept", "Cookie"] {
            XCTAssertThrowsError(try CustomHeader.validated([CustomHeader(name: name, value: "x")])) {
                XCTAssertEqual($0 as? CustomHeader.Problem, .reserved(name))
            }
        }
    }

    func testAnEmptyNameOrValueIsAnErrorNotSkipped() {
        for row in [CustomHeader(name: "", value: "x"), CustomHeader(name: "X-Gate", value: "  ")] {
            XCTAssertThrowsError(try CustomHeader.validated([row])) {
                XCTAssertEqual($0 as? CustomHeader.Problem, .empty)
            }
        }
    }

    func testNamesOutsideTheTokenSetAreRejected() {
        for name in ["X Gate", "X-Gäte", "X:Gate"] {
            XCTAssertThrowsError(try CustomHeader.validated([CustomHeader(name: name, value: "x")])) {
                XCTAssertEqual($0 as? CustomHeader.Problem, .invalidName(name))
            }
        }
    }

    func testAValueWithALineBreakIsRejected() {
        XCTAssertThrowsError(try CustomHeader.validated([CustomHeader(name: "X-Gate", value: "a\r\nHost: evil")])) {
            XCTAssertEqual($0 as? CustomHeader.Problem, .invalidValue("X-Gate"))
        }
    }

    func testDuplicateNamesAreRejectedWhateverTheirCase() {
        let rows = [CustomHeader(name: "X-Gate", value: "a"), CustomHeader(name: "x-gate", value: "b")]
        XCTAssertThrowsError(try CustomHeader.validated(rows)) {
            XCTAssertEqual($0 as? CustomHeader.Problem, .duplicate("x-gate"))
        }
    }

    // MARK: - Every request to the server

    func testAPIRequestsCarryTheHeadersAndStillTheToken() async throws {
        let api = client(serving: [#"{"results": [], "next": null}"#])
        _ = try await api.listAllRaw(path: "tags")
        assertCarriesGate(StubProtocol.requests.last)
        XCTAssertEqual(StubProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"), "Token t")
    }

    func testTheSignInProbeCarriesTheHeaders() async throws {
        let api = client(serving: [#"{"children": "https://baby.example.com/api/children/"}"#])
        try await api.validateToken()
        assertCarriesGate(StubProtocol.requests.last)
    }

    func testImageUploadsCarryTheHeaders() async throws {
        let api = client(serving: [#"{"id": 1}"#])
        _ = try await api.uploadImage(path: "notes", lookup: "1", field: "image", filename: "a.jpg",
                                      mimeType: "image/jpeg", data: Data([0xFF, 0xD8]))
        let request = StubProtocol.requests.last
        assertCarriesGate(request)
        XCTAssertTrue(request?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
    }

    func testMediaFetchesCarryTheHeaders() async {
        let loader = ImageLoader(session: StubProtocol.install(["not an image"]))
        let url = URL(string: "https://baby.example.com/media/\(UUID().uuidString).jpg")!
        _ = await loader.image(for: url, token: "t", headers: gate)
        assertCarriesGate(StubProtocol.requests.last)
    }

    // MARK: - No other host

    /// CFNetwork copies custom headers onto a redirected request. A gate that bounces to a login
    /// page on its own domain must not be handed the secret on the way.
    func testACrossHostRedirectDropsTheHeaders() async {
        let api = client(serving: ["<html>Sign in</html>"])
        StubProtocol.redirect = URL(string: "https://team.gate.example/login")!
        _ = try? await api.validateToken()
        XCTAssertEqual(StubProtocol.requests.count, 2)
        let login = StubProtocol.requests.last
        XCTAssertEqual(login?.url?.host, "team.gate.example")
        XCTAssertNil(login?.value(forHTTPHeaderField: "CF-Access-Client-Id"))
        XCTAssertNil(login?.value(forHTTPHeaderField: "CF-Access-Client-Secret"))
    }

    func testASameHostRedirectKeepsTheHeaders() async throws {
        let api = client(serving: [#"{"children": "https://baby.example.com/api/children/"}"#])
        StubProtocol.redirect = URL(string: "https://baby.example.com/api/")!
        try await api.validateToken()
        XCTAssertEqual(StubProtocol.requests.count, 2)
        assertCarriesGate(StubProtocol.requests.last)
    }

    // MARK: - A gate's 403

    func testAGatePageOn403IsNotTheTokenBeingRejected() async {
        let api = client(serving: ["<html>Forbidden</html>"])
        StubProtocol.status = 403
        do {
            try await api.validateToken()
            XCTFail("a 403 passed the probe")
        } catch {
            XCTAssertEqual(error as? APIError, .decoding(Analytics.ListShape.nonJSON.rawValue))
        }
    }

    func testBabyBuddysOwn403IsStillForbidden() async {
        let api = client(serving: [#"{"detail": "Invalid token."}"#])
        StubProtocol.status = 403
        do {
            try await api.validateToken()
            XCTFail("a 403 passed the probe")
        } catch {
            XCTAssertEqual(error as? APIError, .forbidden)
        }
    }

    func testWithoutHeadersA403PageIsStillForbidden() async {
        let api = client(serving: ["<html>Forbidden</html>"], headers: [])
        StubProtocol.status = 403
        do {
            try await api.validateToken()
            XCTFail("a 403 passed the probe")
        } catch {
            XCTAssertEqual(error as? APIError, .forbidden)
        }
    }
}
