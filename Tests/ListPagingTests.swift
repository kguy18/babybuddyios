import XCTest
@testable import BabyBuddy

/// Serves canned bodies to `APIClient` in order, and records what was asked for.
///
/// The paging loop's stopping conditions are the thing under test, and they are only observable
/// across more than one request — so this is the smallest thing that can show a bare array stops
/// after one fetch while a `next` link keeps going. `CustomHeaderTests` uses it too, for the
/// headers on each request, a gate's 403 and a redirect.
final class StubProtocol: URLProtocol {
    /// Bodies to serve, in order. The last one repeats if the client asks again — a loop that
    /// fails to stop then hangs on data rather than passing on an exhausted queue.
    static var bodies: [Data] = []
    static var requests: [URLRequest] = []
    static var requestedURLs: [URL] { requests.compactMap(\.url) }
    /// The status every response carries.
    static var status = 200
    /// Answer the next request with a 302 to this URL instead, carrying every header across the way
    /// CFNetwork does (except `Authorization`, which it drops), so the redirect delegate decides.
    static var redirect: URL?

    static func install(_ bodies: [String]) -> URLSession {
        self.bodies = bodies.map { Data($0.utf8) }
        requests = []
        status = 200
        redirect = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        Self.requests.append(request)
        if let target = Self.redirect {
            Self.redirect = nil
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                           headerFields: ["Location": target.absoluteString])!
            var next = request
            next.url = target
            next.setValue(nil, forHTTPHeaderField: "Authorization")
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            return
        }
        let body = Self.bodies.count > 1 ? Self.bodies.removeFirst() : (Self.bodies.first ?? Data())
        let response = HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Covers the two halves of reading a list response: classifying the top-level shape
/// (``APIClient/splitPage(_:allowsUnpaginatedArray:)``) and paging on the result.
///
/// The shape half is where the risk lives. A tag pull that *throws* leaves the cache alone, but one
/// that returns an empty list looks to `SyncActor.pullTags` like a server with no tags — and it
/// reconciles deletions, so every cached tag would be deleted. Each rejection case below is
/// therefore asserted as a thrown error, never as an empty result.
final class ListPagingTests: XCTestCase {

    private func split(_ json: String, allowsUnpaginatedArray: Bool = false)
        throws -> (objects: [Data], hasNext: Bool) {
        try APIClient.splitPage(Data(json.utf8), allowsUnpaginatedArray: allowsUnpaginatedArray)
    }

    private func names(_ objects: [Data]) -> [String] {
        objects.compactMap {
            (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["name"] as? String
        }
    }

    private func assertRejected(_ json: String, as shape: Analytics.ListShape,
                                allowsUnpaginatedArray: Bool = false,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try split(json, allowsUnpaginatedArray: allowsUnpaginatedArray),
                             file: file, line: line) { error in
            XCTAssertEqual(error as? APIError, .decoding(shape.rawValue), file: file, line: line)
        }
    }

    // MARK: - Paginated objects (unchanged behaviour)

    func testPaginatedObjectWithAStringNextHasMorePages() throws {
        let page = try split(#"{"results": [{"name": "am"}], "next": "http://x/api/tags/?offset=1"}"#)
        XCTAssertEqual(names(page.objects), ["am"])
        XCTAssertTrue(page.hasNext)
    }

    func testPaginatedObjectWithNullOrMissingNextIsTheLastPage() throws {
        XCTAssertFalse(try split(#"{"results": [{"name": "am"}], "next": null}"#).hasNext)
        XCTAssertFalse(try split(#"{"results": [{"name": "am"}]}"#).hasNext)
    }

    func testEmptyPaginatedResultsIsASuccessfulEmptyPage() throws {
        let page = try split(#"{"results": [], "next": null}"#)
        XCTAssertTrue(page.objects.isEmpty)
        XCTAssertFalse(page.hasNext)
    }

    // MARK: - Bare arrays (opt-in)

    func testBareArrayIsOneCompletePageWhenAllowed() throws {
        let page = try split(#"[{"name": "am"}, {"name": "pm"}]"#, allowsUnpaginatedArray: true)
        XCTAssertEqual(names(page.objects), ["am", "pm"])
        XCTAssertFalse(page.hasNext, "no envelope means no next link — one page is the whole list")
    }

    func testEmptyBareArrayIsAnEmptyListNotAFailure() throws {
        let page = try split("[]", allowsUnpaginatedArray: true)
        XCTAssertTrue(page.objects.isEmpty)
        XCTAssertFalse(page.hasNext)
    }

    /// The opt-in is the whole design: a windowed, high-volume kind reconciles deletions against
    /// what it pulled, so silently reading page one of a paginated collection as the complete set
    /// would delete every cached record beyond it.
    func testBareArrayIsRejectedOnPathsThatDidNotOptIn() {
        assertRejected(#"[{"name": "am"}]"#, as: .unexpectedJSONType)
    }

    // MARK: - Malformed bodies stay failures

    func testObjectWithoutResultsIsRejectedRatherThanReadAsEmpty() {
        assertRejected(#"{"detail": "Not found."}"#, as: .objectMissingResults)
        assertRejected("{}", as: .objectMissingResults)
        // `results` present but not a list is still not a list.
        assertRejected(#"{"results": null}"#, as: .objectMissingResults)
        assertRejected(#"{"results": "am,pm"}"#, as: .objectMissingResults)
    }

    /// The case that opened this: a captive portal or reverse proxy answering the API with a page.
    func testHTMLIsRejected() {
        assertRejected("<!DOCTYPE html><html><body>Sign in</body></html>", as: .nonJSON,
                       allowsUnpaginatedArray: true)
        assertRejected("", as: .nonJSON, allowsUnpaginatedArray: true)
    }

    func testScalarJSONIsRejected() {
        for scalar in ["5", #""tags""#, "true", "null"] {
            assertRejected(scalar, as: .unexpectedJSONType, allowsUnpaginatedArray: true)
        }
    }

    /// A JSON array of non-objects is not a list of records. Re-serializing one would raise an ObjC
    /// exception instead of throwing — a crash, not a rejection — so the rows are checked first.
    func testArrayOfNonObjectsIsRejectedRatherThanCrashing() {
        assertRejected(#"["am", "pm"]"#, as: .unexpectedJSONType, allowsUnpaginatedArray: true)
        assertRejected(#"[{"name": "am"}, 5]"#, as: .unexpectedJSONType, allowsUnpaginatedArray: true)
        // Same hazard on the paginated path, where it has always been reachable.
        assertRejected(#"{"results": ["am"], "next": null}"#, as: .unexpectedJSONType)
    }

    // MARK: - Paging over the wire

    private func client(serving bodies: [String]) -> APIClient {
        let session = StubProtocol.install(bodies)
        return APIClient(config: ServerConfig(baseURL: URL(string: "https://baby.example.com")!,
                                              token: "t"),
                         session: session)
    }

    func testPaginatedResponsesFollowNextUntilItIsNull() async throws {
        let api = client(serving: [
            #"{"results": [{"name": "am"}, {"name": "pm"}], "next": "https://baby.example.com/api/tags/?offset=2"}"#,
            #"{"results": [{"name": "night"}], "next": null}"#,
        ])
        let records = try await api.listAllRaw(path: "tags", allowsUnpaginatedArray: true)
        XCTAssertEqual(names(records), ["am", "pm", "night"])
        XCTAssertEqual(StubProtocol.requestedURLs.count, 2)
        XCTAssertEqual(StubProtocol.requestedURLs.last?.query?.contains("offset=2"), true,
                       "the second page is fetched from where the first one ended")
    }

    func testBareArrayStopsAfterASingleRequest() async throws {
        let api = client(serving: [#"[{"name": "am"}, {"name": "pm"}]"#])
        let records = try await api.listAllRaw(path: "tags", allowsUnpaginatedArray: true)
        XCTAssertEqual(names(records), ["am", "pm"])
        XCTAssertEqual(StubProtocol.requestedURLs.count, 1, "no next link — asking again would loop")
    }

    func testEmptyBareArrayStopsAfterASingleRequest() async throws {
        let api = client(serving: ["[]"])
        let records = try await api.listAllRaw(path: "tags", allowsUnpaginatedArray: true)
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(StubProtocol.requestedURLs.count, 1)
    }

    /// The acceptance criterion, end to end: a proxy page surfaces as an error from the pull, so
    /// `pullTags` throws before it reaches the delete-what-the-server-no-longer-has step.
    func testAProxyPageFailsThePullInsteadOfReturningNoTags() async {
        let api = client(serving: ["<html><body>Sign in</body></html>"])
        do {
            let records = try await api.listAllRaw(path: "tags", allowsUnpaginatedArray: true)
            XCTFail("expected a decoding failure, got \(records.count) records")
        } catch {
            XCTAssertEqual(error as? APIError, .decoding(Analytics.ListShape.nonJSON.rawValue))
        }
    }

    /// Forward auth (Authentik, Authelia) redirects the token probe to its login page, which
    /// URLSession follows to a 200. Sign-in has to fail there, not on the first sync.
    func testALoginPageFailsTheTokenProbe() async {
        let api = client(serving: ["<!DOCTYPE html><html><body>Sign in</body></html>"])
        do {
            try await api.validateToken()
            XCTFail("a login page passed as the API")
        } catch {
            XCTAssertEqual(error as? APIError, .accessGate(.unknown))
        }
    }

    func testTheAPIRootPassesTheTokenProbe() async throws {
        let api = client(serving: [#"{"children": "https://baby.example.com/api/children/"}"#])
        try await api.validateToken()
    }

    func testANonJSONBodyNamesTheLoginProxy() {
        let message = APIError.decoding(Analytics.ListShape.nonJSON.rawValue).userMessage
        XCTAssertTrue(message.contains("/api/"), message)
    }
}
