import XCTest
import SwiftData
@testable import BabyBuddy

/// A controllable transport: suspended replies exercise local edits, cancellation, and full
/// syncs arriving while the timer-only request is in flight. It never reaches a real server.
private final class TimerProbeTransport: URLProtocol {
    struct Reply {
        var status = 200
        var body: String
    }
    @MainActor static var requests: [URLRequest] = []
    @MainActor static var reply = Reply(body: #"{"results":[],"next":null}"#)
    @MainActor static var handler: (@MainActor (URLRequest) async -> Reply)?
    private var responseTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { responseTask?.cancel() }
    override func startLoading() {
        responseTask = Task { @MainActor [self] in
            Self.requests.append(request)
            let reply: Reply
            if let handler = Self.handler { reply = await handler(request) }
            else { reply = Self.reply }
            guard !Task.isCancelled else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

/// Covers the change-detection that gates the `Sync.completed` analytics signal: unchanged
/// server records must not dirty the store on re-pull, and a running timer's volatile
/// `duration` must not register as a change.
@MainActor
final class SyncChangeDetectionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var engine: SyncEngine!
    private var transportSession: URLSession!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
        TimerProbeTransport.requests = []
        TimerProbeTransport.handler = nil
        TimerProbeTransport.reply = .init(body: #"{"results":[],"next":null}"#)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TimerProbeTransport.self]
        transportSession = URLSession(configuration: configuration)
        let client = APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!, token: "t"),
                               session: transportSession)
        // A no-server session keeps the concurrent full-sync test entirely offline, even on
        // a developer simulator that has previously signed in. Restore credentials immediately.
        let savedConfig = KeychainStore.load()
        KeychainStore.clear()
        let session = AppSession()
        if let savedConfig { KeychainStore.save(config: savedConfig) }
        engine = SyncEngine(session: session, context: context, client: client)
    }

    private func json(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: payloadsEquivalent

    func testEquivalentIgnoresKeyOrder() {
        let a = json(["id": 1, "child": 2, "note": "hi"])
        let b = json(["note": "hi", "id": 1, "child": 2])
        XCTAssertTrue(LocalStore.payloadsEquivalent(a, b))
    }

    func testEquivalentIgnoresVolatileDuration() {
        let a = json(["id": 1, "child": 2, "start": "2024-01-15T10:00:00-05:00", "duration": "00:00:03"])
        let b = json(["id": 1, "child": 2, "start": "2024-01-15T10:00:00-05:00", "duration": "00:05:41"])
        XCTAssertTrue(LocalStore.payloadsEquivalent(a, b), "a running timer's drifting duration is not a change")
    }

    func testDifferentValuesAreNotEquivalent() {
        let a = json(["id": 1, "child": 2, "note": "hi"])
        let b = json(["id": 1, "child": 2, "note": "bye"])
        XCTAssertFalse(LocalStore.payloadsEquivalent(a, b))
    }

    // MARK: upsertFromServer change behavior

    func testUnchangedRepullDoesNotDirtyStore() throws {
        let payload = json(["id": 100, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "a"])
        _ = LocalStore.upsertFromServer(payload, kind: .note, in: context)
        try context.save()
        XCTAssertFalse(context.hasChanges)

        // Re-pulling the identical record must be a no-op (no write churn → meaningful hasChanges).
        _ = LocalStore.upsertFromServer(payload, kind: .note, in: context)
        XCTAssertFalse(context.hasChanges, "an unchanged re-pull should not dirty the store")
    }

    func testChangedRepullDirtiesStore() throws {
        let original = json(["id": 100, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "a"])
        _ = LocalStore.upsertFromServer(original, kind: .note, in: context)
        try context.save()
        XCTAssertFalse(context.hasChanges)

        let edited = json(["id": 100, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "edited"])
        _ = LocalStore.upsertFromServer(edited, kind: .note, in: context)
        XCTAssertTrue(context.hasChanges, "a real server change should dirty the store")
    }

    func testNewRecordDirtiesStore() {
        let payload = json(["id": 200, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "new"])
        _ = LocalStore.upsertFromServer(payload, kind: .note, in: context)
        XCTAssertTrue(context.hasChanges, "inserting a new record is a change")
    }

    override func tearDown() async throws {
        transportSession.invalidateAndCancel()
        TimerProbeTransport.handler = nil
        TimerProbeTransport.requests = []
    }

    // MARK: Read-only remote timer checks

    private func timerPayload(_ id: Int, name: String = "Sleep", duration: String = "00:00:05") -> Data {
        json(["id": id, "child": 1, "name": name,
              "start": "2024-01-15T10:00:00-05:00", "duration": duration])
    }

    @discardableResult
    private func cacheTimer(_ id: Int) throws -> LocalEntity {
        let timer = LocalStore.upsertFromServer(timerPayload(id), kind: .timer, in: context)!
        try context.save()
        return timer
    }

    private func page(_ records: [Data], next: String? = nil) -> String {
        let rows = records.map { String(decoding: $0, as: UTF8.self) }.joined(separator: ",")
        let link = next.map { "\"\($0)\"" } ?? "null"
        return "{\"results\":[\(rows)],\"next\":\(link)}"
    }

    private func assertProbe(_ expected: Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let changed = try await engine.remoteTimersChanged()
        XCTAssertEqual(changed, expected, file: file, line: line)
    }

    func testUnchangedProbeIsReadOnlyAndIgnoresDuration() async throws {
        let timer = try cacheTimer(1)
        let original = timer.payload
        let stamp = engine.lastSyncDate
        for duration in ["00:00:05", "00:20:00"] {
            TimerProbeTransport.reply = .init(body: page([timerPayload(1, duration: duration)]))
            try await assertProbe(false)
            XCTAssertEqual(timer.payload, original)
            XCTAssertFalse(context.hasChanges)
            XCTAssertEqual(engine.lastSyncDate, stamp)
            XCTAssertEqual(engine.status, .idle)
        }
        XCTAssertEqual(TimerProbeTransport.requests.count, 2)
        XCTAssertTrue(TimerProbeTransport.requests.allSatisfy {
            $0.httpMethod == "GET" && $0.url?.lastPathComponent == "timers"
        })
    }

    func testProbeDetectsRemovalAdditionAndEditWithoutWriting() async throws {
        let timer = try cacheTimer(1)
        for records in [[], [timerPayload(1), timerPayload(2)], [timerPayload(1, name: "Feeding")]] {
            TimerProbeTransport.reply = .init(body: page(records))
            try await assertProbe(true)
            XCTAssertFalse(context.hasChanges)
            XCTAssertNotNil(LocalStore.fetch(localID: timer.localID, in: context))
        }
    }

    func testProbeReadsAllPagesBeforeComparingTimers() async throws {
        try cacheTimer(1)
        try cacheTimer(2)
        let first = page([timerPayload(1)], next: "https://stub.invalid/api/timers/?offset=1")
        let second = page([timerPayload(2)])
        TimerProbeTransport.handler = { request in
            .init(body: request.url!.query!.contains("offset=0") ? first : second)
        }
        try await assertProbe(false)
        XCTAssertEqual(TimerProbeTransport.requests.count, 2)
        XCTAssertTrue(TimerProbeTransport.requests[1].url!.query!.contains("offset=1"))
    }

    func testProbeIgnoresPendingAndConflictedTimers() async throws {
        try cacheTimer(1)
        let dirty = try cacheTimer(2)
        for state in [SyncState.pendingCreate, .pendingUpdate, .pendingDelete, .conflicted] {
            dirty.syncState = state
            try context.save()
            for records in [[timerPayload(1)], [timerPayload(1), timerPayload(2, name: "Remote edit")]] {
                TimerProbeTransport.reply = .init(body: page(records))
                try await assertProbe(false)
                XCTAssertEqual(dirty.syncState, state)
                XCTAssertFalse(context.hasChanges)
            }
        }
    }

    func testProbeDoesNotFetchWithoutAServerTimer() async throws {
        try await assertProbe(false)
        let timer = try cacheTimer(1)
        timer.serverID = nil
        timer.syncState = .pendingCreate
        try await assertProbe(false)
        timer.serverID = 1
        timer.syncState = .pendingDelete
        try await assertProbe(false)
        XCTAssertTrue(TimerProbeTransport.requests.isEmpty)
    }

    func testProbeStopsAfterLastTimerButContinuesWithAnotherChildsTimer() async throws {
        let first = try cacheTimer(1)
        let second = try cacheTimer(2)
        second.childID = 2
        context.delete(first)
        try context.save()
        try await assertProbe(true)
        XCTAssertEqual(TimerProbeTransport.requests.count, 1)
        context.delete(second)
        try context.save()
        try await assertProbe(false)
        XCTAssertEqual(TimerProbeTransport.requests.count, 1)
    }

    func testFailedOrMalformedProbeNeverMeansDeletion() async throws {
        let timer = try cacheTimer(1)
        let id = timer.localID
        let invalidRows = [json(["name": "Missing ID"])]
        let replies: [TimerProbeTransport.Reply] = [
            .init(status: 500, body: "unavailable"), .init(status: 404, body: "missing endpoint"),
            .init(body: "not JSON"), .init(body: "{}"), .init(body: page(invalidRows)),
            .init(body: page([timerPayload(1), timerPayload(1)]))
        ]
        for reply in replies {
            TimerProbeTransport.reply = reply
            do {
                _ = try await engine.remoteTimersChanged()
                XCTFail("An invalid response must throw, never signal a remote stop")
            } catch {
                XCTAssertNotNil(error as? APIError)
            }
            XCTAssertNotNil(LocalStore.fetch(localID: id, in: context))
            XCTAssertFalse(context.hasChanges)
        }
        TimerProbeTransport.reply = .init(body: page([timerPayload(1)]))
        try await assertProbe(false) // a failure must release the in-flight guard
    }

    func testLocalEditDuringProbeDiscardsResponseAndDoesNotOverlap() async throws {
        let timer = try cacheTimer(1)
        let started = expectation(description: "timer request started")
        var release: CheckedContinuation<Void, Never>?
        TimerProbeTransport.handler = { _ in
            await withCheckedContinuation { continuation in
                release = continuation
                started.fulfill()
            }
            return .init(body: #"{"results":[],"next":null}"#)
        }
        let probe = Task { try await engine.remoteTimersChanged() }
        await fulfillment(of: [started], timeout: 5)
        try await assertProbe(false)
        XCTAssertEqual(TimerProbeTransport.requests.count, 1)
        timer.syncState = .pendingUpdate
        try context.save()
        release?.resume()
        let changed = try await probe.value
        XCTAssertFalse(changed)
    }

    func testFullSyncDuringProbeDiscardsEvenAnAlreadyCompletedSyncsResponse() async throws {
        try cacheTimer(1)
        let started = expectation(description: "timer request started")
        var release: CheckedContinuation<Void, Never>?
        TimerProbeTransport.handler = { _ in
            await withCheckedContinuation { continuation in
                release = continuation
                started.fulfill()
            }
            return .init(body: #"{"results":[],"next":null}"#)
        }
        let probe = Task { try await engine.remoteTimersChanged() }
        await fulfillment(of: [started], timeout: 5)
        // No configured server/queued writes in this fixture; sync still supersedes the probe.
        await engine.sync()
        release?.resume()
        let changed = try await probe.value
        XCTAssertFalse(changed, "A probe must not block or reuse a response predating full sync")
    }

    func testCancellationDuringRequestDoesNotTriggerSyncOrDelete() async throws {
        let timer = try cacheTimer(1)
        let id = timer.localID
        let started = expectation(description: "timer request started")
        var release: CheckedContinuation<Void, Never>?
        TimerProbeTransport.handler = { _ in
            await withCheckedContinuation { continuation in
                release = continuation
                started.fulfill()
            }
            return .init(body: #"{"results":[],"next":null}"#)
        }
        let probe = Task { try await engine.remoteTimersChanged() }
        await fulfillment(of: [started], timeout: 5)
        probe.cancel()
        release?.resume()
        do {
            _ = try await probe.value
            XCTFail("A cancelled probe must throw cancellation")
        } catch is CancellationError {
            XCTAssertNotNil(LocalStore.fetch(localID: id, in: context))
            XCTAssertFalse(context.hasChanges)
        }
        TimerProbeTransport.handler = nil
        TimerProbeTransport.reply = .init(body: page([timerPayload(1)]))
        try await assertProbe(false)
    }

    func testProbeSkipsWhileFullSyncIsDeliveringAWrite() async throws {
        try cacheTimer(1)
        LocalRepository(context: context).create(kind: .note, payload: [
            "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "queued",
        ])
        let started = expectation(description: "full sync POST started")
        var release: CheckedContinuation<Void, Never>?
        TimerProbeTransport.handler = { _ in
            await withCheckedContinuation { continuation in
                release = continuation
                started.fulfill()
            }
            return .init(body: #"{"id":9,"child":1,"time":"2024-01-15T10:00:00-05:00","note":"queued"}"#)
        }
        let fullSync = Task { await engine.sync() }
        await fulfillment(of: [started], timeout: 5)
        try await assertProbe(false)
        XCTAssertEqual(TimerProbeTransport.requests.count, 1)
        XCTAssertEqual(TimerProbeTransport.requests.first?.httpMethod, "POST")
        release?.resume()
        await fullSync.value
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingMutation>()).count, 0)
    }

    func testUnauthorizedProbeSignsOutWithoutWipingCache() async throws {
        let timer = try cacheTimer(1)
        let id = timer.localID
        let savedConfig = KeychainStore.load()
        defer {
            if let savedConfig { KeychainStore.save(config: savedConfig) }
            else { KeychainStore.clear() }
        }
        let config = ServerConfig(baseURL: URL(string: "https://stub.invalid")!, token: "expired")
        KeychainStore.save(config: config)
        let session = AppSession(context: context)
        XCTAssertTrue(session.isAuthenticated)
        engine = SyncEngine(session: session, context: context,
                            client: APIClient(config: config, session: transportSession))
        TimerProbeTransport.reply = .init(status: 401, body: "unauthorized")
        do {
            _ = try await engine.remoteTimersChanged()
            XCTFail("A rejected token must throw")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertNotNil(LocalStore.fetch(localID: id, in: context))
    }
}
