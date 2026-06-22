import Foundation
import SwiftData

/// Performs the bulk pull (server → cache) on a background context so parsing and
/// inserting large datasets never blocks the main thread. It shares the app's
/// `ModelContainer`, so records it saves are merged into the main context that drives
/// the UI's `@Query`s.
///
/// Push, conflict detection, and conflict resolution stay on the main context in
/// ``SyncEngine`` — they're network-bound, low-volume, and user-initiated.
@ModelActor
actor SyncActor {
    /// Sentinel returned when the server rejects the token, so the caller can sign out.
    static let unauthorized = "##unauthorized##"

    /// Pull every kind into the store. Returns `nil` on success, or an error message.
    func pullAll(config: ServerConfig, windowDays: Int) async -> String? {
        let client = APIClient(config: config)
        for kind in EntityKind.allCases {
            do {
                try await pull(kind: kind, client: client, windowDays: windowDays)
                try modelContext.save()      // commit per kind so the UI fills in progressively
            } catch APIError.notFound {
                continue                      // endpoint absent on this server version (e.g. medications)
            } catch APIError.unauthorized {
                return Self.unauthorized
            } catch let error as APIError {
                return error.userMessage
            } catch {
                return error.localizedDescription
            }
        }
        return nil
    }

    private func pull(kind: EntityKind, client: APIClient, windowDays: Int) async throws {
        var query = ListQuery(ordering: "-\(kind.timeField)")
        // Children and timers are low-volume; pull everything. Window the rest.
        let windowStart = Calendar.current.date(byAdding: .day, value: -windowDays, to: .now)
        if kind != .child && kind != .timer { query.dateMin = windowStart }

        let records = try await client.listAllRaw(path: kind.path, query: query)
        var serverIDs = Set<Int>()
        for record in records {
            if let entity = LocalStore.upsertFromServer(record, kind: kind, in: modelContext),
               let id = entity.serverID {
                serverIDs.insert(id)
            }
        }
        reconcileDeletions(kind: kind, serverIDs: serverIDs,
                           windowStart: (kind == .child || kind == .timer) ? nil : windowStart)
    }

    /// Remove synced local records the server no longer returns within the pulled window
    /// (deleted elsewhere). Pending/conflicted records are never touched.
    private func reconcileDeletions(kind: EntityKind, serverIDs: Set<Int>, windowStart: Date?) {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.serverID != nil })
        guard let locals = try? modelContext.fetch(descriptor) else { return }
        for local in locals where local.syncState == .synced {
            if let windowStart, local.timestamp < windowStart { continue } // outside pulled window
            if let id = local.serverID, !serverIDs.contains(id) {
                modelContext.delete(local)
            }
        }
    }
}
