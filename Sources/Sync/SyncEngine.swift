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

    /// How far back to pull high-volume event records, in days.
    var pullWindowDays = 60

    var isOnline: Bool { reachability.isOnline }

    /// Guards against overlapping syncs (foreground + reconnect + manual could collide).
    private var isSyncing = false

    init(session: AppSession, context: ModelContext) {
        self.session = session
        self.context = context
        self.syncActor = SyncActor(modelContainer: context.container)
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
            if Self.jsonEqual(current, mutation.baseSnapshot) {
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
            if Self.jsonEqual(current, mutation.baseSnapshot) {
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
        guard let entity,
              let obj = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else { return }
        entity.payload = response
        entity.baseSnapshot = response
        entity.serverID = obj["id"] as? Int
        entity.timestamp = entity.kind.timestamp(from: obj)
        entity.childID = entity.kind.childID(from: obj)
        entity.syncState = .synced
        entity.updatedAt = .now
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
}
