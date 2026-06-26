import Foundation
import SwiftData

/// The app's SwiftData container.
enum LocalStore {
    static let schema = Schema([LocalEntity.self, CachedTag.self, PendingMutation.self, ConflictRecord.self])

    /// App Group shared between the app and its widget/intents extension. The store lives
    /// here so a widget can read active timers and the App Intents can enqueue mutations.
    static let appGroupID = "group.com.kurtisguy.BabyBuddy"

    /// On-disk location of the SwiftData store. Prefers the App Group container so the
    /// extension shares it; falls back to the app's Application Support directory when the
    /// App Group is unavailable — e.g. unsigned simulator builds (`CODE_SIGNING_ALLOWED=NO`),
    /// where the entitlement isn't applied — so development builds still run.
    static var storeURL: URL {
        let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "BabyBuddy.sqlite")
    }

    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: Upsert (pull side)

    /// Insert or refresh a cached record from a server payload. Records with unsynced
    /// local state (pending*/conflicted) are left untouched so pulls never clobber edits
    /// that haven't been pushed yet.
    @discardableResult
    static func upsertFromServer(_ payload: Data, kind: EntityKind, in context: ModelContext) -> LocalEntity? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let serverID = obj["id"] as? Int else { return nil }

        let existing = fetch(kind: kind, serverID: serverID, in: context)
        if let existing {
            guard existing.syncState == .synced else { return existing } // don't clobber local edits
            // Skip writes when the server record is unchanged, so an unchanged pull doesn't dirty
            // the whole store every time (avoids write churn and keeps `hasChanges` meaningful for
            // "did this sync actually change anything"). Volatile fields are ignored so a running
            // timer's ever-advancing `duration` doesn't count as a change.
            if payloadsEquivalent(existing.payload, payload) { return existing }
            existing.payload = payload
            existing.baseSnapshot = payload
            existing.timestamp = kind.timestamp(from: obj)
            existing.childID = kind.childID(from: obj)
            existing.updatedAt = .now
            return existing
        }

        let entity = LocalEntity(
            kind: kind, serverID: serverID, childID: kind.childID(from: obj),
            timestamp: kind.timestamp(from: obj), payload: payload,
            syncState: .synced, baseSnapshot: payload)
        context.insert(entity)
        return entity
    }

    static func fetch(kind: EntityKind, serverID: Int, in context: ModelContext) -> LocalEntity? {
        let kindRaw = kind.rawValue
        var descriptor = FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.serverID == serverID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func fetch(localID: UUID, in context: ModelContext) -> LocalEntity? {
        var descriptor = FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.localID == localID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: Tags

    /// Insert or refresh a cached tag from a server ``TagDTO``. Keyed by name.
    @discardableResult
    static func upsertTag(_ dto: TagDTO, in context: ModelContext) -> CachedTag {
        let name = dto.name
        var descriptor = FetchDescriptor<CachedTag>(predicate: #Predicate { $0.name == name })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.colorHex = dto.color
            existing.slug = dto.slug
            existing.lastUsed = dto.last_used
            return existing
        }
        let tag = CachedTag(name: name, colorHex: dto.color, slug: dto.slug, lastUsed: dto.last_used)
        context.insert(tag)
        return tag
    }

    // MARK: Change detection

    /// Server-computed fields that drift without any real edit and so must be ignored when
    /// deciding whether a pulled record changed. Mirrors `SyncEngine.volatileFields` (a running
    /// timer's `duration` advances on every GET).
    static let volatilePayloadFields: Set<String> = ["duration"]

    /// Order-independent JSON equality of two payloads, ignoring volatile server-computed fields.
    static func payloadsEquivalent(_ a: Data, _ b: Data) -> Bool {
        guard var oa = try? JSONSerialization.jsonObject(with: a) as? [String: Any],
              var ob = try? JSONSerialization.jsonObject(with: b) as? [String: Any] else { return false }
        for key in volatilePayloadFields { oa.removeValue(forKey: key); ob.removeValue(forKey: key) }
        return NSDictionary(dictionary: oa).isEqual(to: ob)
    }
}
