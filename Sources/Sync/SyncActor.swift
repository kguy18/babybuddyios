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
        do {
            try await pullTags(client: client)
            try modelContext.save()
        } catch APIError.notFound {
            // Tags endpoint absent on this server version — skip.
        } catch APIError.unauthorized {
            return Self.unauthorized
        } catch let error as APIError {
            return error.userMessage
        } catch {
            return error.localizedDescription
        }
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

    /// Pull the server's global tag list into the cache for the picker's autocomplete.
    /// Tags are low-volume and not child-scoped, so we pull all and reconcile deletions.
    private func pullTags(client: APIClient) async throws {
        let records = try await client.listAllRaw(path: "tags")
        var names = Set<String>()
        for record in records {
            guard let dto = try? APICoders.decoder.decode(TagDTO.self, from: record) else { continue }
            LocalStore.upsertTag(dto, in: modelContext)
            names.insert(dto.name)
        }
        let cached = (try? modelContext.fetch(FetchDescriptor<CachedTag>())) ?? []
        for tag in cached where !names.contains(tag.name) {
            modelContext.delete(tag)
        }
    }

    private func pull(kind: EntityKind, client: APIClient, windowDays: Int) async throws {
        var query = ListQuery(ordering: "-\(kind.timeField)")
        // Only high-volume event kinds are windowed; children, timers, and growth
        // measurements are pulled in full (measurements expose no range filter on the API).
        let windowStart = kind.isWindowed
            ? Calendar.current.date(byAdding: .day, value: -windowDays, to: .now)
            : nil
        if let windowStart {
            query.timeParam = kind.rangeFilterParam
            query.timeMin = windowStart
        }

        let records = try await client.listAllRaw(path: kind.path, query: query)
        var serverIDs = Set<Int>()
        for record in records {
            if let entity = LocalStore.upsertFromServer(record, kind: kind, in: modelContext),
               let id = entity.serverID {
                serverIDs.insert(id)
            }
        }
        reconcileDeletions(kind: kind, serverIDs: serverIDs, windowStart: windowStart)
    }

    /// Pull a historic date window `[dateMin, dateMax]` across every windowed kind, merging
    /// the results into the cache for on-demand "load older" history. Unlike
    /// ``pull(kind:client:windowDays:)`` this **only ever upserts and never reconciles
    /// deletions**, so records already cached — by this call, an earlier history page, or the
    /// rolling window — are never dropped. Returns `nil` on success, or an error message.
    func pullOlderWindow(config: ServerConfig, dateMin: Date, dateMax: Date) async -> String? {
        let client = APIClient(config: config)
        for kind in EntityKind.allCases where kind.isWindowed {
            do {
                var query = ListQuery(ordering: "-\(kind.timeField)")
                query.timeParam = kind.rangeFilterParam
                query.timeMin = dateMin
                query.timeMax = dateMax
                let records = try await client.listAllRaw(path: kind.path, query: query)
                for record in records {
                    LocalStore.upsertFromServer(record, kind: kind, in: modelContext)
                }
                try modelContext.save()       // commit per kind so the UI fills in progressively
            } catch APIError.notFound {
                continue                       // endpoint absent on this server version
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

    /// Remove synced local records the server no longer returns within the pulled window
    /// (deleted elsewhere). Pending/conflicted records are never touched.
    private func reconcileDeletions(kind: EntityKind, serverIDs: Set<Int>, windowStart: Date?) {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.serverID != nil })
        guard let locals = try? modelContext.fetch(descriptor) else { return }
        for local in locals where Self.shouldPurge(
            syncState: local.syncState, timestamp: local.timestamp, serverID: local.serverID,
            serverIDs: serverIDs, windowStart: windowStart) {
            modelContext.delete(local)
        }
    }

    /// Whether a cached record should be purged as a server-side deletion. Only *synced*
    /// records the windowed pull no longer returned are candidates, and only those at or
    /// after `windowStart`: records older than the rolling window — fetched by "load older"
    /// history paging — are preserved so a narrower pull never drops them. Pending/conflicted
    /// local edits are never purged. Pure, so the window invariant is unit-testable.
    static func shouldPurge(syncState: SyncState, timestamp: Date, serverID: Int?,
                            serverIDs: Set<Int>, windowStart: Date?) -> Bool {
        guard syncState == .synced, let serverID else { return false }
        if let windowStart, timestamp < windowStart { return false } // outside pulled window — keep
        return !serverIDs.contains(serverID)
    }
}
