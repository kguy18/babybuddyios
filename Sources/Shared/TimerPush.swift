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
    @MainActor
    static func pushCreate(localID: UUID, in context: ModelContext) async {
        guard let config = KeychainStore.load() else { return }
        let descriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.localID == localID && $0.opRaw == "create" })
        guard let mutation = try? context.fetch(descriptor).first,
              let entity = LocalStore.fetch(localID: localID, in: context) else { return }

        mutation.claimedAt = .now // tell the app's push loop to skip this briefly
        try? context.save()

        do {
            let response = try await APIClient(config: config)
                .createRaw(path: mutation.kind.path, body: mutation.payload)
            reconcile(response, into: entity)
            context.delete(mutation)
            try? context.save()
        } catch {
            mutation.claimedAt = nil // release so the app retries on its next sync
            try? context.save()
        }
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
