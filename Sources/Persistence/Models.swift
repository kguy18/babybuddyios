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

/// An ordered, persisted write awaiting delivery to the server.
@Model
final class PendingMutation {
    @Attribute(.unique) var id: UUID
    var localID: UUID          // links to the LocalEntity
    var kindRaw: String
    var opRaw: String
    var payload: Data          // JSON body to send (create/update)
    var baseSnapshot: Data?    // server version the edit derived from
    var serverID: Int?         // set for update/delete
    var attemptCount: Int
    var lastError: String?
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
final class PendingImageUpload {
    @Attribute(.unique) var id: UUID
    var localID: UUID          // the LocalEntity to attach the image to
    var kindRaw: String        // .note or .child
    var filename: String       // file in the pending-images directory holding the bytes
    var mimeType: String
    var attemptCount: Int
    var lastError: String?
    var createdAt: Date

    init(localID: UUID, kind: EntityKind, filename: String, mimeType: String, createdAt: Date = .now) {
        self.id = UUID()
        self.localID = localID
        self.kindRaw = kind.rawValue
        self.filename = filename
        self.mimeType = mimeType
        self.attemptCount = 0
        self.lastError = nil
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
