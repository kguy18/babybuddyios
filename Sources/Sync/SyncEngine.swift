import Foundation
import SwiftData
import Observation
import WidgetKit

/// Coordinates pull (server → cache) and, from Phase 4, push (cache → server) sync.
/// Lives for the app's lifetime and is shared via the environment.
@MainActor
@Observable
final class SyncEngine {
    enum Status: Equatable { case idle, syncing, failed(String) }

    private(set) var status: Status = .idle
    /// Persisted to the App Group so the stamp survives relaunch and the widget can show it.
    private(set) var lastSyncDate: Date? = SharedDefaults.lastSyncDate {
        didSet { SharedDefaults.lastSyncDate = lastSyncDate }
    }

    private let session: AppSession
    private let context: ModelContext
    /// Background context owner for the heavy bulk pull.
    private let syncActor: SyncActor
    let reachability = Reachability()

    /// Default rolling-window depth, in days; also the initial history horizon.
    /// Kept lean so the first sync stays light — older data is fetched on demand via
    /// "Load older" and, once cached, remains visible and locally searchable.
    static let defaultPullWindowDays = 30

    /// How far back to pull high-volume event records, in days.
    var pullWindowDays = SyncEngine.defaultPullWindowDays

    /// How far back each "Load older" step reaches, in days.
    var historyChunkDays = 60

    /// Oldest date history has been pulled through. Starts at the rolling window's start and
    /// walks backward as the user loads older activity. In-memory (reset per launch): records
    /// already loaded persist in the cache and keep displaying, so a reset only means a repeat
    /// "load older" re-fetches an already-cached chunk — an idempotent upsert.
    private(set) var historyHorizon: Date

    /// True while a "load older" fetch is in flight (drives the timeline footer spinner).
    private(set) var isLoadingHistory = false

    /// Last "load older" failure, for inline display in the timeline footer. Cleared on retry.
    private(set) var historyError: String?

    var isOnline: Bool { reachability.isOnline }

    /// Guards against overlapping syncs (foreground + reconnect + manual could collide).
    private var isSyncing = false
    private var isCheckingTimers = false
    private var syncGeneration = 0

    /// Stands in for ``AppSession/client`` so the push/upload loops can be driven against a stub
    /// transport. `nil` in the app, where the session owns the client and its lifetime.
    private let clientOverride: APIClient?

    /// The client the queues deliver through.
    private var apiClient: APIClient? { clientOverride ?? session.client }

    init(session: AppSession, context: ModelContext, client: APIClient? = nil) {
        self.session = session
        self.context = context
        self.clientOverride = client
        self.syncActor = SyncActor(modelContainer: context.container)
        self.historyHorizon = Calendar.current.date(
            byAdding: .day, value: -SyncEngine.defaultPullWindowDays, to: .now) ?? .now
        reachability.onReconnect = { [weak self] in
            Task { await self?.sync() }
        }
    }

    /// Push queued local changes, then pull fresh server state. Reentrancy-guarded.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncGeneration += 1
        defer { isSyncing = false }
        let push = await pushPending()
        // Image uploads drain after the mutation queue so a just-created record already has its
        // serverID (a multipart PATCH needs it).
        let uploads = await drainImageUploads()
        let pulledChanges = await pullAll()
        // A dose or timer logged elsewhere reschedules its local notification, background syncs too.
        if pulledChanges {
            await LiveActivityManager().reconcile()
            WidgetCenter.shared.reloadAllTimelines()
        }
        let changed = push.delivered > 0 || uploads.delivered > 0 || pulledChanges
        // Only report a sync that actually did work — most syncs (foreground, pull-to-refresh,
        // after each timer action, background) are no-ops, which would otherwise be pure noise.
        if changed { Analytics.syncCompleted() }
        reportOutcome(push, uploads, changed: changed)
    }

    /// Read-only probe: ordinary ticks fetch only timers, without dirtying the cache or its
    /// full-sync freshness stamp. A full sync remains free to run while this request is in flight.
    func remoteTimersChanged() async throws -> Bool {
        try Task.checkCancellation()
        #if DEBUG
        if session.isDemo { return false }
        #endif
        guard !isSyncing, !isCheckingTimers, let client = apiClient else { return false }
        let before = try timerSnapshots()
        guard before.values.contains(where: { $0.serverID != nil && $0.state != .pendingDelete })
        else { return false }
        isCheckingTimers = true
        defer { isCheckingTimers = false }
        let generation = syncGeneration
        let config = session.config
        do {
            let records = try await client.listAllRaw(path: EntityKind.timer.path)
            try Task.checkCancellation()
            // A local stop/edit or a full sync supersedes this response, even if that sync has
            // already finished. Never let an old probe resurrect a just-consumed timer.
            guard !isSyncing, generation == syncGeneration, config == session.config,
                  before == (try timerSnapshots()) else { return false }
            var remote: [Int: Data] = [:]
            for record in records {
                guard let timer = try? APICoders.decoder.decode(TimerDTO.self, from: record),
                      let id = timer.id, remote[id] == nil else {
                    throw APIError.decoding("Invalid timer record")
                }
                remote[id] = record
            }
            let knownIDs = Set(before.values.compactMap(\.serverID))
            if remote.keys.contains(where: { !knownIDs.contains($0) }) { return true }
            return before.values.contains { local in
                guard local.state == .synced, let id = local.serverID else { return false }
                guard let payload = remote[id] else { return true }
                return !LocalStore.payloadsEquivalent(local.payload, payload)
            }
        } catch {
            try Task.checkCancellation() // URLSession cancellation is wrapped as APIError.offline.
            if config == session.config, let error = error as? APIError, error == .unauthorized {
                session.signOut(clearLocalData: false)
            }
            throw error
        }
    }

    private struct TimerSnapshot: Equatable {
        let serverID: Int?
        let state: SyncState
        let payload: Data
        let updatedAt: Date
    }

    private func timerSnapshots() throws -> [UUID: TimerSnapshot] {
        let timers = try context.fetch(FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.kindRaw == "timer" }))
        return Dictionary(uniqueKeysWithValues: timers.map {
            ($0.localID, TimerSnapshot(serverID: $0.serverID, state: $0.syncState,
                                      payload: $0.payload, updatedAt: $0.updatedAt))
        })
    }

    /// What one pass over a queue did. `Sync.completed` says only "something moved", which a
    /// permanently blocked row can coexist with forever; these are the facts that separate a
    /// drained sync from a partial one. Counts and flags only — never what was in the payload.
    struct QueueRun {
        /// Rows actually delivered to the server this pass.
        var delivered = 0
        /// Rows this pass parked (see ``QueueDisposition``) — the transition, not the backlog.
        var blockedNew = 0
        /// The pass stopped early on a retryable failure (offline / 5xx), so the rest of the queue
        /// was never attempted.
        var stoppedRetryable = false
    }

    /// Emit `Sync.finished` — one bounded outcome per sync that did work or found work waiting.
    ///
    /// Deliberately alongside `Sync.completed` rather than replacing it: that signal backs an
    /// existing dashboard, and its meaning ("something changed") is unchanged here.
    ///
    /// Same no-op suppression as `Sync.completed`: a sync that moved nothing and has nothing
    /// queued is silent, which is most of them. `transientFailure` covers only the push/upload
    /// queues stopping early — a failed *pull* reports itself through ``SyncActor`` with its own
    /// category, and has no queue state to describe.
    private func reportOutcome(_ push: QueueRun, _ uploads: QueueRun, changed: Bool) {
        let census = queueCensus()
        guard changed || census.queued > 0 || census.blocked > 0 else { return }
        let outcome: Analytics.SyncOutcome =
            if push.stoppedRetryable || uploads.stoppedRetryable { .transientFailure }
            else if census.blocked > 0 { .partialBlocked }
            else if census.queued > 0 { .changedWithPendingWork }
            else { .drained }
        Analytics.syncFinished(outcome: outcome,
                               delivered: push.delivered, uploaded: uploads.delivered,
                               blockedNew: push.blockedNew + uploads.blockedNew,
                               blockedTotal: census.blocked, queued: census.queued)
    }

    /// Both queues after this sync saved: rows still eligible for automatic delivery, and rows
    /// parked until the user retries them.
    private func queueCensus() -> (queued: Int, blocked: Int) {
        let parked = ((try? context.fetch(FetchDescriptor<PendingMutation>())) ?? []).map(\.isBlocked)
            + ((try? context.fetch(FetchDescriptor<PendingImageUpload>())) ?? []).map(\.isBlocked)
        let blocked = parked.filter { $0 }.count
        return (parked.count - blocked, blocked)
    }

    /// Deliver queued image uploads (child pictures / note images) as multipart `PATCH`es. Each
    /// runs only once its target record is fully synced (has a `serverID`, no pending text write),
    /// so the image PATCH can't clobber an un-pushed edit. Returns what the pass did, so `sync()`
    /// can describe its outcome.
    @discardableResult
    func drainImageUploads() async -> QueueRun {
        var run = QueueRun()
        #if DEBUG
        if session.isDemo { return run }
        #endif
        guard let client = apiClient else { return run }
        let queue = (try? context.fetch(
            FetchDescriptor<PendingImageUpload>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        uploads: for upload in queue {
            // Parked by a terminal rejection: still queued and visible in Pending Changes, but
            // not re-sent until the user explicitly retries it.
            if upload.isBlocked { continue }
            guard let entity = LocalStore.fetch(localID: upload.localID, in: context),
                  entity.serverID != nil, entity.syncState == .synced,
                  let field = entity.kind.imageField else {
                continue // target not ready (create not yet pushed, or has a pending edit)
            }
            guard let data = try? Data(contentsOf: ImageUploadStore.url(for: upload.filename)) else {
                context.delete(upload); continue // bytes gone — drop the orphan
            }
            // Children are addressed by slug, not by id. A cached child payload that has no usable
            // one can't be PATCHed at all: keep the upload (and its bytes) queued rather than
            // sending it to the numeric URL, which 404s and retries forever.
            //
            // Blocked rather than left waiting, because this isn't a gap that closes on its own:
            // children only ever enter the cache through a server pull, so a `.synced` child
            // without a usable slug is a server that didn't supply one, and the next pull returns
            // the same payload. Parking it puts the reason in Pending Changes with a Retry for the
            // case that does fix it — the server itself changing.
            guard let lookup = entity.detailLookup else {
                upload.fail("This child's record on the server is missing something the photo upload needs. Refresh, then tap Retry.",
                            blocked: true)
                run.blockedNew += 1
                continue
            }
            do {
                let response = try await client.uploadImage(
                    path: entity.kind.path, lookup: lookup, field: field,
                    filename: upload.filename, mimeType: upload.mimeType, data: data)
                TimerPush.reconcile(response, into: entity)
                ImageUploadStore.delete(upload.filename)
                context.delete(upload)
                run.delivered += 1
            } catch let error as APIError {
                // Reported here, once per real attempt. A row that blocks is skipped from now on,
                // so this fires on the transition rather than on every sync that walks past it.
                Analytics.report(error, context: "upload-\(entity.kind.rawValue)",
                                 attempt: upload.attemptCount)
                switch error.queueOutcome {
                case .signOut: session.signOut(clearLocalData: false); return run
                case .retryLater:
                    run.stoppedRetryable = true
                    break uploads // offline/5xx: retry the whole queue later
                case .blocked:
                    upload.fail(error.userMessage, blocked: true)
                    run.blockedNew += 1
                case .recordAndRetry: upload.fail(error.userMessage, blocked: false)
                }
            } catch {
                upload.fail(error.localizedDescription, blocked: false)
            }
        }
        try? context.save()
        return run
    }

    /// Drain the pending-mutation queue oldest-first. Conflict detection is layered on in
    /// Phase 5; for now updates/deletes are delivered directly.
    /// Returns what the pass did (so callers can tell a meaningful sync from a no-op one, and
    /// `sync()` can describe its outcome). Conflicts don't count as delivered.
    @discardableResult
    func pushPending() async -> QueueRun {
        var run = QueueRun()
        #if DEBUG
        if session.isDemo { return run }
        #endif
        guard let client = apiClient else { return run }
        let queue = (try? context.fetch(
            FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        mutations: for mutation in queue {
            // Parked by a terminal rejection. Skipped rather than aborting the loop, so one poison
            // record doesn't hold up every write queued behind it.
            if mutation.isBlocked { continue }
            // Skip a create the widget/intents extension is currently delivering, so we don't
            // double-POST it. A stale claim (extension killed mid-push) ages out and is retried.
            if let claimedAt = mutation.claimedAt,
               Date().timeIntervalSince(claimedAt) < TimerPush.claimWindow {
                continue
            }
            do {
                if try await deliver(mutation, client: client) { run.delivered += 1 }
            } catch let error as APIError {
                // Reported here, once per real attempt. A row that blocks is skipped from now on,
                // so this fires on the transition rather than on every sync that walks past it.
                Analytics.report(error, context: "push-\(mutation.op.rawValue)-\(mutation.kind.rawValue)",
                                 attempt: mutation.attemptCount)
                switch error.queueOutcome {
                case .signOut: session.signOut(clearLocalData: false); return run
                case .retryLater:
                    run.stoppedRetryable = true
                    break mutations // offline/5xx: stop, retry whole queue later
                case .blocked:
                    if Self.isStaleTimerRejection(mutation, error) {
                        mutation.fail(Self.staleTimerMessage, disposition: .blockedStaleTimer)
                    } else {
                        mutation.fail(error.userMessage, blocked: true)
                    }
                    run.blockedNew += 1
                case .recordAndRetry: mutation.fail(error.userMessage, blocked: false)
                }
            } catch {
                mutation.fail(error.localizedDescription, blocked: false)
            }
        }
        try? context.save()
        return run
    }

    /// A create the server refused on its write-only `timer` field and nothing else. Only that
    /// exact shape is ambiguous-but-recoverable (see ``QueueDisposition/blockedStaleTimer``); a
    /// body that also names another field (pumping's `amount` + `timer`) has a real validation
    /// problem too, so it stays plainly blocked with both reasons in `lastError` and no
    /// create-without-timer shortcut.
    static func isStaleTimerRejection(_ mutation: PendingMutation, _ error: APIError) -> Bool {
        guard mutation.op == .create, case .badRequest(_, _, let fields) = error else { return false }
        return fields == ["timer"]
    }

    nonisolated static let staleTimerMessage = "The timer this was logged from no longer exists on the server. It may already have been saved from another device — check before creating it again."

    /// Delivers one mutation. Returns `true` when it performed an actual server write (POST/
    /// PATCH/DELETE), `false` when it raised a conflict or only cleaned up locally.
    @discardableResult
    private func deliver(_ mutation: PendingMutation, client: APIClient) async throws -> Bool {
        let entity = LocalStore.fetch(localID: mutation.localID, in: context)
        switch mutation.op {
        case .create:
            // Creates can't conflict — the server assigns a fresh id.
            let response = try await client.createRaw(path: mutation.kind.path, body: mutation.payload)
            applyServerResponse(response, to: entity)
            context.delete(mutation)
            return true

        case .update:
            guard let serverID = mutation.serverID else { context.delete(mutation); return false }
            // Conflict check: has the server record changed since we based our edit on it?
            let current: Data
            do {
                current = try await client.getRaw(path: mutation.kind.path, id: serverID)
            } catch APIError.notFound {
                raiseConflict(mutation, entity: entity, serverPayload: Data("{}".utf8), serverDeleted: true)
                return false
            }
            if Self.unchangedSinceBase(current, mutation.baseSnapshot) {
                let response = try await client.patchRaw(
                    path: mutation.kind.path, id: serverID, body: mutation.payload)
                applyServerResponse(response, to: entity)
                context.delete(mutation)
                return true
            } else {
                raiseConflict(mutation, entity: entity, serverPayload: current, serverDeleted: false)
                return false
            }

        case .delete:
            guard let serverID = mutation.serverID else {
                if let entity { context.delete(entity) }
                context.delete(mutation); return false
            }
            let current: Data
            do {
                current = try await client.getRaw(path: mutation.kind.path, id: serverID)
            } catch APIError.notFound {
                if let entity { context.delete(entity) } // already gone — our delete is satisfied
                context.delete(mutation); return false
            }
            if Self.unchangedSinceBase(current, mutation.baseSnapshot) {
                try await client.deleteRaw(path: mutation.kind.path, id: serverID)
                if let entity { context.delete(entity) }
                context.delete(mutation)
                return true
            } else {
                // Server changed under a local delete — let the user decide.
                raiseConflict(mutation, entity: entity, serverPayload: current, serverDeleted: false)
                return false
            }
        }
    }

    /// The user's explicit "try this one again" on a blocked row. Nothing else un-blocks a row:
    /// automatic syncs walk past it forever, which is the whole point.
    func retry(_ item: some QueueItem) {
        item.retryOnce()
        try? context.save()
        Task { await sync() }
    }

    /// Record a conflict for user resolution and stop retrying this mutation.
    private func raiseConflict(_ mutation: PendingMutation, entity: LocalEntity?,
                               serverPayload: Data, serverDeleted: Bool) {
        let conflict = ConflictRecord(
            localID: mutation.localID, kind: mutation.kind, op: mutation.op,
            serverID: mutation.serverID, localPayload: mutation.payload,
            serverPayload: serverPayload, basePayload: mutation.baseSnapshot,
            serverDeleted: serverDeleted)
        context.insert(conflict)
        entity?.syncState = .conflicted
        Analytics.syncConflictRaised(kind: mutation.kind.rawValue, op: "\(mutation.op)")
        context.delete(mutation)
    }

    // MARK: Conflict resolution

    /// Keep the local version, overwriting the server.
    func resolveKeepMine(_ conflict: ConflictRecord) {
        let entity = LocalStore.fetch(localID: conflict.localID, in: context)
        clearMutations(for: conflict.localID)

        switch conflict.op {
        case .delete:
            entity?.syncState = .pendingDelete
            context.insert(PendingMutation(
                localID: conflict.localID, kind: conflict.kind, op: .delete,
                payload: Data("{}".utf8), baseSnapshot: conflict.serverPayload, serverID: conflict.serverID))
        case .update, .create:
            if conflict.serverDeleted {
                // The server record is gone — re-create it from the local version.
                entity?.serverID = nil
                applyLocal(conflict.localPayload, to: entity, base: nil, state: .pendingCreate)
                context.insert(PendingMutation(
                    localID: conflict.localID, kind: conflict.kind, op: .create,
                    payload: conflict.localPayload))
            } else {
                applyLocal(conflict.localPayload, to: entity, base: conflict.serverPayload, state: .pendingUpdate)
                context.insert(PendingMutation(
                    localID: conflict.localID, kind: conflict.kind, op: .update,
                    payload: conflict.localPayload, baseSnapshot: conflict.serverPayload,
                    serverID: conflict.serverID))
            }
        }
        context.delete(conflict)
        try? context.save()
        Analytics.syncConflictResolved(choice: .mine, kind: conflict.kind.rawValue)
        Task { await sync() }
    }

    /// Discard the local change and adopt the server version (no server write needed).
    func resolveKeepTheirs(_ conflict: ConflictRecord) {
        let entity = LocalStore.fetch(localID: conflict.localID, in: context)
        clearMutations(for: conflict.localID)
        if conflict.serverDeleted {
            if let entity { context.delete(entity) }
        } else {
            applyLocal(conflict.serverPayload, to: entity, base: conflict.serverPayload, state: .synced)
            entity?.serverID = conflict.serverID
        }
        context.delete(conflict)
        try? context.save()
        Analytics.syncConflictResolved(choice: .server, kind: conflict.kind.rawValue)
    }

    /// Keep a field-by-field merged payload, overwriting the server.
    func resolveMerge(_ conflict: ConflictRecord, merged: Data) {
        let entity = LocalStore.fetch(localID: conflict.localID, in: context)
        clearMutations(for: conflict.localID)
        applyLocal(merged, to: entity, base: conflict.serverPayload, state: .pendingUpdate)
        context.insert(PendingMutation(
            localID: conflict.localID, kind: conflict.kind, op: .update,
            payload: merged, baseSnapshot: conflict.serverPayload, serverID: conflict.serverID))
        context.delete(conflict)
        try? context.save()
        Analytics.syncConflictResolved(choice: .merge, kind: conflict.kind.rawValue)
        Task { await sync() }
    }

    private func applyLocal(_ payload: Data, to entity: LocalEntity?, base: Data?, state: SyncState) {
        guard let entity else { return }
        entity.payload = payload
        entity.baseSnapshot = base
        entity.timestamp = entity.kind.timestamp(from: entity.payloadObject)
        entity.childID = entity.kind.childID(from: entity.payloadObject)
        entity.syncState = state
        entity.updatedAt = .now
    }

    private func clearMutations(for localID: UUID) {
        let descriptor = FetchDescriptor<PendingMutation>(predicate: #Predicate { $0.localID == localID })
        for mutation in (try? context.fetch(descriptor)) ?? [] { context.delete(mutation) }
    }

    /// Server-computed, read-only fields that drift without any client edit and so must be
    /// excluded from conflict detection. A running timer's `duration` advances every second,
    /// so comparing it against a base snapshot would flag a false conflict on every push
    /// (e.g. stopping a timer). The client never writes these, so ignoring them can't mask a
    /// real edit.
    static let volatileFields: Set<String> = ["duration"]

    /// Conflict-detection equality: like ``jsonEqual`` but ignoring server-computed volatile
    /// fields, so an otherwise-unchanged record never looks "changed" just because time passed.
    static func unchangedSinceBase(_ current: Data?, _ base: Data?) -> Bool {
        jsonEqual(stripVolatile(current), stripVolatile(base))
    }

    private static func stripVolatile(_ data: Data?) -> Data? {
        guard let data,
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return data }
        for key in volatileFields { obj.removeValue(forKey: key) }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? data
    }

    /// Order-independent deep equality of two JSON object payloads.
    static func jsonEqual(_ a: Data?, _ b: Data?) -> Bool {
        guard let a, let b,
              let oa = try? JSONSerialization.jsonObject(with: a),
              let ob = try? JSONSerialization.jsonObject(with: b) else { return false }
        return NSDictionary(dictionary: oa as? [String: Any] ?? [:])
            .isEqual(to: ob as? [String: Any] ?? [:])
    }

    /// Reconcile a cached record with the authoritative server payload after a write.
    private func applyServerResponse(_ response: Data, to entity: LocalEntity?) {
        guard let entity else { return }
        TimerPush.reconcile(response, into: entity)
    }

    /// Pull fresh server state into the cache. The heavy parsing/inserting runs on a
    /// background context (``SyncActor``); the UI's `@Query`s pick up the merged changes.
    /// Returns whether the pull changed any cached data, so `sync()` can report only meaningful syncs.
    @discardableResult
    func pullAll() async -> Bool {
        #if DEBUG
        if session.isDemo {
            DemoData.seedIfNeeded(into: context)
            lastSyncDate = .now
            status = .idle
            return false
        }
        #endif
        guard let config = session.config else { return false }
        status = .syncing
        let outcome = await syncActor.pullAll(config: config, windowDays: pullWindowDays)
        if let error = outcome.error {
            if error == SyncActor.unauthorized { session.signOut(clearLocalData: false); return outcome.changed }
            // Already reported inside ``SyncActor`` with its category and the kind that failed;
            // here the message is only for the user.
            status = .failed(error)
            return outcome.changed // earlier kinds may already have committed a remote timer stop
        }
        lastSyncDate = .now
        status = .idle
        return outcome.changed
    }

    // MARK: History paging

    /// Whether older activity remains to be loaded (the horizon hasn't reached the birth floor).
    var hasMoreHistory: Bool { Self.hasMoreHistory(horizon: historyHorizon, floor: historyFloor) }

    /// The earliest date history can contain: the start-of-day of the earliest-born cached
    /// child (no activity predates birth). Falls back to a 5-year lookback when no child or
    /// `birth_date` is cached, so paging always terminates.
    private var historyFloor: Date {
        let descriptor = FetchDescriptor<LocalEntity>(predicate: #Predicate { $0.kindRaw == "child" })
        let births = ((try? context.fetch(descriptor)) ?? []).compactMap { child -> Date? in
            (child.payloadObject["birth_date"] as? String).flatMap(APIDate.parse)
        }
        guard let earliest = births.min() else {
            return Calendar.current.date(byAdding: .year, value: -5, to: .now) ?? .distantPast
        }
        return Calendar.current.startOfDay(for: earliest)
    }

    /// Fetch the next older chunk of history into the cache, extending the timeline backward.
    /// Reentrancy-guarded and a no-op once the horizon reaches the birth floor. The fetch only
    /// upserts (never reconciles deletions), so nothing already cached is dropped.
    func loadOlderHistory() async {
        guard !isLoadingHistory, hasMoreHistory,
              let chunk = Self.nextHistoryChunk(
                horizon: historyHorizon, chunkDays: historyChunkDays, floor: historyFloor)
        else { return }
        isLoadingHistory = true
        historyError = nil
        defer { isLoadingHistory = false }

        #if DEBUG
        if session.isDemo {
            DemoData.seedOlderBatch(from: chunk.start, to: chunk.end, into: context)
            historyHorizon = chunk.start
            return
        }
        #endif

        guard let config = session.config else { return }
        let error = await syncActor.pullOlderWindow(
            config: config, dateMin: chunk.start, dateMax: chunk.end)
        if let error {
            if error == SyncActor.unauthorized { session.signOut(clearLocalData: false); return }
            historyError = error
            return
        }
        // Advance only on success, so a failed load retries the same chunk.
        historyHorizon = chunk.start
    }

    /// The historic window the next "load older" step fetches: `[start, end]` where `end` is the
    /// current horizon and `start` steps back `chunkDays`, clamped at `floor`. `nil` once the
    /// horizon has reached the floor. Pure, for unit-testing the paging math.
    nonisolated static func nextHistoryChunk(horizon: Date, chunkDays: Int, floor: Date) -> (start: Date, end: Date)? {
        guard horizon > floor else { return nil }
        let stepped = Calendar.current.date(byAdding: .day, value: -chunkDays, to: horizon) ?? floor
        return (max(stepped, floor), horizon)
    }

    /// Whether the horizon can still walk back toward older history.
    nonisolated static func hasMoreHistory(horizon: Date, floor: Date) -> Bool { horizon > floor }
}
