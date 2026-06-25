import Foundation
import SwiftData
import Observation

/// Coordinates pull (server → cache) and, from Phase 4, push (cache → server) sync.
/// Lives for the app's lifetime and is shared via the environment.
@MainActor
@Observable
final class SyncEngine {
    enum Status: Equatable { case idle, syncing, failed(String) }

    private(set) var status: Status = .idle
    private(set) var lastSyncDate: Date?

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

    init(session: AppSession, context: ModelContext) {
        self.session = session
        self.context = context
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
        defer { isSyncing = false }
        await pushPending()
        await pullAll()
    }

    /// Drain the pending-mutation queue oldest-first. Conflict detection is layered on in
    /// Phase 5; for now updates/deletes are delivered directly.
    func pushPending() async {
        #if DEBUG
        if session.isDemo { return }
        #endif
        guard let client = session.client else { return }
        let queue = (try? context.fetch(
            FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for mutation in queue {
            // Skip a create the widget/intents extension is currently delivering, so we don't
            // double-POST it. A stale claim (extension killed mid-push) ages out and is retried.
            if let claimedAt = mutation.claimedAt,
               Date().timeIntervalSince(claimedAt) < TimerPush.claimWindow {
                continue
            }
            do {
                try await deliver(mutation, client: client)
            } catch let error as APIError {
                if case .unauthorized = error { session.signOut(); return }
                if error.isRetryable { break } // offline/5xx: stop, retry whole queue later
                mutation.attemptCount += 1
                mutation.lastError = error.userMessage
            } catch {
                mutation.attemptCount += 1
                mutation.lastError = error.localizedDescription
            }
        }
        try? context.save()
    }

    private func deliver(_ mutation: PendingMutation, client: APIClient) async throws {
        let entity = LocalStore.fetch(localID: mutation.localID, in: context)
        switch mutation.op {
        case .create:
            // Creates can't conflict — the server assigns a fresh id.
            let response = try await client.createRaw(path: mutation.kind.path, body: mutation.payload)
            applyServerResponse(response, to: entity)
            context.delete(mutation)

        case .update:
            guard let serverID = mutation.serverID else { context.delete(mutation); return }
            // Conflict check: has the server record changed since we based our edit on it?
            let current: Data
            do {
                current = try await client.getRaw(path: mutation.kind.path, id: serverID)
            } catch APIError.notFound {
                raiseConflict(mutation, entity: entity, serverPayload: Data("{}".utf8), serverDeleted: true)
                return
            }
            if Self.unchangedSinceBase(current, mutation.baseSnapshot) {
                let response = try await client.patchRaw(
                    path: mutation.kind.path, id: serverID, body: mutation.payload)
                applyServerResponse(response, to: entity)
                context.delete(mutation)
            } else {
                raiseConflict(mutation, entity: entity, serverPayload: current, serverDeleted: false)
            }

        case .delete:
            guard let serverID = mutation.serverID else {
                if let entity { context.delete(entity) }
                context.delete(mutation); return
            }
            let current: Data
            do {
                current = try await client.getRaw(path: mutation.kind.path, id: serverID)
            } catch APIError.notFound {
                if let entity { context.delete(entity) } // already gone — our delete is satisfied
                context.delete(mutation); return
            }
            if Self.unchangedSinceBase(current, mutation.baseSnapshot) {
                try await client.deleteRaw(path: mutation.kind.path, id: serverID)
                if let entity { context.delete(entity) }
                context.delete(mutation)
            } else {
                // Server changed under a local delete — let the user decide.
                raiseConflict(mutation, entity: entity, serverPayload: current, serverDeleted: false)
            }
        }
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
    func pullAll() async {
        #if DEBUG
        if session.isDemo {
            DemoData.seedIfNeeded(into: context)
            lastSyncDate = .now
            status = .idle
            return
        }
        #endif
        guard let config = session.config else { return }
        status = .syncing
        let error = await syncActor.pullAll(config: config, windowDays: pullWindowDays)
        if let error {
            if error == SyncActor.unauthorized { session.signOut(); return }
            status = .failed(error)
            return
        }
        lastSyncDate = .now
        status = .idle
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
            if error == SyncActor.unauthorized { session.signOut(); return }
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
