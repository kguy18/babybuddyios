#if DEBUG
import Foundation
import SwiftData
import UIKit

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
            "picture": demoChildPicture() as Any,
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
        insert(.note, id: 60, [
            "id": 60, "child": 1, "time": iso(150), "note": "Looking out at the garden.",
            "image": demoNoteImage() as Any, "tags": ["milestone"],
        ], context)

        if ProcessInfo.processInfo.environment["BB_SEED_CONFLICT"] == "1" {
            seedConflict(into: context)
        }
        if ProcessInfo.processInfo.environment["BB_SEED_PENDING"] == "1" {
            seedPending(into: context)
        }
        try? context.save()
    }

    /// Seed a few queued writes — one create, one update, one delete — so the Pending Changes
    /// sheet can be verified in demo, where the sync engine never actually pushes.
    private static func seedPending(into context: ModelContext) {
        func data(_ o: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8) }
        let iso = APIDate.isoDateTime.string(from: Date())

        // Create: a brand-new pumping not yet on the server.
        let newPayload: [String: Any] = ["child": 1, "start": iso, "end": iso, "amount": 75, "tags": []]
        let created = LocalEntity(kind: .pumping, serverID: nil, childID: 1,
                                  timestamp: Date(), payload: data(newPayload), syncState: .pendingCreate)
        context.insert(created)
        context.insert(PendingMutation(localID: created.localID, kind: .pumping, op: .create, payload: data(newPayload)))

        // Update: edit the cached diaper change (id 20).
        if let change = LocalStore.fetch(kind: .change, serverID: 20, in: context) {
            let base = change.payload
            var edited = change.payloadObject
            edited["solid"] = true; edited["color"] = "green"
            change.baseSnapshot = base
            change.payload = data(edited)
            change.syncState = .pendingUpdate
            context.insert(PendingMutation(localID: change.localID, kind: .change, op: .update,
                                           payload: data(edited), baseSnapshot: base, serverID: 20))
        }

        // Delete: remove the cached sleep (id 30).
        if let sleep = LocalStore.fetch(kind: .sleep, serverID: 30, in: context) {
            sleep.syncState = .pendingDelete
            context.insert(PendingMutation(localID: sleep.localID, kind: .sleep, op: .delete,
                                           payload: Data("{}".utf8), baseSnapshot: sleep.payload, serverID: 30))
        }
    }

    /// Reveal the slice of the fixed historic dataset whose dates fall within `[start, end]`,
    /// mimicking a server fetch for that older window. Drives BB_DEMO verification of "load
    /// older": each `SyncEngine.loadOlderHistory()` chunk uncovers the entries it spans, all
    /// dated older than the rolling 60-day window but after Maya's birth (2025-11-02). ids are
    /// namespaced (1000+) so they never collide with the recent seeds; upsert keeps re-reveals
    /// idempotent.
    static func seedOlderBatch(from start: Date, to end: Date, into context: ModelContext) {
        let now = Date()
        func day(_ daysAgo: Int) -> Date { now.addingTimeInterval(Double(-daysAgo) * 86_400) }
        func iso(_ d: Date) -> String { APIDate.isoDateTime.string(from: d) }
        func mins(_ d: Date, _ m: Int) -> String { iso(d.addingTimeInterval(Double(m) * 60)) }

        let historic: [(id: Int, kind: EntityKind, daysAgo: Int, payload: (Date) -> [String: Any])] = [
            (1001, .feeding, 70, { ["start": mins($0, -20), "end": iso($0), "type": "formula",
                                    "method": "bottle", "amount": 100, "tags": []] }),
            (1002, .change, 72, { ["time": iso($0), "wet": true, "solid": false, "color": "", "tags": []] }),
            (1003, .sleep, 95, { ["start": mins($0, -180), "end": iso($0), "nap": true, "tags": ["night"]] }),
            (1004, .feeding, 100, { ["start": mins($0, -15), "end": iso($0), "type": "breast milk",
                                     "method": "left breast", "amount": NSNull(), "tags": ["hungry"]] }),
            (1005, .note, 115, { ["time": iso($0), "note": "First real smile!", "tags": ["milestone"]] }),
            (1006, .change, 130, { ["time": iso($0), "wet": true, "solid": true, "color": "yellow", "tags": []] }),
            (1007, .sleep, 140, { ["start": mins($0, -240), "end": iso($0), "nap": false, "tags": ["night"]] }),
            (1008, .tummyTime, 175, { ["start": mins($0, -10), "end": iso($0), "tags": []] }),
            (1009, .feeding, 200, { ["start": mins($0, -18), "end": iso($0), "type": "formula",
                                     "method": "bottle", "amount": 60, "tags": []] }),
            (1010, .change, 210, { ["time": iso($0), "wet": true, "solid": false, "color": "", "tags": []] }),
        ]

        for item in historic {
            let when = day(item.daysAgo)
            guard when >= start, when <= end else { continue }
            var p = item.payload(when)
            p["id"] = item.id
            p["child"] = 1
            insert(item.kind, id: item.id, p, context)
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

    // MARK: Demo images
    //
    // The display feature fetches media from the server, which demo mode has no access to. To
    // exercise the image UI (avatar + note thumbnail) offline, render a couple of placeholder
    // images to the caches directory and seed their `file://` URLs — `RemoteImage` loads file URLs
    // directly with no network.

    /// A simple flat "portrait" (distinct from the initials fallback so the loaded photo is
    /// visually obvious), written once to caches.
    private static func demoChildPicture() -> String? {
        renderDemoImage(named: "child", size: CGSize(width: 240, height: 240)) { ctx, rect in
            UIColor(hex: "F4A6C0").setFill()
            ctx.fill(rect)
            UIColor(hex: "FFE0B2").setFill()  // face
            ctx.fillEllipse(in: rect.insetBy(dx: rect.width * 0.26, dy: rect.height * 0.18))
            UIColor(hex: "5D4037").setFill()  // eyes
            ctx.fillEllipse(in: CGRect(x: rect.width * 0.40, y: rect.height * 0.42, width: rect.width * 0.06, height: rect.width * 0.06))
            ctx.fillEllipse(in: CGRect(x: rect.width * 0.54, y: rect.height * 0.42, width: rect.width * 0.06, height: rect.width * 0.06))
        }
    }

    /// A simple flat "garden" scene, written once to caches, for the seeded note's thumbnail.
    private static func demoNoteImage() -> String? {
        renderDemoImage(named: "note", size: CGSize(width: 320, height: 320)) { ctx, rect in
            UIColor(hex: "BFE3F5").setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height * 0.6))
            UIColor(hex: "A8D08D").setFill()
            ctx.fill(CGRect(x: 0, y: rect.height * 0.6, width: rect.width, height: rect.height * 0.4))
            UIColor(hex: "FFD54A").setFill()
            let sun = CGRect(x: rect.width * 0.66, y: rect.height * 0.1, width: rect.width * 0.22, height: rect.width * 0.22)
            ctx.fillEllipse(in: sun)
        }
    }

    private static func renderDemoImage(named name: String, size: CGSize,
                                        draw: (CGContext, CGRect) -> Void) -> String? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("bbdemo_\(name).png")
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in draw(ctx.cgContext, CGRect(origin: .zero, size: size)) }
        guard let data = image.pngData() else { return nil }
        try? data.write(to: url, options: .atomic)
        return url.absoluteString
    }
}
#endif
