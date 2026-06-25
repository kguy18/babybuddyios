#if DEBUG
import Foundation
import SwiftData

/// Seeds the local cache with sample records so the authenticated UI can be exercised in
/// the simulator without a live Baby Buddy server. Activated by launching with the
/// environment variable `BB_DEMO=1`.
enum DemoData {
    static func seedIfNeeded(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<LocalEntity>()))?.isEmpty ?? true
        guard existing else { return }

        insert(.child, id: 1, [
            "id": 1, "first_name": "Maya", "last_name": "Guy",
            "birth_date": "2025-11-02", "slug": "maya-guy",
        ], context)

        let now = Date()
        func iso(_ offsetMinutes: Int) -> String {
            APIDate.isoDateTime.string(from: now.addingTimeInterval(Double(-offsetMinutes * 60)))
        }

        // Cached tags so the picker has colored suggestions offline.
        for dto in [
            TagDTO(slug: "hungry", name: "hungry", color: "#ff7f7f", last_used: now),
            TagDTO(slug: "night", name: "night", color: "#00007f", last_used: now),
            TagDTO(slug: "fussy", name: "fussy", color: "#ffff7f", last_used: now),
            TagDTO(slug: "milestone", name: "milestone", color: "#007f7f", last_used: now),
        ] {
            LocalStore.upsertTag(dto, in: context)
        }

        insert(.feeding, id: 10, [
            "id": 10, "child": 1, "start": iso(90), "end": iso(70),
            "type": "breast milk", "method": "left breast", "amount": NSNull(),
            "tags": ["hungry", "night"],
        ], context)
        insert(.feeding, id: 11, [
            "id": 11, "child": 1, "start": iso(330), "end": iso(310),
            "type": "formula", "method": "bottle", "amount": 90, "tags": [],
        ], context)
        insert(.change, id: 20, [
            "id": 20, "child": 1, "time": iso(45), "wet": true, "solid": false,
            "color": "", "tags": [],
        ], context)
        insert(.change, id: 21, [
            "id": 21, "child": 1, "time": iso(200), "wet": true, "solid": true,
            "color": "yellow", "tags": [],
        ], context)
        insert(.sleep, id: 30, [
            "id": 30, "child": 1, "start": iso(420), "end": iso(180), "nap": false,
            "tags": ["night"],
        ], context)
        insert(.timer, id: 40, [
            "id": 40, "child": 1, "name": "Tummy time", "start": iso(8),
        ], context)
        insert(.weight, id: 50, [
            "id": 50, "child": 1, "weight": 5.4, "date": APIDate.dateOnly.string(from: now), "tags": [],
        ], context)

        if ProcessInfo.processInfo.environment["BB_SEED_CONFLICT"] == "1" {
            seedConflict(into: context)
        }
        try? context.save()
    }

    /// Seed a single update-vs-update conflict on the most recent feeding. Diverges in four
    /// fields (end time, amount, tags, notes) while start/type/method match, so the merge
    /// screen exercises scalar choices, a tag diff, and the silently-kept summary row.
    private static func seedConflict(into context: ModelContext) {
        guard let feeding = LocalStore.fetch(kind: .feeding, serverID: 11, in: context) else { return }
        let base = feeding.payload
        let iso: (Int) -> String = { APIDate.isoDateTime.string(from: Date().addingTimeInterval(Double(-$0 * 60))) }
        var mine = feeding.payloadObject
        mine["end"] = iso(305); mine["amount"] = 120; mine["tags"] = ["hungry", "night"]; mine["notes"] = "Extra hungry"
        var theirs = feeding.payloadObject
        theirs["amount"] = 60; theirs["notes"] = "Spit up a little"
        feeding.syncState = .conflicted
        context.insert(ConflictRecord(
            localID: feeding.localID, kind: .feeding, op: .update, serverID: 11,
            localPayload: (try? JSONSerialization.data(withJSONObject: mine)) ?? base,
            serverPayload: (try? JSONSerialization.data(withJSONObject: theirs)) ?? base,
            basePayload: base))
    }

    private static func insert(_ kind: EntityKind, id: Int, _ obj: [String: Any], _ context: ModelContext) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        LocalStore.upsertFromServer(data, kind: kind, in: context)
    }
}
#endif
