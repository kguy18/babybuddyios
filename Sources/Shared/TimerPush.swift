import Foundation
import SwiftData

/// Best-effort immediate delivery of a pending *create* to the server, callable from any
/// process — notably the widget/intents extension, which can't run the `@MainActor`
/// `SyncEngine`. Every widget timer action (start, and stop-as-log) is a create, and creates
/// can't conflict, so this needs none of `SyncEngine`'s GET-before-write conflict checks: it
/// `POST`s and reconciles. On any failure it leaves the mutation queued for the app's next sync.
enum TimerPush {
    /// How long a claimed-but-undelivered create is skipped by the app's push loop, so the app
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
            let response = try await sendCreate(mutation, client: client, context: context)
            reconcile(response, into: entity)
            context.delete(mutation)
            try? context.save()
        } catch {
            mutation.claimedAt = nil // release so the app retries on its next sync
            try? context.save()
        }
    }

    /// The timer a conversion was logged from is already gone from the server. Another device
    /// may have logged it, or our own earlier attempt deleted it and the response was lost. See
    /// ``QueueDisposition/blockedStaleTimer``.
    struct StaleTimer: Error {}

    /// `POST` a queued create and return the server's response.
    ///
    /// A timer conversion's body holds the timer's id under `timer`, but that key never goes out.
    /// Baby Buddy treats `timer` on a create as "use the timer's times": it overwrites `start`
    /// with the timer's start and `end` with the moment the request arrives, so an edited End, or
    /// a feed logged offline and synced hours later, would be saved wrong. Instead this deletes
    /// the timer, then posts the activity with its own `start` and `end`. A 404 on that delete
    /// throws ``StaleTimer``. Once the delete succeeds, `timer` is dropped and saved before the
    /// `POST`, so a `POST` that fails is retried as a plain create rather than hitting the 404.
    @MainActor
    static func sendCreate(_ mutation: PendingMutation, client: APIClient,
                           context: ModelContext) async throws -> Data {
        let body = try? JSONSerialization.jsonObject(with: mutation.payload) as? [String: Any]
        if let timerID = body?["timer"] as? Int {
            do {
                try await client.deleteRaw(path: EntityKind.timer.path, id: timerID)
            } catch APIError.notFound {
                throw StaleTimer()
            }
            LocalRepository(context: context).dropTimerReference(mutation)
            try? context.save()
        }
        return try await client.createRaw(path: mutation.kind.path, body: mutation.payload)
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
