import Foundation

/// The slice of the Baby Buddy REST API the server tests need: arrange state on the server, and
/// check what the app did to it from outside the app.
///
/// Deliberately its own small client rather than the app's ``APIClient``: a test that checked the
/// app's writes through the app's own networking would pass straight through a shared bug.
struct BabyBuddyAPI {
    let baseURL: URL
    let token: String

    struct Failure: LocalizedError {
        let method: String
        let path: String
        let status: Int
        var errorDescription: String? { "\(method) /api/\(path)/ answered \(status)" }
    }

    // MARK: Requests

    /// `GET /api/<path>/` — the page's `results`.
    func list(_ path: String, _ query: [String: String] = [:]) async throws -> [[String: Any]] {
        var items = query
        items["limit"] = items["limit"] ?? "100"
        let body = try await send("GET", path, query: items)
        guard let page = body as? [String: Any], let results = page["results"] as? [[String: Any]] else {
            return (body as? [[String: Any]]) ?? []
        }
        return results
    }

    /// `POST /api/<path>/` — the created record.
    @discardableResult
    func create(_ path: String, _ fields: [String: Any]) async throws -> [String: Any] {
        try await send("POST", path, body: fields) as? [String: Any] ?? [:]
    }

    func patch(_ path: String, id: Int, _ fields: [String: Any]) async throws {
        _ = try await send("PATCH", "\(path)/\(id)", body: fields)
    }

    func delete(_ path: String, id: Int) async throws {
        _ = try await send("DELETE", "\(path)/\(id)")
    }

    /// The status of `GET /api/<path>/<id>/` — 404 once the app's delete has landed.
    func status(_ path: String, id: Int) async throws -> Int {
        let (_, response) = try await URLSession.shared.data(for: request("GET", "\(path)/\(id)"))
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }

    /// Is the server there and does it take this token? Used once per run, before the suite: a
    /// server that is down skips the tests, a token it refuses fails them.
    func probe() async -> Result<Void, Failure> {
        do {
            _ = try await send("GET", "")
            return .success(())
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(Failure(method: "GET", path: "", status: 0)) // unreachable
        }
    }

    // MARK: Waiting

    /// Polls until a record of `path` carries `marker` in one of its text fields — the app's push
    /// reaching the server — or gives up and returns nil.
    func waitForRecord(_ path: String, marker: String, timeout: TimeInterval = 40) async throws -> [String: Any]? {
        try await poll(timeout: timeout) {
            try await marked(in: path, marker: marker).first
        }
    }

    /// Polls until `id` is gone from `path` — the app's delete reaching the server.
    func waitForDeletion(_ path: String, id: Int, timeout: TimeInterval = 40) async throws -> Bool {
        try await poll(timeout: timeout) { try await status(path, id: id) == 404 ? true : nil } ?? false
    }

    /// Polls until `field` of `id` matches — the app's edit reaching the server.
    func waitForField(_ path: String, id: Int, field: String, contains text: String,
                      timeout: TimeInterval = 40) async throws -> Bool {
        try await poll(timeout: timeout) {
            let record = try await send("GET", "\(path)/\(id)") as? [String: Any]
            let value = record?[field] as? String ?? ""
            return value.contains(text) ? true : nil
        } ?? false
    }

    // MARK: Records this run created

    /// Records of `path` carrying `marker` in any text field — everything a test wrote, and nothing
    /// of App Review's or an earlier run's.
    func marked(in path: String, marker: String) async throws -> [[String: Any]] {
        try await list(path).filter { record in
            record.values.contains { ($0 as? String)?.contains(marker) == true }
        }
    }

    /// Deletes everything a test marked. Children and tags are never touched.
    func deleteMarked(in paths: [String], marker: String) async {
        for path in paths {
            let records = (try? await marked(in: path, marker: marker)) ?? []
            for record in records {
                if let id = record["id"] as? Int { try? await delete(path, id: id) }
            }
        }
    }

    /// Deletes timers left running by a run that never reached its teardown — a cancelled CI job,
    /// a stopped `xcodebuild`, a crashed runner.
    ///
    /// A running timer is the one piece of litter that shows on every signed-in device's Dashboard.
    /// A killed run's other records sit in history, carrying a marker no later test looks for, and
    /// the seeds pick free time around them (``freeSlot``).
    ///
    /// Age-gated rather than a blanket delete of every `ci-` timer, so two runs overlapping on the
    /// same server don't delete each other's live timer — an in-flight one is seconds old.
    func deleteStaleTimers(prefix: String, olderThan age: TimeInterval = 30 * 60) async {
        let cutoff = Date().addingTimeInterval(-age)
        for timer in (try? await list("timers")) ?? [] {
            guard let id = timer["id"] as? Int,
                  (timer["name"] as? String)?.hasPrefix(prefix) == true,
                  let started = (timer["start"] as? String).flatMap(Date.fromAPI),
                  started < cutoff
            else { continue }
            try? await delete("timers", id: id)
        }
    }

    /// The latest stretch ending by `before` in which `child` has no `path` record. It runs to
    /// `length.upperBound` where there's room and is never shorter than `length.lowerBound`.
    ///
    /// Baby Buddy refuses a sleep, feeding or tummy time that overlaps another of the child's, and
    /// this server is shared. The owner's own device logs to it, and a run killed before its
    /// teardown leaves its records behind, so a seed over a fixed window such as the last hour
    /// answers 400 whenever something is already there.
    func freeSlot(_ path: String, child: Int, length: ClosedRange<TimeInterval>,
                  before: Date) async throws -> (start: Date, end: Date) {
        let margin: TimeInterval = 60 // API times drop fractions of a second
        var end = before
        // One kind's records never overlap each other, so newest start first is newest end first.
        for record in try await list(path, ["child": "\(child)", "ordering": "-start"]) {
            guard let start = (record["start"] as? String).flatMap(Date.fromAPI),
                  let finish = (record["end"] as? String).flatMap(Date.fromAPI) else { continue }
            let free = finish.addingTimeInterval(margin)
            if end.timeIntervalSince(free) >= length.lowerBound {
                return (max(free, end.addingTimeInterval(-length.upperBound)), end)
            }
            end = min(end, start.addingTimeInterval(-margin))
        }
        return (end.addingTimeInterval(-length.upperBound), end)
    }

    /// The child the app will select: the server's first.
    func firstChild() async throws -> (id: Int, firstName: String) {
        guard let child = try await list("children", ["limit": "1"]).first,
              let id = child["id"] as? Int else {
            throw Failure(method: "GET", path: "children", status: 404)
        }
        return (id, child["first_name"] as? String ?? "")
    }

    // MARK: Internals

    private func request(_ method: String, _ path: String, query: [String: String] = [:],
                         body: [String: Any]? = nil) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api").appendingPathComponent(path),
            resolvingAgainstBaseURL: false)
        // Django wants the trailing slash; appendingPathComponent drops it.
        components?.path += "/"
        if !query.isEmpty { components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }

        var request = URLRequest(url: components?.url ?? baseURL, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        return request
    }

    @discardableResult
    private func send(_ method: String, _ path: String, query: [String: String] = [:],
                      body: [String: Any]? = nil) async throws -> Any {
        let (data, response) = try await URLSession.shared
            .data(for: request(method, path, query: query, body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw Failure(method: method, path: path, status: status)
        }
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }

    /// Runs `check` every second until it returns a value or `timeout` passes. The app pushes on its
    /// own schedule, so every server assertion waits rather than looking once.
    private func poll<T>(timeout: TimeInterval, _ check: () async throws -> T?) async throws -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let value = try await check() { return value }
            try? await Task.sleep(for: .seconds(1))
        } while Date() < deadline
        return nil
    }
}

extension Date {
    /// The format Baby Buddy's API takes for times.
    var apiTime: String { ISO8601DateFormatter.api.string(from: self) }

    /// Reads a time back out of a response. Both formatters are tried because some Baby Buddy
    /// versions return fractional seconds and some don't, and a formatter set for one rejects the
    /// other outright — a silent `nil` here would quietly stop the stale sweep from ever firing.
    static func fromAPI(_ string: String) -> Date? {
        ISO8601DateFormatter.api.date(from: string)
            ?? ISO8601DateFormatter.apiFractional.date(from: string)
    }
}

extension ISO8601DateFormatter {
    static let api: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let apiFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
