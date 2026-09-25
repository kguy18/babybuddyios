import Foundation
import SwiftData

/// Best-effort immediate delivery of a pending write to the server, callable from any
/// process — notably the widget/intents extension, which can't run the `@MainActor`
/// `SyncEngine`. Every widget timer action is a create, or a stopped timer's DELETE, and neither
/// needs `SyncEngine`'s GET-before-write conflict checks: a create can't conflict, and a timer the
/// user just stopped goes whatever changed on it. On any failure it leaves the mutation queued
/// for the app's next sync.
enum TimerPush {
    /// How long a claimed-but-undelivered write is skipped by the app's push loop, so the app
    /// and the extension don't both `POST` the same record. After this it's treated as a stale
    /// claim (e.g. the extension was killed mid-push) and delivered normally.
    static let claimWindow: TimeInterval = 30

    /// Deliver the pending create for `localID` now, if signed in. Best-effort and silent.
    ///
    /// A parked row (``QueueItem/isBlocked``) is never sent from here: the app owns that verdict
    /// and the user's recovery choice, and a stale-timer create in particular must go out at most
    /// once more, on the user's say-so. The extension only ever pushes what it just created.
    @MainActor
    static func pushCreate(localID: UUID, in context: ModelContext,
                           client: APIClient? = KeychainStore.load().map { APIClient(config: $0) }) async {
        guard let client else { return }
        let descriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.localID == localID && $0.opRaw == "create" })
        guard let mutation = try? context.fetch(descriptor).first, !mutation.isBlocked,
              let entity = LocalStore.fetch(localID: localID, in: context) else { return }

        mutation.claimedAt = .now // tell the app's push loop to skip this briefly
        try? context.save()

        do {
            let response = try await client.createRaw(path: mutation.kind.path, body: mutation.payload)
            reconcile(response, into: entity)
            context.delete(mutation)
            try? context.save()
        } catch {
            mutation.claimedAt = nil // release so the app retries on its next sync
            try? context.save()
        }
    }

    /// Deliver the queued DELETE that stops the timer `localID`, if signed in. Best-effort, like
    /// ``pushCreate``, and sent first: a 404 parks the create logged from the timer as a likely
    /// duplicate, so ``pushCreate`` then leaves it alone.
    @MainActor
    static func pushTimerDelete(localID: UUID, in context: ModelContext,
                                client: APIClient? = KeychainStore.load().map { APIClient(config: $0) }) async {
        guard let client else { return }
        let descriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.localID == localID && $0.opRaw == "delete" })
        guard let mutation = try? context.fetch(descriptor).first, !mutation.isBlocked,
              let serverID = mutation.serverID else { return }

        mutation.claimedAt = .now
        try? context.save()

        let repo = LocalRepository(context: context)
        do {
            try await client.deleteRaw(path: EntityKind.timer.path, id: serverID)
            repo.settleTimerDelete(mutation, alreadyGone: false)
        } catch APIError.notFound {
            repo.settleTimerDelete(mutation, alreadyGone: true)
        } catch {
            mutation.claimedAt = nil
        }
        try? context.save()
    }

    /// Apply an authoritative server response onto a cached entity after a create. Shared with
    /// `SyncEngine` so the reconcile rules live in one place.
    static func reconcile(_ response: Data, into entity: LocalEntity) {
        guard let obj = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else { return }
        entity.payload = response
        entity.baseSnapshot = response
        entity.serverID = obj["id"] as? Int
        entity.timestamp = entity.kind.timestamp(from: obj)
        entity.childID = entity.kind.childID(from: obj)
        entity.syncState = .synced
        entity.updatedAt = .now
    }
}
