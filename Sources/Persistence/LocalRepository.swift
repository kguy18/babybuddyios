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
    static var didLogActivity: ((LocalEntity) -> Void)?

    // MARK: Create

    /// Create a record locally and queue it for the server.
    ///
    /// `source` is which path is doing the creating; it rides onto `Activity.logged`. This method is
    /// the app's **only** emitter of that signal (``QuickLogIntent`` documents the same invariant),
    /// so the distinction can't be recovered downstream — it has to be threaded in from here. It
    /// defaults to ``Analytics/ActivitySource/editor``, the sheet-and-save path every other caller
    /// is a variation on.
    @discardableResult
    func create(kind: EntityKind, payload: [String: Any], timerActivity: EntityKind? = nil,
                source: Analytics.ActivitySource = .editor) -> LocalEntity? {
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
            Analytics.activityLogged(kind: kind.rawValue, source: source)
            Self.didLogActivity?(entity)
        }
        return entity
    }

    // MARK: Update

    func update(_ entity: LocalEntity, payload: [String: Any]) {
        var payload = payload
        let pending = pendingMutation(for: entity.localID)
        // An edit must not unpark a likely duplicate: that's what "Create without timer" exists to
        // gate. Keep the row parked, since the edit changes the record, not why it's blocked. The
        // editor never sets `timer`, so a row queued before #145 carries its dead reference over.
        let keepsStaleTimer = pending?.isStaleTimer == true
        if keepsStaleTimer, let timer = entity.payloadObject["timer"] { payload["timer"] = timer }

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        entity.payload = data
        entity.timestamp = entity.kind.timestamp(from: payload)
        entity.childID = entity.kind.childID(from: payload)
        entity.updatedAt = .now

        if let pending {
            // Coalesce: keep the original op (create stays create), refresh the body.
            pending.payload = data
            // A blocked row is terminal for the payload that was rejected, not for the record.
            // This is a different payload now, so it earns a fresh attempt — unless what was
            // rejected is the timer reference this edit had to keep.
            if !keepsStaleTimer { pending.retryOnce() }
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

    // MARK: Timer stop

    /// Stop a running timer at `time`. Its duration freezes here, and because a Baby Buddy timer
    /// has no end, stopping it on the server means deleting it: other devices drop it on their
    /// next sync. The record stays on this device as a stopped draft until it's logged
    /// (``convertTimer``), discarded (``discardStoppedTimer``) or resumed (``resumeTimer``).
    func stopTimer(_ timer: LocalEntity, at time: Date = .now) {
        guard timer.kind == .timer, timer.stoppedAt == nil else { return }
        timer.stoppedAt = time
        queueServerTimerDelete(timer)
        try? context.save()
    }

    /// Undo a Stop. A DELETE that hasn't gone out is cancelled; once it has, the server timer is
    /// gone, so a new one is created with the original start.
    func resumeTimer(_ timer: LocalEntity) {
        guard timer.stoppedAt != nil else { return }
        timer.stoppedAt = nil
        timer.stoppedTimerWasGone = nil
        if let pending = pendingMutation(for: timer.localID), pending.op == .delete {
            context.delete(pending)
            timer.syncState = .synced
            try? context.save()
            // A start corrected while it was stopped (``setTimerStart``) hasn't reached the server.
            if timer.payload != timer.baseSnapshot { update(timer, payload: timer.payloadObject) }
        } else if timer.serverID == nil {
            recreate(timer)
        }
        try? context.save()
    }

    /// Correct a timer's start (#72). A stopped draft's server copy is gone or going, so the edit
    /// stays local: the logged record carries the start (``LocalEntity/stoppedTimerPayload``), and
    /// ``resumeTimer`` sends it if the timer runs on instead. A running timer's edit is queued.
    func setTimerStart(_ timer: LocalEntity, to date: Date) {
        var payload = timer.payloadObject
        payload["start"] = APIDate.isoDateTime.string(from: date)
        guard timer.stoppedAt != nil else { return update(timer, payload: payload) }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        timer.payload = data
        timer.timestamp = date
        timer.updatedAt = .now
        try? context.save()
    }

    /// Log a timer as a completed activity (feeding/sleep/tummy-time/pumping) with the payload's
    /// explicit `start` and `end`. Stops it first if nothing has.
    ///
    /// The create never carries Baby Buddy's write-only `timer` field: with it the server replaces
    /// `start` and `end` with the timer's start and its own clock (#145). The timer's DELETE is
    /// its own queued request, ahead of the create. If that DELETE finds the timer already gone,
    /// another device got there first and the create is parked as a likely duplicate
    /// (``QueueDisposition/blockedStaleTimer``).
    @discardableResult
    func convertTimer(_ timer: LocalEntity, to kind: EntityKind, payload: [String: Any]) -> LocalEntity? {
        stopTimer(timer)
        let activity = create(kind: kind, payload: payload, source: .timerStop)
        if let activity {
            if timer.stoppedTimerWasGone == true {
                pendingMutation(for: activity.localID)?
                    .fail(Self.staleTimerMessage, disposition: .blockedStaleTimer)
            } else if let delete = pendingMutation(for: timer.localID), delete.op == .delete {
                // Links the create to the DELETE, which parks it on a 404 (``settleTimerDelete``).
                // A DELETE sends no body, so the payload is free to carry this.
                delete.payload = (try? JSONSerialization.data(
                    withJSONObject: ["loggedAs": activity.localID.uuidString])) ?? delete.payload
            }
        }
        context.delete(timer) // a queued DELETE stays: the timer is still on the server
        try? context.save()
        return activity
    }

    /// Discard a stopped timer without logging anything. Its DELETE, if still queued, stays.
    func discardStoppedTimer(_ timer: LocalEntity) {
        guard timer.stoppedAt != nil else { return delete(timer) }
        queueServerTimerDelete(timer)
        context.delete(timer)
        try? context.save()
    }

    /// A timer's DELETE has been answered: `alreadyGone` for a 404. Shared by
    /// `SyncEngine` and ``TimerPush`` so both settle it the same way. Deletes the mutation.
    func settleTimerDelete(_ mutation: PendingMutation, alreadyGone: Bool) {
        if let timer = LocalStore.fetch(localID: mutation.localID, in: context) {
            if timer.stoppedAt != nil {
                // A stopped draft: now local-only, which neither pull purges nor upserts onto.
                timer.serverID = nil
                timer.syncState = .synced
                if alreadyGone { timer.stoppedTimerWasGone = true }
            } else if timer.syncState == .pendingDelete {
                context.delete(timer)
            } else {
                // Resumed while this DELETE was already on its way.
                timer.serverID = nil
                recreate(timer)
            }
        }
        if alreadyGone,
           let body = try? JSONSerialization.jsonObject(with: mutation.payload) as? [String: Any],
           let logged = (body["loggedAs"] as? String).flatMap(UUID.init(uuidString:)),
           let create = pendingMutation(for: logged), create.op == .create {
            create.fail(Self.staleTimerMessage, disposition: .blockedStaleTimer)
        }
        context.delete(mutation)
    }

    nonisolated static let staleTimerMessage = "The timer this was logged from no longer exists on the server. It may already have been saved from another device — check before creating it again."

    /// Queue the DELETE for a timer's server copy, unless one is queued already. A timer the
    /// server never saw just loses its queued create.
    private func queueServerTimerDelete(_ timer: LocalEntity) {
        let pending = pendingMutation(for: timer.localID)
        if pending?.op == .delete { return }
        if let pending { context.delete(pending) }
        guard let serverID = timer.serverID else {
            timer.syncState = .synced
            return
        }
        timer.syncState = .pendingDelete
        context.insert(PendingMutation(
            localID: timer.localID, kind: .timer, op: .delete,
            payload: Data("{}".utf8), baseSnapshot: timer.baseSnapshot, serverID: serverID))
    }

    /// Queue a fresh create for a timer whose server copy is gone, keeping its start and name.
    private func recreate(_ timer: LocalEntity) {
        var p = timer.payloadObject
        for key in ["id", "url", "duration", "end"] { p.removeValue(forKey: key) }
        guard let data = try? JSONSerialization.data(withJSONObject: p) else { return }
        timer.payload = data
        timer.baseSnapshot = nil
        timer.syncState = .pendingCreate
        context.insert(PendingMutation(localID: timer.localID, kind: .timer, op: .create, payload: data))
    }

    /// The user's explicit answer to ``QueueDisposition/blockedStaleTimer``: drop any dead `timer`
    /// reference (only rows queued before #145 carry one) from both the queued body and the cached
    /// record, so they can't disagree about what was sent, keep child/start/end exactly as chosen,
    /// and give the row one more try. The
    /// duplicate warning lives in the UI — this method assumes it has been shown.
    func createWithoutTimer(_ mutation: PendingMutation) {
        guard mutation.isStaleTimer else { return }
        func stripped(_ data: Data) -> Data? {
            guard var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            obj.removeValue(forKey: "timer")
            return try? JSONSerialization.data(withJSONObject: obj)
        }
        guard let body = stripped(mutation.payload) else { return }
        mutation.payload = body
        if let entity = LocalStore.fetch(localID: mutation.localID, in: context),
           let cached = stripped(entity.payload) {
            entity.payload = cached
            entity.updatedAt = .now
        }
        mutation.retryOnce()
        try? context.save()
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
           let start = APIDate.parse(s), let end = APIDate.parse(e), end >= start {
            let duration = end.timeIntervalSince(start)
            p["start"] = iso(now.addingTimeInterval(-duration))
            p["end"] = iso(now)
        } else if p["start"] is String {
            p["start"] = iso(now)
        }
        if p["time"] is String { p["time"] = iso(now) }
        if p["date"] is String { p["date"] = APIDate.dateOnly.string(from: now) }

        return create(kind: entity.kind, payload: p, source: .repeat)
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

    /// Cancel a queued image upload, leaving the record itself alone.
    ///
    /// The pending bytes double as the record's local `file://` preview, so dropping the queue row
    /// alone would leave the entity pointing at a file that no longer exists. The image field is
    /// put back the way it was — the remote URL from the last synced snapshot, or absent when the
    /// record never had an image. Only that one field is touched: an unrelated un-pushed edit to
    /// the same record stays exactly as the user left it.
    func discardPendingImage(_ upload: PendingImageUpload) {
        if let entity = LocalStore.fetch(localID: upload.localID, in: context),
           let field = entity.kind.imageField {
            var payload = entity.payloadObject
            let base = entity.baseSnapshot
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            if let prior = base?[field], !(prior is NSNull) {
                payload[field] = prior
            } else {
                payload.removeValue(forKey: field)
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                entity.payload = data
                entity.updatedAt = .now
            }
        }
        ImageUploadStore.delete(upload.filename)
        context.delete(upload)
        try? context.save()
    }

    // MARK: Helpers

    private func pendingMutation(for localID: UUID) -> PendingMutation? {
        var d = FetchDescriptor<PendingMutation>(predicate: #Predicate { $0.localID == localID })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
