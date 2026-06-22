import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class ConflictTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var engine: SyncEngine!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
        engine = SyncEngine(session: AppSession(), context: context)
    }

    private func data(_ obj: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: obj)
    }
    private func mutations() throws -> [PendingMutation] { try context.fetch(FetchDescriptor<PendingMutation>()) }
    private func conflicts() throws -> [ConflictRecord] { try context.fetch(FetchDescriptor<ConflictRecord>()) }

    func testJSONEqualIgnoresKeyOrder() {
        let a = data(["child": 1, "note": "x", "time": "2024-01-15T10:00:00-05:00"])
        let b = data(["time": "2024-01-15T10:00:00-05:00", "note": "x", "child": 1])
        XCTAssertTrue(SyncEngine.jsonEqual(a, b))
    }

    func testJSONEqualDetectsDifference() {
        XCTAssertFalse(SyncEngine.jsonEqual(data(["note": "x"]), data(["note": "y"])))
        XCTAssertFalse(SyncEngine.jsonEqual(nil, data(["note": "x"])))
    }

    /// A running timer's server-computed `duration` advances on every GET (verified against
    /// the live API), so a plain diff would raise a false conflict on every stop. The
    /// conflict comparison must ignore it. Payloads below are real demo `/api/timers/` shapes.
    func testUnchangedSinceBaseIgnoresTimerDurationDrift() {
        let base = data(["id": 2, "child": 1, "name": "nap",
                         "start": "2026-06-22T12:09:57-05:00", "duration": "00:00:00.264700", "user": 1])
        let later = data(["id": 2, "child": 1, "name": "nap",
                          "start": "2026-06-22T12:09:57-05:00", "duration": "00:00:03.602713", "user": 1])
        XCTAssertTrue(SyncEngine.unchangedSinceBase(later, base), "duration drift must not be a conflict")
        XCTAssertFalse(SyncEngine.jsonEqual(later, base), "plain equality would wrongly flag a change")
    }

    /// Ignoring `duration` must not hide a genuine server-side edit to another field.
    func testUnchangedSinceBaseStillDetectsRealEdits() {
        let base = data(["id": 2, "child": 1, "name": "nap", "duration": "00:00:01"])
        let edited = data(["id": 2, "child": 1, "name": "feeding", "duration": "00:09:00"])
        XCTAssertFalse(SyncEngine.unchangedSinceBase(edited, base))
    }

    /// Sets up a cached note plus a conflict between a local edit and a divergent server version.
    private func makeConflict(op: MutationOp, serverDeleted: Bool = false) -> (LocalEntity, ConflictRecord) {
        let base = data(["id": 5, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "base"])
        let entity = LocalStore.upsertFromServer(base, kind: .note, in: context)!
        let mine = data(["id": 5, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "mine"])
        let theirs = data(["id": 5, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "theirs"])
        entity.syncState = .conflicted
        let conflict = ConflictRecord(
            localID: entity.localID, kind: .note, op: op, serverID: 5,
            localPayload: mine, serverPayload: serverDeleted ? Data("{}".utf8) : theirs,
            basePayload: base, serverDeleted: serverDeleted)
        context.insert(conflict)
        return (entity, conflict)
    }

    func testKeepTheirsAdoptsServerAndClearsConflict() throws {
        let (entity, conflict) = makeConflict(op: .update)
        engine.resolveKeepTheirs(conflict)
        XCTAssertEqual(entity.payloadObject["note"] as? String, "theirs")
        XCTAssertEqual(entity.syncState, .synced)
        XCTAssertEqual(try conflicts().count, 0)
        XCTAssertEqual(try mutations().count, 0)   // no server write needed
    }

    func testKeepMineEnqueuesUpdateOverServer() throws {
        let (entity, conflict) = makeConflict(op: .update)
        engine.resolveKeepMine(conflict)
        XCTAssertEqual(entity.payloadObject["note"] as? String, "mine")
        XCTAssertEqual(entity.syncState, .pendingUpdate)
        let muts = try mutations()
        XCTAssertEqual(muts.count, 1)
        XCTAssertEqual(muts.first?.op, .update)
        // Base is now the server version, so the next push won't re-conflict.
        XCTAssertTrue(SyncEngine.jsonEqual(muts.first?.baseSnapshot, conflict.serverPayload))
        XCTAssertEqual(try conflicts().count, 0)
    }

    func testMergePicksFieldsAndEnqueuesUpdate() throws {
        let (entity, conflict) = makeConflict(op: .update)
        let merged = data(["id": 5, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "merged"])
        engine.resolveMerge(conflict, merged: merged)
        XCTAssertEqual(entity.payloadObject["note"] as? String, "merged")
        XCTAssertEqual(try mutations().first?.op, .update)
        XCTAssertEqual(try conflicts().count, 0)
    }

    func testServerDeletedKeepTheirsRemovesEntity() throws {
        let (_, conflict) = makeConflict(op: .update, serverDeleted: true)
        engine.resolveKeepTheirs(conflict)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocalEntity>()).count, 0)
        XCTAssertEqual(try conflicts().count, 0)
    }

    func testServerDeletedKeepMineReCreates() throws {
        let (entity, conflict) = makeConflict(op: .update, serverDeleted: true)
        engine.resolveKeepMine(conflict)
        XCTAssertEqual(entity.syncState, .pendingCreate)
        XCTAssertNil(entity.serverID)
        XCTAssertEqual(try mutations().first?.op, .create)
    }
}
