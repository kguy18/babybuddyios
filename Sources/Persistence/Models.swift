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

    init(localID: UUID = UUID(), kind: EntityKind, serverID: Int?, childID: Int?,
         timestamp: Date, payload: Data, syncState: SyncState,
         baseSnapshot: Data? = nil, updatedAt: Date = .now) {
        self.localID = localID
        self.kindRaw = kind.rawValue
        self.serverID = serverID
        self.childID = childID
        self.timestamp = timestamp
        self.payload = payload
        self.syncStateRaw = syncState.rawValue
        self.baseSnapshot = baseSnapshot
        self.updatedAt = updatedAt
    }

    var kind: EntityKind { EntityKind(rawValue: kindRaw) ?? .note }
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    /// Decoded payload as a JSON dictionary.
    var payloadObject: [String: Any] {
        (try? JSONSerialization.jsonObject(with: payload) as? [String: Any]) ?? [:]
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
    }

    var kind: EntityKind { EntityKind(rawValue: kindRaw) ?? .note }
    var op: MutationOp { MutationOp(rawValue: opRaw) ?? .update }
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
