import Foundation
import SwiftData

/// The app's SwiftData container.
enum LocalStore {
    static let schema = Schema([LocalEntity.self, PendingMutation.self, ConflictRecord.self])

    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
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
}
