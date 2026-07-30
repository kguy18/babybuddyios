import Foundation
import SwiftData

/// Write API for the local cache. Every mutation updates the ``LocalEntity`` immediately
/// (so the UI reflects it at once) and enqueues a ``PendingMutation`` for the sync engine
/// to deliver. Mutations to the same record are coalesced so the queue never grows
/// unbounded while offline.
@MainActor
struct LocalRepository {
    let context: ModelContext

    /// Called once for each activity record logged on this device.
    ///
    /// A seam rather than a direct call because this file also compiles into the widget extension,
    /// which can't reach the app's own `UserDefaults` (and so can't touch the support-nudge counters
    /// that hang off this). ``BabyBuddyApp`` installs the hook at launch; in the extension it stays
    /// `nil` and the notification is simply dropped.
    static var didLogActivity: (() -> Void)?

    // MARK: Create

    @discardableResult
    func create(kind: EntityKind, payload: [String: Any], timerActivity: EntityKind? = nil) -> LocalEntity? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        let entity = LocalEntity(
            kind: kind, serverID: nil, childID: kind.childID(from: payload),
            timestamp: kind.timestamp(from: payload), payload: data, syncState: .pendingCreate,
            timerActivityRaw: timerActivity?.rawValue)
        context.insert(entity)
        context.insert(PendingMutation(localID: entity.localID, kind: kind, op: .create, payload: data))
        try? context.save()
        // A timer is a stopwatch, not a logged activity; children come from sync. Everything
        // else here is a completed record being logged (incl. timer conversions, which route
        // through this method). Timer start/stop are tracked separately at their call sites.
        if kind != .timer && kind != .child {
            Analytics.activityLogged(kind: kind.rawValue)
            Self.didLogActivity?()
        }
        return entity
    }

    // MARK: Update

    func update(_ entity: LocalEntity, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        entity.payload = data
        entity.timestamp = entity.kind.timestamp(from: payload)
        entity.childID = entity.kind.childID(from: payload)
        entity.updatedAt = .now

        if let pending = pendingMutation(for: entity.localID) {
            // Coalesce: keep the original op (create stays create), refresh the body.
            pending.payload = data
        } else {
            entity.syncState = .pendingUpdate
            context.insert(PendingMutation(
                localID: entity.localID, kind: entity.kind, op: .update,
                payload: data, baseSnapshot: entity.baseSnapshot, serverID: entity.serverID))
        }
        try? context.save()
    }

    // MARK: Delete

    func delete(_ entity: LocalEntity) {
        let existingPending = pendingMutation(for: entity.localID)

        // Never synced to the server: drop it (and any queued create) entirely.
        if entity.serverID == nil {
            if let existingPending { context.delete(existingPending) }
            context.delete(entity)
            try? context.save()
            return
        }

        if let existingPending { context.delete(existingPending) }
        entity.syncState = .pendingDelete
        context.insert(PendingMutation(
            localID: entity.localID, kind: entity.kind, op: .delete,
            payload: Data("{}".utf8), baseSnapshot: entity.baseSnapshot, serverID: entity.serverID))
        try? context.save()
    }

    // MARK: Timer conversion

    /// Remove a record from the cache *without* enqueueing a server delete. Drops any queued
    /// mutation for it too. Used when the server disposes of the record as a side effect of
    /// another write (e.g. converting a timer into an activity deletes the timer server-side),
    /// so a separate DELETE would be redundant and could race the conversion.
    func removeLocally(_ entity: LocalEntity) {
        if let pending = pendingMutation(for: entity.localID) { context.delete(pending) }
        context.delete(entity)
        try? context.save()
    }

    /// Convert a running timer into a completed activity (feeding/sleep/tummy-time/pumping).
    ///
    /// The activity is created locally with the supplied payload (typically `start =
    /// timer.start`, `end = now`). For a **synced** timer the payload carries the write-only
    /// `timer` id so a single POST makes the server create the activity *and* delete the
    /// timer; for an **unsynced** timer no server timer exists yet, so we post a plain
    /// activity and just drop the timer's queued create. Either way the local timer is
    /// removed without enqueueing a delete.
    @discardableResult
    func convertTimer(_ timer: LocalEntity, to kind: EntityKind, payload: [String: Any]) -> LocalEntity? {
        var body = payload
        if let serverID = timer.serverID { body["timer"] = serverID }
        let activity = create(kind: kind, payload: body)
        removeLocally(timer)
        return activity
    }

    // MARK: Repeat

    /// Re-log an existing event as a fresh record stamped to `now`: copies the payload, drops
    /// the server-assigned/computed fields, and re-stamps its timestamps (preserving an
    /// activity's start→end duration). Routes through ``create`` — no special sync handling.
    @discardableResult
    func repeatEvent(_ entity: LocalEntity, now: Date = .now) -> LocalEntity? {
        var p = entity.payloadObject
        for key in ["id", "url", "duration"] { p.removeValue(forKey: key) }

        func iso(_ d: Date) -> String { APIDate.isoDateTime.string(from: d) }
        if let s = p["start"] as? String, let e = p["end"] as? String,
           let start = APIDate.parse(s), let end = APIDate.parse(e), end > start {
            let duration = end.timeIntervalSince(start)
            p["start"] = iso(now.addingTimeInterval(-duration))
            p["end"] = iso(now)
        } else if p["start"] is String {
            p["start"] = iso(now)
        }
        if p["time"] is String { p["time"] = iso(now) }
        if p["date"] is String { p["date"] = APIDate.dateOnly.string(from: now) }

        return create(kind: entity.kind, payload: p)
    }

    // MARK: Image uploads

    /// Attach a picked image to a record: persist the bytes, point the cached record's image field
    /// at that local `file://` (so it displays immediately), and enqueue a ``PendingImageUpload``
    /// to `PATCH` it to the server once the record has a `serverID`. Only notes (`image`) and
    /// children (`picture`) carry images; a call for any other kind is ignored.
    ///
    /// The `file://` preview lives only in the cached `payload` — it is never sent in a JSON
    /// create/update body (those omit the image field), so the queued text write stays clean and
    /// the image travels solely over the dedicated multipart path.
    func enqueueImageUpload(for entity: LocalEntity, imageData: Data,
                            ext: String = "jpg", mimeType: String = "image/jpeg") {
        guard let field = entity.kind.imageField,
              let filename = ImageUploadStore.write(imageData, ext: ext) else { return }

        var payload = entity.payloadObject
        payload[field] = ImageUploadStore.url(for: filename).absoluteString
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            entity.payload = data
            entity.updatedAt = .now
        }

        // Coalesce: a newer pick supersedes an earlier queued one for the same record.
        let localID = entity.localID
        let existing = (try? context.fetch(FetchDescriptor<PendingImageUpload>(
            predicate: #Predicate { $0.localID == localID }))) ?? []
        for old in existing { ImageUploadStore.delete(old.filename); context.delete(old) }

        context.insert(PendingImageUpload(
            localID: entity.localID, kind: entity.kind, filename: filename, mimeType: mimeType))
        try? context.save()
    }

    // MARK: Discard a queued change

    /// Cancel a queued write, reverting the cached record to the server's last-known state.
    /// This edits the *sync queue*, never the underlying record:
    /// - **create**: the record never reached the server, so drop it and its queued write.
    /// - **update**: restore the record to its base snapshot (the synced server version).
    /// - **delete**: un-hide the record (it still exists on the server) and mark it synced.
    func discardPending(_ mutation: PendingMutation) {
        let entity = LocalStore.fetch(localID: mutation.localID, in: context)
        switch mutation.op {
        case .create:
            if let entity { context.delete(entity) }
        case .update:
            if let entity {
                if let base = entity.baseSnapshot {
                    entity.payload = base
                    entity.timestamp = entity.kind.timestamp(from: entity.payloadObject)
                    entity.childID = entity.kind.childID(from: entity.payloadObject)
                }
                entity.syncState = .synced
                entity.updatedAt = .now
            }
        case .delete:
            entity?.syncState = .synced
        }
        context.delete(mutation)
        try? context.save()
    }

    // MARK: Helpers

    private func pendingMutation(for localID: UUID) -> PendingMutation? {
        var d = FetchDescriptor<PendingMutation>(predicate: #Predicate { $0.localID == localID })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
