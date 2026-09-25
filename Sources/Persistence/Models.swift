import Foundation
import SwiftData

/// Sync status of a locally cached record.
enum SyncState: String, Codable {
    case synced          // matches the server
    case pendingCreate   // created locally, not yet POSTed
    case pendingUpdate   // edited locally, not yet PATCHed
    case pendingDelete   // deleted locally, not yet DELETEd on server
    case conflicted      // a sync attempt found a server-side change; awaiting user resolution
}

/// The kind of write a ``PendingMutation`` represents.
enum MutationOp: String, Codable {
    case create, update, delete
}

/// A cached Baby Buddy record. Stored as an opaque JSON `payload` keyed by ``EntityKind``
/// so all 14 record types share one model. `timestamp` and `childID` are denormalized out
/// of the payload at write time for fast querying/sorting.
@Model
final class LocalEntity {
    @Attribute(.unique) var localID: UUID
    var kindRaw: String
    var serverID: Int?
    var childID: Int?
    var timestamp: Date
    var payload: Data
    var syncStateRaw: String
    /// JSON of the server version this local edit was derived from (conflict detection).
    var baseSnapshot: Data?
    var updatedAt: Date
    /// For `.timer` records started for a specific activity: the convertible ``EntityKind``
    /// rawValue chosen at start, so Stop can auto-file the timer without asking which kind.
    /// Local-only and never sent to the server, so it survives sync (server timers are generic);
    /// `nil` for uncategorized timers and all non-timer records.
    var timerActivityRaw: String?
    /// For a `.timer` the user has tapped Stop on: when. Baby Buddy timers have no end, so the
    /// server copy is deleted at Stop and this record stays on this device as a stopped draft until
    /// it's logged, discarded or resumed. Local-only, like `timerActivityRaw`.
    var stoppedAt: Date?
    /// The stopped timer's DELETE found it already gone from the server: another device logged or
    /// discarded it first, so logging it here would likely be a duplicate.
    var stoppedTimerWasGone: Bool?

    init(localID: UUID = UUID(), kind: EntityKind, serverID: Int?, childID: Int?,
         timestamp: Date, payload: Data, syncState: SyncState,
         baseSnapshot: Data? = nil, updatedAt: Date = .now, timerActivityRaw: String? = nil) {
        self.localID = localID
        self.kindRaw = kind.rawValue
        self.serverID = serverID
        self.childID = childID
        self.timestamp = timestamp
        self.payload = payload
        self.syncStateRaw = syncState.rawValue
        self.baseSnapshot = baseSnapshot
        self.updatedAt = updatedAt
        self.timerActivityRaw = timerActivityRaw
    }

    var kind: EntityKind { EntityKind(rawValue: kindRaw) ?? .note }
    /// A timer that is counting: not stopped, not being deleted. What the Live Activity, the
    /// widgets and the forgotten-timer alerts show.
    var isRunningTimer: Bool { kind == .timer && stoppedAt == nil && syncState != .pendingDelete }

    /// The `child`/`start`/`end` of the activity a timer logs as: its start to its Stop, or to now
    /// if nothing has stopped it.
    func stoppedTimerPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "start": (payloadObject["start"] as? String) ?? APIDate.isoDateTime.string(from: timestamp),
            "end": APIDate.isoDateTime.string(from: stoppedAt ?? .now),
        ]
        if let childID { payload["child"] = childID }
        return payload
    }
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    /// Memoized ``payloadObject``, keyed by the `payload` bytes it was decoded from so a sync
    /// rewrite invalidates it. Every list row reads the payload several times per body pass;
    /// the Data equality check is far cheaper than re-parsing the JSON each time.
    @Transient private var payloadCache: (data: Data, object: [String: Any])? = nil
    /// Memoized ``startEndDates``, keyed the same way (ISO date parsing is as hot as decoding).
    @Transient private var datesCache: (data: Data, start: Date?, end: Date?)? = nil

    /// Decoded payload as a JSON dictionary.
    var payloadObject: [String: Any] {
        if let cached = payloadCache, cached.data == payload { return cached.object }
        let object = (try? JSONSerialization.jsonObject(with: payload) as? [String: Any]) ?? [:]
        payloadCache = (payload, object)
        return object
    }

    /// The identifier this record's detail route is keyed by. Baby Buddy routes children by their
    /// server-assigned `slug` (`lookup_field = "slug"`), every other kind by numeric id. `nil` when
    /// the record has no usable one yet — callers must not substitute the other form, which 404s.
    var detailLookup: String? {
        guard kind == .child else { return serverID.map { String($0) } }
        guard let slug = payloadObject["slug"] as? String, APIClient.isSafeLookup(slug) else { return nil }
        return slug
    }

    /// Parsed `start`/`end` payload dates (nil when absent or unparseable).
    var startEndDates: (start: Date?, end: Date?) {
        if let cached = datesCache, cached.data == payload { return (cached.start, cached.end) }
        let p = payloadObject
        let start = (p["start"] as? String).flatMap(APIDate.parse)
        let end = (p["end"] as? String).flatMap(APIDate.parse)
        datesCache = (payload, start, end)
        return (start, end)
    }
}

/// A Baby Buddy tag cached for offline autocomplete in the tag picker. Tags have no child
/// or timestamp, so they don't fit the generic ``LocalEntity`` envelope and live in their
/// own lightweight model. `name` is the natural key (Baby Buddy tag names are unique);
/// `colorHex` is the server-assigned `#RRGGBB` chip color. Refreshed on every sync.
@Model
final class CachedTag {
    @Attribute(.unique) var name: String
    var colorHex: String?
    var slug: String?
    var lastUsed: Date?

    init(name: String, colorHex: String? = nil, slug: String? = nil, lastUsed: Date? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.slug = slug
        self.lastUsed = lastUsed
    }
}

/// Why a queued item isn't currently eligible for automatic delivery.
///
/// Stored as an optional raw string so rows written before this existed migrate in as `nil` —
/// the waiting state — without a versioned schema. `nil` is deliberately the safe default: a
/// queue row is eligible unless something told us otherwise.
enum QueueDisposition: String, Codable {
    /// The server answered, and re-sending this exact payload cannot succeed (a validation
    /// rejection, a permission refusal, a response we can't parse). The row stays queued and
    /// visible in Pending Changes, but automatic syncs skip it until the user asks to retry.
    /// Without this, one poison record is re-sent on every foreground, pull-to-refresh, timer
    /// action, and background sync — hundreds of identical rejections for a single bad row.
    case blocked
    /// A *create* the server refused only on its write-only `timer` field: the timer it was
    /// logged from no longer exists there. That is ambiguous — another device may have stopped
    /// the timer, or our own POST may have succeeded (which deletes the timer) with the response
    /// lost. Re-sending is safe (the same rejection comes back); stripping `timer` and re-sending
    /// is not, because it can create a duplicate. So the row parks like ``blocked`` and the user
    /// gets an explicit "create without timer" alongside Retry and Discard.
    case blockedStaleTimer
}

/// The two queue models share a failure lifecycle: attempts, the last user-safe message, and
/// whether the row has been parked. Factored out so the mutation queue and the image-upload
/// queue can't drift into contradictory retry behavior.
protocol QueueItem: AnyObject {
    var dispositionRaw: String? { get set }
    var attemptCount: Int { get set }
    var lastError: String? { get set }
}

extension QueueItem {
    var disposition: QueueDisposition? {
        get { dispositionRaw.flatMap(QueueDisposition.init(rawValue:)) }
        set { dispositionRaw = newValue?.rawValue }
    }

    /// Whether automatic syncs should skip this row. Every disposition parks the row; they differ
    /// only in what recovery the UI offers.
    var isBlocked: Bool { disposition != nil }
    var isStaleTimer: Bool { disposition == .blockedStaleTimer }

    /// Record a failed delivery. `blocked` parks the row: still queued, still visible, but no
    /// longer sent automatically.
    func fail(_ message: String, blocked: Bool) {
        fail(message, disposition: blocked ? .blocked : nil)
    }

    /// Record a failed delivery under a specific disposition (`nil` leaves the row eligible).
    func fail(_ message: String, disposition: QueueDisposition?) {
        attemptCount += 1
        lastError = message
        if let disposition { self.disposition = disposition }
    }

    /// Make a parked row eligible for one more automatic attempt. If that attempt fails the same
    /// way it blocks again, so "Retry" buys exactly one try rather than resuming the old spin.
    /// `attemptCount` keeps accumulating — it's the row's lifetime total, not a per-retry budget.
    func retryOnce() {
        disposition = nil
        lastError = nil
    }
}

/// An ordered, persisted write awaiting delivery to the server.
@Model
final class PendingMutation: QueueItem {
    @Attribute(.unique) var id: UUID
    var localID: UUID          // links to the LocalEntity
    var kindRaw: String
    var opRaw: String
    var payload: Data          // JSON body to send (create/update)
    var baseSnapshot: Data?    // server version the edit derived from
    var serverID: Int?         // set for update/delete
    var attemptCount: Int
    var lastError: String?
    /// ``QueueDisposition`` rawValue; `nil` (the default for pre-existing rows) means waiting.
    var dispositionRaw: String?
    var createdAt: Date
    /// When another process (the widget/intents extension) started delivering this mutation,
    /// so the app's push loop can skip it briefly and avoid a double-send. `nil` = unclaimed.
    var claimedAt: Date?

    init(localID: UUID, kind: EntityKind, op: MutationOp, payload: Data,
         baseSnapshot: Data? = nil, serverID: Int? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.localID = localID
        self.kindRaw = kind.rawValue
        self.opRaw = op.rawValue
        self.payload = payload
        self.baseSnapshot = baseSnapshot
        self.serverID = serverID
        self.attemptCount = 0
        self.lastError = nil
        self.dispositionRaw = nil
        self.createdAt = createdAt
        self.claimedAt = nil
    }

    var kind: EntityKind { EntityKind(rawValue: kindRaw) ?? .note }
    var op: MutationOp { MutationOp(rawValue: opRaw) ?? .update }
}

/// A queued image upload (a child `picture` or a note `image`).
///
/// Kept separate from ``PendingMutation`` because it's a multipart `PATCH` of a single file field
/// that can only run **after** the target record exists on the server (has a `serverID`). The image
/// bytes live on disk (see ``ImageUploadStore``) referenced by `filename`, so large blobs stay out
/// of the SwiftData store; that same file also backs the record's local `file://` preview.
@Model
final class PendingImageUpload: QueueItem {
    @Attribute(.unique) var id: UUID
    var localID: UUID          // the LocalEntity to attach the image to
    var kindRaw: String        // .note or .child
    var filename: String       // file in the pending-images directory holding the bytes
    var mimeType: String
    var attemptCount: Int
    var lastError: String?
    /// ``QueueDisposition`` rawValue; `nil` (the default for pre-existing rows) means waiting.
    var dispositionRaw: String?
    var createdAt: Date

    init(localID: UUID, kind: EntityKind, filename: String, mimeType: String, createdAt: Date = .now) {
        self.id = UUID()
        self.localID = localID
        self.kindRaw = kind.rawValue
        self.filename = filename
        self.mimeType = mimeType
        self.attemptCount = 0
        self.lastError = nil
        self.dispositionRaw = nil
        self.createdAt = createdAt
    }

    var kind: EntityKind { EntityKind(rawValue: kindRaw) ?? .note }
}

/// A detected sync conflict awaiting user resolution.
@Model
final class ConflictRecord {
    @Attribute(.unique) var id: UUID
    var localID: UUID
    var kindRaw: String
    var opRaw: String           // the local op that conflicted (update or delete)
    var serverID: Int?
    var localPayload: Data
    var serverPayload: Data     // empty object {} when the server record was deleted
    var basePayload: Data?
    var serverDeleted: Bool     // server returned 404 (delete-vs-edit)
    var detectedAt: Date

    init(localID: UUID, kind: EntityKind, op: MutationOp, serverID: Int?,
         localPayload: Data, serverPayload: Data, basePayload: Data?,
         serverDeleted: Bool = false, detectedAt: Date = .now) {
        self.id = UUID()
        self.localID = localID
        self.kindRaw = kind.rawValue
        self.opRaw = op.rawValue
        self.serverID = serverID
        self.localPayload = localPayload
        self.serverPayload = serverPayload
        self.basePayload = basePayload
        self.serverDeleted = serverDeleted
        self.detectedAt = detectedAt
    }

    var kind: EntityKind { EntityKind(rawValue: kindRaw) ?? .note }
    var op: MutationOp { MutationOp(rawValue: opRaw) ?? .update }
}
