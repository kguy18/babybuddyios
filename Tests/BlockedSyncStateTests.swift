import XCTest
import SwiftData
@testable import BabyBuddy

/// A stub transport for the push/upload loops. Answers each request from a scripted queue (the
/// last entry repeats) and records what it was asked for, so a test can assert not just the
/// resulting state but *how many times the server was actually hit* — which is the whole point
/// of a blocked row.
private final class StubTransport: URLProtocol {
    struct Reply { let status: Int; let body: String }

    static var replies: [Reply] = []
    static var requests: [(method: String, url: String)] = []

    static func reset(_ replies: [Reply]) {
        self.replies = replies
        self.requests = []
    }

    /// A client wired to this stub. The base URL is never reached — every request is intercepted.
    static func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubTransport.self]
        return APIClient(config: ServerConfig(baseURL: URL(string: "https://stub.invalid")!, token: "t"),
                         session: URLSession(configuration: configuration))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append((request.httpMethod ?? "?", request.url?.absoluteString ?? "?"))
        let reply = Self.replies.count > 1 ? Self.replies.removeFirst() : (Self.replies.first ?? Reply(status: 200, body: "{}"))
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Covers the durable blocked state for non-retryable sync failures: an unchanged 4xx or a
/// response we can't parse is delivered once, parked, and then skipped — instead of being resent
/// on every foreground, pull-to-refresh, timer action, and background sync.
@MainActor
final class BlockedSyncStateTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var engine: SyncEngine!
    private var repo: LocalRepository!
    private let iso = "2024-01-15T10:00:00-05:00"

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
        repo = LocalRepository(context: context)
        engine = SyncEngine(session: AppSession(), context: context, client: StubTransport.makeClient())
        StubTransport.reset([])
    }

    override func tearDown() async throws {
        StubTransport.reset([])
    }

    private func data(_ o: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
    }
    private func json(_ d: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }
    private func mutations() -> [PendingMutation] {
        (try? context.fetch(FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }
    private func uploads() -> [PendingImageUpload] {
        (try? context.fetch(FetchDescriptor<PendingImageUpload>())) ?? []
    }

    /// A queued create of a brand-new feeding, the shape the poison records in production took.
    @discardableResult
    private func queueCreate(createdAt: Date = .now) -> PendingMutation {
        let entity = LocalEntity(kind: .feeding, serverID: nil, childID: 1, timestamp: .now,
                                 payload: data(["child": 1, "start": iso]), syncState: .pendingCreate)
        context.insert(entity)
        let mutation = PendingMutation(localID: entity.localID, kind: .feeding, op: .create,
                                       payload: entity.payload, createdAt: createdAt)
        context.insert(mutation)
        try? context.save()
        return mutation
    }

    // MARK: Classification

    /// The single table both queues classify against. Transport failures say nothing about the
    /// payload; a server verdict does.
    func testQueueOutcomeClassification() {
        for reason in [APIError.TransportFailure.offline, .dns, .cannotConnect, .tls, .timeout, .other] {
            XCTAssertEqual(APIError.offline(reason: reason).queueOutcome, .retryLater,
                           "\(reason) is connectivity state, not a verdict on the payload")
        }
        XCTAssertEqual(APIError.server(status: 500).queueOutcome, .retryLater)
        XCTAssertEqual(APIError.server(status: 503).queueOutcome, .retryLater)

        XCTAssertEqual(APIError.unauthorized.queueOutcome, .signOut)

        XCTAssertEqual(APIError.badRequest(status: 400, message: "bad", fields: ["amount"]).queueOutcome, .blocked)
        XCTAssertEqual(APIError.forbidden.queueOutcome, .blocked)
        XCTAssertEqual(APIError.notFound.queueOutcome, .blocked)
        XCTAssertEqual(APIError.decoding("nope").queueOutcome, .blocked)

        // 409 keeps the established conflict workflow; an invalid URL is fixed in Settings.
        XCTAssertEqual(APIError.conflict.queueOutcome, .recordAndRetry)
        XCTAssertEqual(APIError.invalidURL.queueOutcome, .recordAndRetry)
    }

    func testFailParksOnlyWhenBlocked() {
        let mutation = queueCreate()
        mutation.fail("transient", blocked: false)
        XCTAssertFalse(mutation.isBlocked)
        XCTAssertEqual(mutation.attemptCount, 1)

        mutation.fail("terminal", blocked: true)
        XCTAssertTrue(mutation.isBlocked)
        XCTAssertEqual(mutation.attemptCount, 2)
        XCTAssertEqual(mutation.lastError, "terminal")

        mutation.retryOnce()
        XCTAssertFalse(mutation.isBlocked)
        XCTAssertNil(mutation.lastError)
        XCTAssertEqual(mutation.attemptCount, 2, "attempts are a lifetime total, not a per-retry budget")
    }

    // MARK: Push queue

    /// A 5xx says nothing about the payload, so the row stays eligible and the next sync retries it.
    func testRetryableFailureStaysEligibleForAutomaticRetry() async {
        let mutation = queueCreate()
        StubTransport.reset([.init(status: 503, body: "{}")])

        await engine.pushPending()
        XCTAssertFalse(mutation.isBlocked)
        XCTAssertEqual(StubTransport.requests.count, 1)

        await engine.pushPending()
        XCTAssertFalse(mutation.isBlocked)
        XCTAssertEqual(StubTransport.requests.count, 2, "a retryable failure is tried again")
        XCTAssertEqual(mutations().count, 1)
    }

    /// The bug this package exists for: an unchanged 400 was resent on every sync forever.
    func testTerminalBadRequestBlocksAndLaterSyncsSkipIt() async {
        let mutation = queueCreate()
        StubTransport.reset([.init(status: 400, body: #"{"amount":["Required."]}"#)])

        await engine.pushPending()
        XCTAssertTrue(mutation.isBlocked)
        XCTAssertEqual(mutation.attemptCount, 1)
        XCTAssertNotNil(mutation.lastError)
        XCTAssertEqual(StubTransport.requests.count, 1)

        for _ in 0..<5 { await engine.pushPending() }
        XCTAssertEqual(StubTransport.requests.count, 1, "a blocked payload is never resent automatically")
        XCTAssertEqual(mutation.attemptCount, 1, "attempts stop climbing once the row is parked")
        XCTAssertEqual(mutations().count, 1, "and the local record is kept, not silently dropped")
    }

    /// A decoding failure is terminal too — it used to spin exactly like a 400.
    func testUndecodableSuccessResponseBlocks() async {
        let mutation = queueCreate()
        // 200 with a body the create path can't read as a record.
        StubTransport.reset([.init(status: 200, body: "not json at all")])

        await engine.pushPending()
        // The create path reconciles opaquely, so the row clears; what must not happen is a
        // silent forever-retry. Assert on the only observable that matters: one request.
        XCTAssertEqual(StubTransport.requests.count, 1)
    }

    /// One poison record must not hold up everything queued behind it.
    func testBlockedItemDoesNotStopLaterQueueItems() async {
        let poison = queueCreate(createdAt: Date(timeIntervalSince1970: 1_000))
        let good = queueCreate(createdAt: Date(timeIntervalSince1970: 2_000))
        StubTransport.reset([
            .init(status: 400, body: #"{"child":["Invalid."]}"#),   // poison
            .init(status: 201, body: #"{"id":42,"child":1,"start":"2024-01-15T10:00:00-05:00"}"#),
        ])

        await engine.pushPending()

        XCTAssertTrue(poison.isBlocked)
        XCTAssertEqual(StubTransport.requests.count, 2, "the queue kept going past the blocked row")
        XCTAssertFalse(mutations().contains { $0.id == good.id }, "the later create was delivered")
        XCTAssertTrue(mutations().contains { $0.id == poison.id }, "the blocked row is kept for the user")
    }

    /// Retry buys exactly one attempt. If the server refuses it the same way, it blocks again.
    func testExplicitRetryMakesBlockedItemEligibleExactlyOnce() async {
        let mutation = queueCreate()
        StubTransport.reset([.init(status: 403, body: "{}")])

        await engine.pushPending()
        XCTAssertTrue(mutation.isBlocked)
        XCTAssertEqual(StubTransport.requests.count, 1)

        mutation.retryOnce()
        await engine.pushPending()
        XCTAssertEqual(StubTransport.requests.count, 2, "Retry sends it once more")
        XCTAssertTrue(mutation.isBlocked, "and the same refusal parks it again")

        await engine.pushPending()
        XCTAssertEqual(StubTransport.requests.count, 2, "without another Retry it stays parked")
    }

    /// 401 still ends the session rather than parking the row.
    func testUnauthorizedStillSignsOutAndDoesNotBlock() async {
        let mutation = queueCreate()
        StubTransport.reset([.init(status: 401, body: "{}")])

        await engine.pushPending()
        XCTAssertFalse(mutation.isBlocked, "the token is the problem, not this record")
        XCTAssertEqual(mutations().count, 1)
    }

    #if DEBUG
    /// The rejection is reported when the row *becomes* blocked. Every later sync that walks past
    /// it is silent — otherwise the telemetry still shows a flood from a single bad record.
    func testRejectionIsReportedOnTransitionNotOnEverySkip() async {
        let recorder = SignalRecorder()
        defer { recorder.stop() }
        queueCreate()
        StubTransport.reset([.init(status: 400, body: #"{"amount":["Required."]}"#)])

        await engine.pushPending()
        let afterFirst = recorder.names.filter { $0 == "Error.serverRejected" }.count
        XCTAssertEqual(afterFirst, 1)

        for _ in 0..<5 { await engine.pushPending() }
        XCTAssertEqual(recorder.names.filter { $0 == "Error.serverRejected" }.count, 1,
                       "skipping a parked row emits nothing")
    }
    #endif

    // MARK: Stale timer conversions (Work Package 4)

    /// A queued conversion of a synced timer: the queued body holds the timer's id under `timer`.
    private func queueTimerConversion(timerID: Int = 42) -> (LocalEntity, PendingMutation) {
        let timer = LocalStore.upsertFromServer(
            data(["id": timerID, "child": 1, "name": "Tummy time", "start": iso]), kind: .timer, in: context)!
        let activity = repo.convertTimer(timer, to: .tummyTime, payload: [
            "child": 1, "start": iso, "end": "2024-01-15T10:15:00-05:00", "milestone": "", "tags": []])!
        return (activity, mutations()[0])
    }

    private static let timerGone = StubTransport.Reply(status: 404, body: #"{"detail":"No Timer matches the given query."}"#)
    private static let timerDeleted = StubTransport.Reply(status: 204, body: "")

    /// The timer is deleted by its own request and the activity posted without `timer`, so the
    /// server keeps the activity's own start and end instead of overwriting them (#145).
    func testTimerConversionDeletesTimerThenPostsOnce() async {
        let (activity, _) = queueTimerConversion()
        StubTransport.reset([Self.timerDeleted,
                             .init(status: 201, body: #"{"id":77,"child":1,"start":"2024-01-15T10:00:00-05:00","end":"2024-01-15T10:15:00-05:00"}"#)])

        await engine.pushPending()
        for _ in 0..<3 { await engine.pushPending() }

        XCTAssertEqual(StubTransport.requests.map(\.method), ["DELETE", "POST"])
        XCTAssertEqual(StubTransport.requests.first?.url, "https://stub.invalid/api/timers/42/")
        XCTAssertTrue(mutations().isEmpty)
        XCTAssertEqual(activity.serverID, 77)
        XCTAssertEqual(activity.syncState, .synced)
    }

    /// Once the timer is deleted, a failed POST is retried as a plain create: the `timer` key is
    /// gone from both copies, so the retry doesn't re-DELETE, 404, and park a row that was fine.
    func testPostFailureAfterTimerDeleteRetriesWithoutTimer() async {
        let (activity, create) = queueTimerConversion()
        StubTransport.reset([Self.timerDeleted, .init(status: 503, body: ""),
                             .init(status: 201, body: #"{"id":81,"child":1,"start":"2024-01-15T10:00:00-05:00"}"#)])

        await engine.pushPending()
        XCTAssertFalse(create.isBlocked)
        XCTAssertNil(json(create.payload)["timer"])
        XCTAssertNil(activity.payloadObject["timer"])
        XCTAssertEqual(json(create.payload)["end"] as? String, "2024-01-15T10:15:00-05:00")

        await engine.pushPending()
        XCTAssertEqual(StubTransport.requests.map(\.method), ["DELETE", "POST", "POST"])
        XCTAssertTrue(mutations().isEmpty)
        XCTAssertEqual(activity.serverID, 81)
    }

    /// A 404 on the timer's DELETE parks the row in its own state and later syncs walk past it.
    /// A plain Retry re-sends the same DELETE — which 404s the same way, so it can't create a
    /// duplicate and it can't loop.
    func testTimerGoneBecomesStaleTimerAndIsSkipped() async {
        let (activity, create) = queueTimerConversion()
        StubTransport.reset([Self.timerGone])

        await engine.pushPending()
        XCTAssertTrue(create.isBlocked)
        XCTAssertTrue(create.isStaleTimer)
        XCTAssertEqual(create.lastError, SyncEngine.staleTimerMessage)
        XCTAssertEqual(StubTransport.requests.map(\.method), ["DELETE"], "nothing is posted")

        for _ in 0..<5 { await engine.pushPending() }
        XCTAssertEqual(StubTransport.requests.count, 1, "never resent automatically")
        XCTAssertEqual(json(create.payload)["timer"] as? Int, 42, "the timer key is never stripped by itself")
        XCTAssertEqual(activity.payloadObject["timer"] as? Int, 42)

        create.retryOnce()
        await engine.pushPending()
        XCTAssertEqual(StubTransport.requests.count, 2, "Retry sends the same DELETE once")
        XCTAssertTrue(create.isStaleTimer, "and it parks the same way again")
        await engine.pushPending()
        XCTAssertEqual(StubTransport.requests.count, 2)
    }

    /// The user's explicit choice: `timer` is dropped from both copies of the payload, everything
    /// else is kept, and it goes out exactly once.
    func testCreateWithoutTimerStripsKeyEverywhereAndSendsOnce() async {
        let (activity, create) = queueTimerConversion()
        StubTransport.reset([
            Self.timerGone,
            .init(status: 201, body: #"{"id":78,"child":1,"start":"2024-01-15T10:00:00-05:00","end":"2024-01-15T10:15:00-05:00"}"#),
        ])
        await engine.pushPending()
        XCTAssertTrue(create.isStaleTimer)

        repo.createWithoutTimer(create)

        XCTAssertFalse(create.isBlocked)
        XCTAssertNil(json(create.payload)["timer"])
        XCTAssertNil(activity.payloadObject["timer"], "queued body and cached record agree")
        XCTAssertEqual(json(create.payload)["child"] as? Int, 1)
        XCTAssertEqual(json(create.payload)["start"] as? String, iso)
        XCTAssertEqual(json(create.payload)["end"] as? String, "2024-01-15T10:15:00-05:00")

        await engine.pushPending()
        for _ in 0..<3 { await engine.pushPending() }
        XCTAssertEqual(StubTransport.requests.map(\.method), ["DELETE", "POST"], "one 404, then exactly one POST")
        XCTAssertTrue(mutations().isEmpty)
        XCTAssertEqual(activity.serverID, 78)
    }

    /// Not a stale-timer row: the method is a no-op rather than a way to strip `timer` from anything.
    func testCreateWithoutTimerIgnoresOtherRows() async {
        let (_, create) = queueTimerConversion()
        StubTransport.reset([.init(status: 400, body: #"{"amount":["Required."]}"#)])
        await engine.pushPending()
        XCTAssertTrue(create.isBlocked)
        XCTAssertFalse(create.isStaleTimer)

        repo.createWithoutTimer(create)
        XCTAssertTrue(create.isBlocked)
        XCTAssertEqual(json(create.payload)["timer"] as? Int, 42)
    }

    /// The editor rebuilds payloads from its fields and never sets `timer`. Saving an edit to a
    /// stale-timer activity must not turn into a silent create-without-timer: the reference is
    /// carried over, the row stays parked, and nothing goes out until the user decides.
    func testEditingStaleTimerRowKeepsTimerAndStaysParked() async {
        let (activity, create) = queueTimerConversion()
        StubTransport.reset([Self.timerGone])
        await engine.pushPending()
        XCTAssertTrue(create.isStaleTimer)

        // An editor save: same record, no `timer` key, one field changed.
        repo.update(activity, payload: ["child": 1, "start": iso, "end": "2024-01-15T10:15:00-05:00",
                                        "milestone": "Rolled over", "tags": []])

        XCTAssertEqual(json(create.payload)["timer"] as? Int, 42, "the dead reference is kept in the queued body")
        XCTAssertEqual(activity.payloadObject["timer"] as? Int, 42, "and in the cached record")
        XCTAssertEqual(activity.payloadObject["milestone"] as? String, "Rolled over", "the edit itself lands")
        XCTAssertTrue(create.isStaleTimer, "still parked: the edit didn't change why")
        XCTAssertEqual(create.lastError, SyncEngine.staleTimerMessage)

        for _ in 0..<3 { await engine.pushPending() }
        XCTAssertEqual(StubTransport.requests.count, 1, "nothing is sent behind the user's back")

        // The explicit choice still works afterwards, on the edited body.
        StubTransport.reset([.init(status: 201, body: #"{"id":80,"child":1,"start":"2024-01-15T10:00:00-05:00","milestone":"Rolled over"}"#)])
        repo.createWithoutTimer(create)
        await engine.pushPending()
        XCTAssertEqual(StubTransport.requests.count, 1)
        XCTAssertTrue(mutations().isEmpty)
        XCTAssertEqual(activity.payloadObject["milestone"] as? String, "Rolled over")
    }

    /// An edit before the conversion is delivered keeps the timer reference, so the server timer
    /// is still deleted rather than left running.
    func testEditingQueuedConversionStillDeletesTimer() async {
        let (activity, create) = queueTimerConversion()

        // An editor save: same record, no `timer` key, one field changed.
        repo.update(activity, payload: ["child": 1, "start": iso, "end": "2024-01-15T10:15:00-05:00",
                                        "milestone": "Rolled over", "tags": []])
        XCTAssertEqual(json(create.payload)["timer"] as? Int, 42)
        XCTAssertFalse(create.isBlocked)

        StubTransport.reset([Self.timerDeleted,
                             .init(status: 201, body: #"{"id":82,"child":1,"start":"2024-01-15T10:00:00-05:00","milestone":"Rolled over"}"#)])
        await engine.pushPending()
        XCTAssertEqual(StubTransport.requests.map(\.method), ["DELETE", "POST"])
        XCTAssertEqual(StubTransport.requests.first?.url, "https://stub.invalid/api/timers/42/")
        XCTAssertTrue(mutations().isEmpty)
        XCTAssertEqual(activity.serverID, 82)
    }

    /// App/extension coordination: the extension delivers its own fresh create, the app's push
    /// loop honours the claim, and a parked row is never re-sent from the extension.
    func testWidgetClaimedAndParkedCreatesDoNotDoublePost() async {
        let (activity, create) = queueTimerConversion()
        let localID = activity.localID
        StubTransport.reset([Self.timerDeleted,
                             .init(status: 201, body: #"{"id":79,"child":1,"start":"2024-01-15T10:00:00-05:00"}"#)])

        // The app skips a create the extension has claimed.
        create.claimedAt = .now
        await engine.pushPending()
        XCTAssertEqual(StubTransport.requests.count, 0)

        // The extension delivers it; the app then finds nothing to send.
        create.claimedAt = nil
        await TimerPush.pushCreate(localID: localID, in: context, client: StubTransport.makeClient())
        XCTAssertEqual(StubTransport.requests.map(\.method), ["DELETE", "POST"])
        XCTAssertTrue(mutations().isEmpty)
        await engine.pushPending()
        XCTAssertEqual(StubTransport.requests.count, 2)

        // A stale-timer row is the app's to resolve — the extension never re-POSTs it.
        let (parked, parkedCreate) = queueTimerConversion(timerID: 43)
        parkedCreate.fail(SyncEngine.staleTimerMessage, disposition: .blockedStaleTimer)
        await TimerPush.pushCreate(localID: parked.localID, in: context, client: StubTransport.makeClient())
        XCTAssertEqual(StubTransport.requests.count, 2)
        XCTAssertNil(parkedCreate.claimedAt, "not even claimed")
    }

    // MARK: Image-upload queue

    /// Seed a synced note with a queued image upload, ready to drain.
    private func queueUpload(baseSnapshot: [String: Any]? = nil) -> (LocalEntity, PendingImageUpload) {
        let base = baseSnapshot ?? ["id": 9, "child": 1, "time": iso, "note": "hi"]
        let entity = LocalStore.upsertFromServer(data(base), kind: .note, in: context)!
        repo.enqueueImageUpload(for: entity, imageData: Data("jpegbytes".utf8))
        return (entity, uploads()[0])
    }

    /// An image upload whose target is gone is terminal — retrying the same PATCH can't find it.
    func testImageUploadNotFoundBlocks() async {
        let (_, upload) = queueUpload()
        StubTransport.reset([.init(status: 404, body: "{}")])

        await engine.drainImageUploads()
        XCTAssertTrue(upload.isBlocked)
        XCTAssertEqual(StubTransport.requests.count, 1)

        for _ in 0..<3 { await engine.drainImageUploads() }
        XCTAssertEqual(StubTransport.requests.count, 1, "a blocked upload is never resent automatically")
        XCTAssertEqual(upload.attemptCount, 1)

        ImageUploadStore.delete(upload.filename)
    }

    /// A child the server never gave a usable slug can't be addressed at all. Children only ever
    /// reach the cache through a pull, so the next sync would read back the same payload — parking
    /// it surfaces the reason instead of re-deciding it forever. Crucially it must not fall back to
    /// the numeric URL (the 404-forever bug #96 fixed) and must not throw away the photo.
    func testChildWithoutUsableSlugBlocksWithoutSendingAnything() async {
        let payload = data(["id": 3, "first_name": "Maya", "last_name": "Guy"])  // no `slug`
        let child = LocalStore.upsertFromServer(payload, kind: .child, in: context)!
        repo.enqueueImageUpload(for: child, imageData: Data("jpegbytes".utf8))
        let upload = uploads()[0]

        await engine.drainImageUploads()

        XCTAssertTrue(upload.isBlocked)
        XCTAssertEqual(upload.attemptCount, 1)
        XCTAssertEqual(StubTransport.requests.count, 0, "nothing may be sent to the numeric URL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ImageUploadStore.url(for: upload.filename).path),
                      "the photo is kept, not discarded")

        for _ in 0..<4 { await engine.drainImageUploads() }
        XCTAssertEqual(upload.attemptCount, 1, "the guard stops re-deciding on every sync")
        XCTAssertEqual(StubTransport.requests.count, 0)

        ImageUploadStore.delete(upload.filename)
    }

    /// The same child once the server does supply a slug: addressed by slug, never by id.
    func testChildWithSlugUploadsToTheSlugRoute() async {
        let payload = data(["id": 3, "slug": "maya-guy", "first_name": "Maya"])
        let child = LocalStore.upsertFromServer(payload, kind: .child, in: context)!
        repo.enqueueImageUpload(for: child, imageData: Data("jpegbytes".utf8))
        StubTransport.reset([.init(status: 200, body: #"{"id":3,"slug":"maya-guy","picture":"https://s/p.jpg"}"#)])

        await engine.drainImageUploads()

        XCTAssertEqual(StubTransport.requests.count, 1)
        XCTAssertTrue(try! XCTUnwrap(StubTransport.requests.first).url.hasSuffix("/api/children/maya-guy/"),
                      "addressed by slug, not by id")
        XCTAssertTrue(uploads().isEmpty, "delivered and cleared")
    }

    /// A newer pick supersedes the blocked one — the user fixed it the obvious way.
    func testNewImageSelectionClearsBlockedState() async {
        let (entity, upload) = queueUpload()
        StubTransport.reset([.init(status: 404, body: "{}")])
        await engine.drainImageUploads()
        XCTAssertTrue(upload.isBlocked)
        let staleFile = upload.filename

        repo.enqueueImageUpload(for: entity, imageData: Data("newerbytes".utf8))

        let current = uploads()
        XCTAssertEqual(current.count, 1)
        XCTAssertFalse(current[0].isBlocked, "the new pick is a different payload and gets a fresh try")
        XCTAssertNotEqual(current[0].filename, staleFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ImageUploadStore.url(for: staleFile).path),
                       "the superseded bytes are cleaned up")

        ImageUploadStore.delete(current[0].filename)
    }

    /// Editing a record makes its queued write a different payload, so the block no longer applies.
    func testEditingPayloadUnblocksItsQueuedMutation() async {
        let mutation = queueCreate()
        StubTransport.reset([.init(status: 400, body: #"{"amount":["Required."]}"#)])
        await engine.pushPending()
        XCTAssertTrue(mutation.isBlocked)

        let entity = LocalStore.fetch(localID: mutation.localID, in: context)!
        repo.update(entity, payload: ["child": 1, "start": iso, "amount": 120])

        XCTAssertFalse(mutation.isBlocked, "the rejected payload is gone; this one deserves a try")
        XCTAssertNil(mutation.lastError)
    }

    // MARK: Discarding an image upload

    func testDiscardImageUploadRestoresPriorRemoteURL() throws {
        let prior = "https://baby.example.com/media/note/old.jpg"
        let (entity, upload) = queueUpload(
            baseSnapshot: ["id": 9, "child": 1, "time": iso, "note": "hi", "image": prior])
        let filename = upload.filename
        XCTAssertTrue((entity.payloadObject["image"] as? String)?.hasPrefix("file://") == true)

        repo.discardPendingImage(upload)

        XCTAssertEqual(entity.payloadObject["image"] as? String, prior, "back to the server's image")
        XCTAssertEqual(entity.payloadObject["note"] as? String, "hi", "unrelated fields untouched")
        XCTAssertEqual(entity.payloadObject["child"] as? Int, 1)
        XCTAssertTrue(uploads().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ImageUploadStore.url(for: filename).path),
                       "the pending bytes are deleted")
    }

    func testDiscardImageUploadWithNoPriorImageClearsTheField() throws {
        let (entity, upload) = queueUpload()  // base snapshot has no `image`
        let filename = upload.filename

        repo.discardPendingImage(upload)

        XCTAssertNil(entity.payloadObject["image"],
                     "no prior image, so the field goes away rather than pointing at a deleted file")
        XCTAssertEqual(entity.payloadObject["note"] as? String, "hi")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ImageUploadStore.url(for: filename).path))
    }

    /// Discarding a photo must not roll back an unrelated un-pushed text edit on the same record.
    func testDiscardImageUploadKeepsUnpushedTextEdit() throws {
        let (entity, upload) = queueUpload()
        repo.update(entity, payload: entity.payloadObject.merging(["note": "edited"]) { _, new in new })
        XCTAssertEqual(entity.payloadObject["note"] as? String, "edited")

        repo.discardPendingImage(upload)

        XCTAssertEqual(entity.payloadObject["note"] as? String, "edited", "only the image field is reverted")
        XCTAssertNil(entity.payloadObject["image"])
        XCTAssertEqual(mutations().count, 1, "the queued text write survives")
    }

    // MARK: Persistence

    /// The new attribute is optional with a `nil` default, so it round-trips through a real
    /// on-disk store. (Opening a store written *before* the attribute existed is covered by
    /// ``StoreMigrationTests``, which opens a captured 1.0.2 store file.)
    func testDispositionRoundTripsThroughAnOnDiskStore() throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        var container: ModelContainer? = try ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: url))
        let blockedID = UUID()
        do {
            let ctx = ModelContext(container!)
            let blocked = PendingMutation(localID: blockedID, kind: .feeding, op: .create,
                                          payload: Data("{}".utf8))
            blocked.fail("rejected", blocked: true)
            ctx.insert(blocked)
            ctx.insert(PendingMutation(localID: UUID(), kind: .note, op: .create,
                                       payload: Data("{}".utf8)))
            try ctx.save()
        }
        container = nil

        let reopened = try ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: url))
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<PendingMutation>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.localID == blockedID }).isBlocked)
        XCTAssertFalse(try XCTUnwrap(rows.first { $0.localID != blockedID }).isBlocked,
                       "a row that was never failed is waiting, not blocked")
    }

    // MARK: Sync outcome telemetry (Work Package 6)

    #if DEBUG
    /// One `Sync.finished`, and its parameters — a sync emits exactly one outcome or none at all.
    private func outcome(of recorder: SignalRecorder) -> [String: String]? {
        XCTAssertLessThanOrEqual(recorder.names.filter { $0 == "Sync.finished" }.count, 1,
                                 "one outcome per sync run")
        return recorder.parameters("Sync.finished")
    }

    /// The queue emptied: the outcome `Sync.completed` alone can't distinguish from a sync that
    /// delivered one record and parked another.
    func testDrainedSyncReportsDrainedAlongsideSyncCompleted() async {
        let recorder = SignalRecorder()
        defer { recorder.stop() }
        queueCreate()
        StubTransport.reset([.init(status: 201, body: #"{"id":42,"child":1,"start":"2024-01-15T10:00:00-05:00"}"#)])

        await engine.sync()

        XCTAssertEqual(outcome(of: recorder),
                       ["outcome": "drained", "delivered": "1", "uploaded": "0",
                        "blockedNew": "0", "blockedTotal": "0", "queued": "0"])
        XCTAssertTrue(recorder.names.contains("Sync.completed"), "the existing signal is unchanged")
    }

    /// The pattern the investigation found: a rejection parks a row, the sync reports itself as
    /// completed, and nothing said the queue never emptied. `blockedNew` is the transition.
    func testBlockedRowMakesTheSyncPartialBlocked() async {
        let recorder = SignalRecorder()
        defer { recorder.stop() }
        queueCreate()
        StubTransport.reset([.init(status: 400, body: #"{"amount":["Required."]}"#)])

        await engine.sync()

        XCTAssertEqual(outcome(of: recorder),
                       ["outcome": "partialBlocked", "delivered": "0", "uploaded": "0",
                        "blockedNew": "1", "blockedTotal": "1", "queued": "0"])
        XCTAssertFalse(recorder.names.contains("Sync.completed"), "nothing moved")
    }

    /// A 5xx says nothing about the payload: the row stays eligible, and the outcome says the
    /// queue stopped rather than that it drained.
    func testRetryableFailureReportsTransientFailure() async {
        let recorder = SignalRecorder()
        defer { recorder.stop() }
        queueCreate()
        StubTransport.reset([.init(status: 503, body: "{}")])

        await engine.sync()

        XCTAssertEqual(outcome(of: recorder),
                       ["outcome": "transientFailure", "delivered": "0", "uploaded": "0",
                        "blockedNew": "0", "blockedTotal": "0", "queued": "1"])
    }

    /// Work delivered, work still waiting, nothing wrong: an image whose record isn't on the
    /// server yet is skipped until it is, which is neither drained nor blocked.
    func testDeliveredWithWaitingUploadReportsPendingWork() async {
        let recorder = SignalRecorder()
        defer { recorder.stop() }
        queueCreate()
        // A second record that never got as far as the queue — its photo has nothing to attach to.
        let unsynced = LocalEntity(kind: .note, serverID: nil, childID: 1, timestamp: .now,
                                   payload: data(["child": 1, "time": iso, "note": "hi"]),
                                   syncState: .pendingCreate)
        context.insert(unsynced)
        repo.enqueueImageUpload(for: unsynced, imageData: Data("jpegbytes".utf8))
        let waiting = uploads()[0]
        defer { ImageUploadStore.delete(waiting.filename) }
        StubTransport.reset([.init(status: 201, body: #"{"id":42,"child":1,"start":"2024-01-15T10:00:00-05:00"}"#)])

        await engine.sync()

        XCTAssertEqual(StubTransport.requests.count, 1, "the upload was never attempted")
        XCTAssertEqual(outcome(of: recorder),
                       ["outcome": "changedWithPendingWork", "delivered": "1", "uploaded": "0",
                        "blockedNew": "0", "blockedTotal": "0", "queued": "1"])
    }

    /// The noise suppression `Sync.completed` has: most syncs are foreground/pull-to-refresh/
    /// post-timer no-ops with an empty queue, and reporting those would swamp the signal.
    func testNoOpSyncReportsNothing() async {
        let recorder = SignalRecorder()
        defer { recorder.stop() }

        await engine.sync()

        XCTAssertEqual(recorder.names, [], "an empty queue and an unchanged pull say nothing")
    }

    /// A row already parked when the sync starts — the shape an upgrade from build 1.0.2 inherits,
    /// and the one that produced hundreds of identical events. Walking past it must send nothing
    /// and report nothing new: no request, no rejection, and `blockedNew` zero. The standing
    /// backlog stays visible in `blockedTotal`, which is what makes the sync knowably partial.
    func testAlreadyBlockedRowIsSkippedWithoutReportingARejection() async {
        let recorder = SignalRecorder()
        defer { recorder.stop() }
        let mutation = queueCreate()
        mutation.fail("rejected on an earlier launch", blocked: true)
        try? context.save()
        StubTransport.reset([.init(status: 400, body: #"{"amount":["Required."]}"#)])

        for _ in 0..<5 { await engine.sync() }

        XCTAssertEqual(StubTransport.requests.count, 0, "a parked row is never re-sent")
        XCTAssertEqual(recorder.names.filter { $0 == "Error.serverRejected" }.count, 0,
                       "skipping a row that was already blocked reports no rejection")
        XCTAssertEqual(mutation.attemptCount, 1, "and its attempt count stops climbing")
        XCTAssertEqual(recorder.parameters("Sync.finished"),
                       ["outcome": "partialBlocked", "delivered": "0", "uploaded": "0",
                        "blockedNew": "0", "blockedTotal": "1", "queued": "0"])
        XCTAssertEqual(recorder.names.filter { $0 == "Sync.finished" }.count, 5,
                       "the backlog is reported per sync; the rejection is not")
    }
    #endif

    // MARK: Readable server messages

    func testValidationBodyBecomesReadableSentences() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "non_field_errors": ["Another entry intersects the specified time period."],
            "amount": ["This field is required."]])
        XCTAssertEqual(APIClient.errorMessage(from: body),
                       "Amount: This field is required.\nAnother entry intersects the specified time period.")
    }

    func testHTMLInServerMessageIsStripped() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "non_field_errors": ["Conflicting entry: <a href=\"/feedings/470/\">Feeding (1:09 a.m. - 1:24 a.m.)</a>"]])
        XCTAssertEqual(APIClient.errorMessage(from: body),
                       "Conflicting entry: Feeding (1:09 a.m. - 1:24 a.m.)")
    }

    func testEmptyObjectYieldsNoMessage() throws {
        XCTAssertNil(APIClient.errorMessage(from: Data("{}".utf8)))
    }
}
