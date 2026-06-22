import Foundation

/// Connection settings for a Baby Buddy server.
struct ServerConfig: Equatable {
    /// Base server URL, e.g. `https://baby.example.com`. The `/api/` prefix is appended internally.
    var baseURL: URL
    var token: String
}

/// Query parameters for list requests.
struct ListQuery {
    var child: Int?
    var dateMin: Date?
    var dateMax: Date?
    var ordering: String?
    var limit: Int?
    var offset: Int?

    func items() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let child { items.append(.init(name: "child", value: String(child))) }
        if let dateMin { items.append(.init(name: "date_min", value: APIDate.isoDateTime.string(from: dateMin))) }
        if let dateMax { items.append(.init(name: "date_max", value: APIDate.isoDateTime.string(from: dateMax))) }
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
    func listAllRaw(path: String, query: ListQuery = ListQuery()) async throws -> [Data] {
        var query = query
        if query.limit == nil { query.limit = 100 }
        var offset = 0
        var all: [Data] = []
        while true {
            query.offset = offset
            let req = try makeRequest(path: "\(path)/", method: "GET", query: query.items())
            let data = try await sendRaw(req)
            let (objects, hasNext) = try Self.splitPage(data)
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

    func deleteRaw(path: String, id: Int) async throws {
        _ = try await sendRaw(try makeRequest(path: "\(path)/\(id)/", method: "DELETE"))
    }

    /// Split a DRF paginated list body into per-record JSON `Data` plus a has-next flag.
    private static func splitPage(_ data: Data) throws -> (objects: [Data], hasNext: Bool) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [Any] else {
            throw APIError.decoding("Unexpected list response shape")
        }
        let objects = try results.map { try JSONSerialization.data(withJSONObject: $0) }
        return (objects, root["next"] is String)
    }

    /// Lightweight reachability + auth probe used during onboarding.
    @discardableResult
    func validateToken() async throws -> Bool {
        let req = try makeRequest(path: "", method: "GET")
        _ = try await sendRaw(req)
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
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .timedOut, .cannotFindHost, .dnsLookupFailed, .dataNotAllowed:
                throw APIError.offline
            default:
                throw APIError.offline
            }
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.offline }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            throw APIError.conflict
        case 400...499:
            throw APIError.badRequest(status: http.statusCode, message: Self.errorMessage(from: data))
        default:
            throw APIError.server(status: http.statusCode)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let dict = obj as? [String: Any] {
            return dict.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        }
        return String(data: data, encoding: .utf8)
    }
}

/// Type-erased `Encodable` so PATCH payloads can be assembled as `[String: AnyEncodable]`.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
