import Foundation

/// Connection settings for a Baby Buddy server.
struct ServerConfig: Equatable {
    /// Base server URL, e.g. `https://baby.example.com`. The `/api/` prefix is appended internally.
    var baseURL: URL
    var token: String
    /// Headers an access gate in front of the server checks, such as a service token or a shared
    /// secret. Sent on every request to the server's host and never to another one.
    var headers: [CustomHeader] = []
}

/// One name and value pair from the "Custom headers" rows at sign-in.
struct CustomHeader: Codable, Equatable {
    var name: String
    var value: String

    /// Why a set of rows can't be saved, worded for the person who typed them.
    enum Problem: Error, Equatable {
        case empty
        case reserved(String)
        case invalidName(String)
        case invalidValue(String)
        case duplicate(String)

        var message: String {
            switch self {
            case .empty: return "Each custom header needs a name and a value."
            case .reserved(let name) where name.lowercased() == "authorization":
                return "Authorization carries your API token, so it can't be a custom header."
            case .reserved(let name): return "The app sets \(name) itself, so it can't be a custom header."
            case .invalidName(let name): return "\"\(name)\" isn't a valid header name. Use letters, digits and dashes."
            case .invalidValue(let name): return "The value for \(name) can't contain a line break or control character."
            case .duplicate(let name): return "\(name) is set more than once."
            }
        }
    }

    /// Names that would replace the Baby Buddy token or break the request.
    private static let reserved: Set<String> = [
        "authorization", "host", "content-type", "content-length", "accept", "cookie",
    ]

    /// RFC 9110's `token` characters, the only ones a header name may contain.
    private static let tokenCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~")

    /// The rows trimmed, or the first problem with them. A row with an empty name or value is an
    /// error rather than skipped: dropping it quietly would sign in without a header the user typed.
    static func validated(_ rows: [CustomHeader]) throws -> [CustomHeader] {
        var seen: Set<String> = []
        return try rows.map { row in
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { throw Problem.empty }
            guard name.unicodeScalars.allSatisfy(tokenCharacters.contains) else { throw Problem.invalidName(name) }
            guard !reserved.contains(name.lowercased()) else { throw Problem.reserved(name) }
            guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw Problem.invalidValue(name)
            }
            guard seen.insert(name.lowercased()).inserted else { throw Problem.duplicate(name) }
            return CustomHeader(name: name, value: value)
        }
    }
}

/// Strips the custom headers from a redirect that leaves the server's host. CFNetwork copies every
/// header except `Authorization` onto a redirected request, so a gate that bounces an unauthorized
/// request to a login page on another domain would otherwise be handed the secret. The redirect
/// is still followed, so the login page answers and sign-in reports it the way #147 does.
final class CustomHeaderRedirectGuard: NSObject, URLSessionTaskDelegate {
    private let names: [String]

    /// `nil` when there's nothing to strip, so a request without custom headers behaves as before.
    static func make(for headers: [CustomHeader]) -> CustomHeaderRedirectGuard? {
        headers.isEmpty ? nil : CustomHeaderRedirectGuard(names: headers.map(\.name))
    }

    private init(names: [String]) { self.names = names }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard request.url?.host?.lowercased() != response.url?.host?.lowercased() else { return request }
        var stripped = request
        for name in names { stripped.setValue(nil, forHTTPHeaderField: name) }
        return stripped
    }
}

/// Query parameters for list requests.
struct ListQuery {
    var child: Int?
    /// Base name for the inclusive range filter (`<timeParam>_min`/`<timeParam>_max`). Baby
    /// Buddy names these per model: start/end events use `start`, time-stamped records use
    /// `date` (see ``EntityKind/rangeFilterParam``). Both bounds are `IsoDateTimeFilter`s.
    var timeParam: String = "date"
    var timeMin: Date?
    var timeMax: Date?
    var ordering: String?
    var limit: Int?
    var offset: Int?

    func items() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let child { items.append(.init(name: "child", value: String(child))) }
        if let timeMin {
            items.append(.init(name: "\(timeParam)_min", value: APIDate.isoDateTime.string(from: timeMin)))
        }
        if let timeMax {
            items.append(.init(name: "\(timeParam)_max", value: APIDate.isoDateTime.string(from: timeMax)))
        }
        if let ordering { items.append(.init(name: "ordering", value: ordering)) }
        if let limit { items.append(.init(name: "limit", value: String(limit))) }
        if let offset { items.append(.init(name: "offset", value: String(offset))) }
        return items
    }
}

/// Async REST client for the Baby Buddy API. Stateless aside from its ``ServerConfig``;
/// the repository/sync layers own retry and persistence concerns.
final class APIClient {
    private let config: ServerConfig
    private let session: URLSession

    init(config: ServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: Requests

    /// Fetch a single page of a collection.
    func list<T: APIResource>(_ type: T.Type, query: ListQuery = ListQuery()) async throws -> Paged<T> {
        let req = try makeRequest(path: "\(T.path)/", method: "GET", query: query.items())
        return try await send(req, decode: Paged<T>.self)
    }

    /// Fetch all pages of a collection, following `next` links.
    func listAll<T: APIResource>(_ type: T.Type, query: ListQuery = ListQuery()) async throws -> [T] {
        var query = query
        if query.limit == nil { query.limit = 100 }
        var offset = 0
        var all: [T] = []
        while true {
            query.offset = offset
            let page = try await list(T.self, query: query)
            all.append(contentsOf: page.results)
            if page.next == nil || page.results.isEmpty { break }
            offset += page.results.count
        }
        return all
    }

    func get<T: APIResource>(_ type: T.Type, id: Int) async throws -> T {
        let req = try makeRequest(path: "\(T.path)/\(id)/", method: "GET")
        return try await send(req, decode: T.self)
    }

    func create<T: APIResource>(_ body: T) async throws -> T {
        var req = try makeRequest(path: "\(T.path)/", method: "POST")
        req.httpBody = try APICoders.encoder.encode(body)
        return try await send(req, decode: T.self)
    }

    /// PATCH with an explicit field dictionary so partial updates don't clobber
    /// unspecified fields with nulls.
    func patch<T: APIResource>(_ type: T.Type, id: Int, fields: [String: AnyEncodable]) async throws -> T {
        var req = try makeRequest(path: "\(T.path)/\(id)/", method: "PATCH")
        req.httpBody = try APICoders.encoder.encode(fields)
        return try await send(req, decode: T.self)
    }

    func delete<T: APIResource>(_ type: T.Type, id: Int) async throws {
        let req = try makeRequest(path: "\(T.path)/\(id)/", method: "DELETE")
        _ = try await sendRaw(req)
    }

    // MARK: Raw (payload-oriented) requests
    //
    // The sync engine works with opaque JSON objects keyed by ``EntityKind`` rather than
    // typed DTOs, so these mirror the typed methods but pass `Data` through untouched.

    /// Fetch all pages of a collection as raw JSON objects (one `Data` per record).
    ///
    /// Pass `allowsUnpaginatedArray` only for a low-volume, un-windowed collection that some
    /// servers return without a pagination envelope — see ``splitPage(_:allowsUnpaginatedArray:)``
    /// for why it is not the default.
    func listAllRaw(path: String, query: ListQuery = ListQuery(),
                    allowsUnpaginatedArray: Bool = false) async throws -> [Data] {
        var query = query
        if query.limit == nil { query.limit = 100 }
        var offset = 0
        var all: [Data] = []
        while true {
            query.offset = offset
            let req = try makeRequest(path: "\(path)/", method: "GET", query: query.items())
            let data = try await sendRaw(req)
            let (objects, hasNext) = try Self.splitPage(data, allowsUnpaginatedArray: allowsUnpaginatedArray)
            all.append(contentsOf: objects)
            if !hasNext || objects.isEmpty { break }
            offset += objects.count
        }
        return all
    }

    func getRaw(path: String, id: Int) async throws -> Data {
        try await sendRaw(try makeRequest(path: "\(path)/\(id)/", method: "GET"))
    }

    func createRaw(path: String, body: Data) async throws -> Data {
        var req = try makeRequest(path: "\(path)/", method: "POST")
        req.httpBody = body
        return try await sendRaw(req)
    }

    func patchRaw(path: String, id: Int, body: Data) async throws -> Data {
        var req = try makeRequest(path: "\(path)/\(id)/", method: "PATCH")
        req.httpBody = body
        return try await sendRaw(req)
    }

    /// PATCH a single image file field (`multipart/form-data`) onto an existing record — the one
    /// non-JSON write. `lookup` is the detail-route identifier, which is *not* always the database
    /// id: Baby Buddy routes children by `slug` (`lookup_field = "slug"` on its child view) and
    /// everything else by numeric id. Returns the updated record so the caller can reconcile the
    /// new media URL.
    func uploadImage(path: String, lookup: String, field: String, filename: String,
                     mimeType: String, data: Data) async throws -> Data {
        guard Self.isSafeLookup(lookup) else { throw APIError.invalidURL }
        let boundary = MultipartForm.boundary()
        var req = try makeRequest(path: "\(path)/\(lookup)/", method: "PATCH")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = MultipartForm.imageBody(
            boundary: boundary, field: field, filename: filename, mimeType: mimeType, data: data)
        return try await sendRaw(req)
    }

    /// Whether a detail-route lookup value is safe to splice into a request path. `makeRequest`
    /// appends the whole path in one go, so a `/` or `..` reaching it from a server payload would
    /// repoint the request; pre-escaping isn't an option either, because `appendingPathComponent`
    /// would then double-encode the `%`. Baby Buddy ids are digits and its slugs are Django
    /// `SlugField`s, so accept exactly `validate_slug`'s alphabet and reject anything else.
    static func isSafeLookup(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy(slugAlphabet.contains)
    }

    private static let slugAlphabet = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    func deleteRaw(path: String, id: Int) async throws {
        _ = try await sendRaw(try makeRequest(path: "\(path)/\(id)/", method: "DELETE"))
    }

    /// Split a list body into per-record JSON `Data` plus a has-next flag.
    ///
    /// The modern shape is DRF's `{ "results": [...], "next": … }`. Some Baby Buddy servers answer
    /// `tags` with a bare top-level array and no pagination envelope; `allowsUnpaginatedArray`
    /// accepts that as a single complete page.
    ///
    /// **That tolerance is opt-in per call rather than generic**, because a bare array carries no
    /// `next` marker to distinguish "this is everything" from "this is page one". If a server did
    /// paginate one, we would read the first page as the whole collection — and
    /// ``SyncActor/pull(kind:client:windowDays:)`` reconciles deletions against exactly that set,
    /// so every cached record past the first page would be deleted. Tags are low-volume, not
    /// windowed, and the one endpoint observed answering this way, so only that path opts in.
    ///
    /// Every other shape stays a decoding failure. An unrecognized object must not be read as an
    /// empty list: a proxy or captive-portal page would then look like a server with no tags, and
    /// ``SyncActor/pullTags(client:)`` would delete the cached ones.
    ///
    /// The thrown detail is a ``Analytics/ListShape`` raw value — a closed category, never any
    /// part of the body — so the failure is diagnosable without collecting response content.
    static func splitPage(_ data: Data,
                          allowsUnpaginatedArray: Bool = false) throws -> (objects: [Data], hasNext: Bool) {
        // `.fragmentsAllowed` so a top-level scalar parses and is categorized as the wrong JSON
        // type rather than being indistinguishable from an HTML error page.
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw APIError.decoding(Analytics.ListShape.nonJSON.rawValue)
        }

        let results: [Any]
        let hasNext: Bool
        switch root {
        case let object as [String: Any]:
            guard let page = object["results"] as? [Any] else {
                throw APIError.decoding(Analytics.ListShape.objectMissingResults.rawValue)
            }
            results = page
            hasNext = object["next"] is String
        case let array as [Any] where allowsUnpaginatedArray:
            results = array
            hasNext = false
        default:
            throw APIError.decoding(Analytics.ListShape.unexpectedJSONType.rawValue)
        }

        // Every row has to be a JSON object before any of it is re-serialized: given anything else
        // `data(withJSONObject:)` raises an ObjC `NSInvalidArgumentException`, which is not a Swift
        // error and would take the app down rather than throw. A page with a non-object row isn't a
        // page of records, so reject the body — reachable from either shape, but newly likely on a
        // bare array, where a proxy answering `["…"]` is exactly the case being guarded.
        guard let rows = results as? [[String: Any]] else {
            throw APIError.decoding(Analytics.ListShape.unexpectedJSONType.rawValue)
        }
        let objects = try rows.map { try JSONSerialization.data(withJSONObject: $0) }
        return (objects, hasNext)
    }

    /// Lightweight reachability + auth probe used during onboarding.
    ///
    /// Baby Buddy answers this with JSON whatever the status, Django REST's refusals included, so a
    /// page in its place came from something in front of it. Forward auth (Authentik, Authelia) and
    /// Cloudflare Access redirect to a login page, which URLSession follows to a 200; a gate can
    /// also refuse outright with a 401 or 403 page. Without this check sign-in would succeed on the
    /// 200 and the first sync fail instead, or a gate's 403 read as a rejected token.
    @discardableResult
    func validateToken() async throws -> Bool {
        let (data, http) = try await fetch(try makeRequest(path: "", method: "GET"))
        let isJSON = (try? JSONSerialization.jsonObject(with: data)) != nil
        if !isJSON, (200..<300).contains(http.statusCode) || http.statusCode == 401 || http.statusCode == 403 {
            throw APIError.accessGate(AccessGate(response: http, body: data))
        }
        _ = try check(data, http)
        return true
    }

    // MARK: Internals

    private func makeRequest(path: String, method: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard var comps = URLComponents(
            url: config.baseURL.appendingPathComponent("api").appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidURL }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        for header in config.headers { req.setValue(header.value, forHTTPHeaderField: header.name) }
        req.setValue("Token \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, decode: T.Type) async throws -> T {
        let data = try await sendRaw(req)
        do {
            return try APICoders.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    @discardableResult
    private func sendRaw(_ req: URLRequest) async throws -> Data {
        let (data, http) = try await fetch(req)
        return try check(data, http)
    }

    private func fetch(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(
                for: req, delegate: CustomHeaderRedirectGuard.make(for: config.headers))
        } catch let urlError as URLError {
            throw APIError.offline(reason: APIError.TransportFailure(urlError.code))
        }
        // Not an HTTP response at all — something answered, but not the API.
        guard let http = response as? HTTPURLResponse else {
            throw APIError.offline(reason: .other)
        }
        return (data, http)
    }

    private func check(_ data: Data, _ http: HTTPURLResponse) throws -> Data {
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        case 403:
            // A gate refuses with 403 too. Baby Buddy's own refusal is always JSON (Django REST),
            // so with custom headers set, a 403 page means the gate turned the headers down.
            if !config.headers.isEmpty, (try? JSONSerialization.jsonObject(with: data)) == nil {
                throw APIError.decoding(Analytics.ListShape.nonJSON.rawValue)
            }
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            throw APIError.conflict
        case 400...499:
            throw APIError.badRequest(status: http.statusCode,
                                      message: Self.errorMessage(from: data),
                                      fields: Self.errorFields(from: data))
        default:
            throw APIError.server(status: http.statusCode)
        }
    }

    /// The field names a DRF validation body named (`{"amount": ["..."]}` -> `["amount"]`). Keys
    /// only — the messages themselves can echo what the user entered, so they never leave the device.
    private static func errorFields(from data: Data) -> [String] {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return dict.keys.sorted()
    }

    /// A DRF validation body as sentences a person can read in Pending Changes. Each field's
    /// messages are joined into one line; `non_field_errors` is unlabeled (the message speaks for
    /// the whole record), other keys become a plain label ("Amount: This field is required.").
    static func errorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let dict = obj as? [String: Any] else { return String(data: data, encoding: .utf8) }
        let lines: [String] = dict.keys.sorted().compactMap { key in
            let value = dict[key]
            let text: String
            switch value {
            case let list as [Any]: text = list.map { "\($0)" }.joined(separator: " ")
            case let one?: text = "\(one)"
            case nil: return nil
            }
            // Baby Buddy's overlap message embeds a link to the other entry as raw HTML.
            let plain = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            if key == "non_field_errors" || key == "detail" { return plain }
            let label = key.replacingOccurrences(of: "_", with: " ").capitalized
            return "\(label): \(plain)"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// Type-erased `Encodable` so PATCH payloads can be assembled as `[String: AnyEncodable]`.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
