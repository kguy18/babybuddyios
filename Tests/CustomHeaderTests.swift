import XCTest
@testable import BabyBuddy

/// Custom headers for a server behind an access gate (#148): which rows are accepted, that every
/// request to the server carries them, that no other host ever gets them, that a gate's 403 isn't
/// read as Baby Buddy rejecting the token, and which gate answered.
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

    private func probeError(_ api: APIClient) async -> APIError? {
        do {
            try await api.validateToken()
            XCTFail("the probe passed")
            return nil
        } catch {
            return error as? APIError
        }
    }

    func testAGatePageOn403IsNotTheTokenBeingRejected() async {
        let api = client(serving: ["<html>Forbidden</html>"])
        StubProtocol.status = 403
        let error = await probeError(api)
        XCTAssertEqual(error, .accessGate(.unknown))
    }

    /// Baby Buddy's own refusals are JSON, so a 403 page at sign-in is a gate even with no headers
    /// set: the person is told about the gate, not about their token.
    func testWithoutHeadersA403PageAtSignInIsStillTheGate() async {
        let api = client(serving: ["<html>Forbidden</html>"], headers: [])
        StubProtocol.status = 403
        let error = await probeError(api)
        XCTAssertEqual(error, .accessGate(.unknown))
    }

    func testBabyBuddysOwn403IsStillForbidden() async {
        let api = client(serving: [#"{"detail": "Invalid token."}"#])
        StubProtocol.status = 403
        let error = await probeError(api)
        XCTAssertEqual(error, .forbidden)
    }

    /// Past sign-in, a 403 page with headers set is a failure to read the answer, parked like one.
    func testDuringSyncA403PageWithHeadersIsNonJSON() async {
        let api = client(serving: ["<html>Forbidden</html>"])
        StubProtocol.status = 403
        do {
            _ = try await api.getRaw(path: "notes", id: 1)
            XCTFail("a 403 passed")
        } catch {
            XCTAssertEqual(error as? APIError, .decoding(Analytics.ListShape.nonJSON.rawValue))
        }
    }

    func testDuringSyncA403PageWithoutHeadersIsForbidden() async {
        let api = client(serving: ["<html>Forbidden</html>"], headers: [])
        StubProtocol.status = 403
        do {
            _ = try await api.getRaw(path: "notes", id: 1)
            XCTFail("a 403 passed")
        } catch {
            XCTAssertEqual(error as? APIError, .forbidden)
        }
    }

    // MARK: - Naming the gate

    /// Cloudflare Access answers a missing or wrong service token with a 302 to its team domain,
    /// which URLSession follows to the login page.
    func testARedirectToCloudflareAccessNamesIt() async {
        let api = client(serving: ["<html>Sign in</html>"], headers: [])
        StubProtocol.redirect = URL(string: "https://team.cloudflareaccess.com/cdn-cgi/access/login/baby.example.com")!
        let error = await probeError(api)
        XCTAssertEqual(error, .accessGate(.cloudflareAccess))
    }

    private func gate(at url: String, page: String) -> AccessGate {
        let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return AccessGate(response: response, body: Data(page.utf8))
    }

    func testTheGateIsNamedFromTheLoginPage() {
        XCTAssertEqual(gate(at: "https://baby.example.com/cdn-cgi/access/login", page: "<html></html>"), .cloudflareAccess)
        XCTAssertEqual(gate(at: "https://auth.example.com/if/flow/default-authentication-flow/", page: "<html></html>"),
                       .authentik)
        XCTAssertEqual(gate(at: "https://auth.example.com/", page: "<title>Login - Authelia</title>"), .authelia)
        XCTAssertEqual(gate(at: "https://baby.example.com/login", page: "<title>Sign in</title>"), .unknown)
    }

    /// Authentik's and Authelia's header logins use `Authorization`, the header carrying the Baby
    /// Buddy token, so sign-in doesn't open custom headers for them.
    func testOnlyGatesHeadersCanPassOpenAdvancedConfiguration() {
        XCTAssertTrue(AccessGate.cloudflareAccess.acceptsHeaders)
        XCTAssertTrue(AccessGate.unknown.acceptsHeaders)
        XCTAssertFalse(AccessGate.authentik.acceptsHeaders)
        XCTAssertFalse(AccessGate.authelia.acceptsHeaders)
    }

    func testANamedGateSaysHowToLetTheAppThrough() {
        XCTAssertTrue(APIError.accessGate(.cloudflareAccess).userMessage.contains("Advanced configuration"))
        XCTAssertTrue(APIError.accessGate(.authentik).userMessage.contains("Unauthenticated Paths"))
        XCTAssertTrue(APIError.accessGate(.authelia).userMessage.contains("bypass"))
        XCTAssertEqual(APIError.accessGate(.unknown).userMessage,
                       APIError.decoding(Analytics.ListShape.nonJSON.rawValue).userMessage)
    }

    // MARK: - Advanced configuration

    func testCloudflareHeadersGetTheirServiceTokenLabels() {
        let rows = HeaderRow.cloudflareServiceToken()
        XCTAssertEqual(rows.map(\.name), ["CF-Access-Client-Id", "CF-Access-Client-Secret"])
        XCTAssertEqual(rows.map { $0.preset?.label }, ["Client ID", "Client Secret"])
        XCTAssertEqual(rows.map { $0.preset?.secret }, [false, true])
        // A saved one reopened in Settings keeps its label, whatever case it was typed in.
        XCTAssertEqual(HeaderRow(CustomHeader(name: "cf-access-client-id", value: "x")).preset?.label, "Client ID")
        XCTAssertNil(HeaderRow(CustomHeader(name: "X-Gate", value: "x")).preset)
    }

    func testTheTraceStopsAtCloudflareThenGoesThroughItOnceFilledIn() {
        let stopped = SignInTrace.hops(for: .cloudflareAccess, host: "baby.example.com", ready: false)
        XCTAssertEqual(stopped.map(\.title), ["This app", "baby.example.com", "Cloudflare Access"])
        XCTAssertEqual(stopped.last?.kind, .stopped)

        let next = SignInTrace.hops(for: .cloudflareAccess, host: "baby.example.com", ready: true)
        XCTAssertEqual(next.map(\.kind), [.plain, .gate, .arrived])
        XCTAssertEqual(next.last?.detail, "baby.example.com")
    }

    func testAnUnknownGateStopsInFrontOfTheServer() {
        let stopped = SignInTrace.hops(for: .unknown, host: "baby.example.com", ready: false)
        XCTAssertEqual(stopped.count, 2)
        XCTAssertEqual(stopped.last?.title, "The gate in front of baby.example.com")
        XCTAssertEqual(stopped.last?.kind, .stopped)
        XCTAssertEqual(AdvancedConfigurationSheet.steps(for: .unknown, host: "baby.example.com").count, 1)
        XCTAssertTrue(AdvancedConfigurationSheet.steps(for: .cloudflareAccess, host: "baby.example.com")[1]
            .contains("**baby.example.com**"))
    }
}
