import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class UndoToastTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: LocalRepository!
    private var center: UndoToastCenter!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
        repo = LocalRepository(context: context)
        center = UndoToastCenter()
        center.duration = .milliseconds(50)
    }

    private func entities() throws -> [LocalEntity] { try context.fetch(FetchDescriptor<LocalEntity>()) }
    private func mutations() throws -> [PendingMutation] { try context.fetch(FetchDescriptor<PendingMutation>()) }

    private func logFeeding() -> LocalEntity {
        repo.create(kind: .feeding, payload: [
            "child": 1, "start": "2024-01-15T10:00:00-05:00", "end": "2024-01-15T10:20:00-05:00",
            "type": "formula", "method": "bottle",
        ])!
    }

    func testUndoOfUnpushedCreateDropsRecordAndMutation() throws {
        center.show(logFeeding())
        XCTAssertEqual(center.current?.kind, .feeding)
        XCTAssertEqual(center.current?.subtitle, "Formula · Bottle · 20m")

        center.undo(in: context)
        XCTAssertNil(center.current)
        XCTAssertEqual(try entities().count, 0)
        XCTAssertEqual(try mutations().count, 0)
    }

    /// "App details copied" confirms and offers no Undo; logging still does.
    func testConfirmationHasNoUndo() throws {
        center.confirm("App details copied")
        XCTAssertEqual(center.current?.title, "App details copied")
        XCTAssertEqual(center.current?.canUndo, false)

        center.show(logFeeding())
        XCTAssertEqual(center.current?.canUndo, true)
    }

    func testUndoOfSyncedRecordQueuesDelete() throws {
        let entity = logFeeding()
        entity.serverID = 42
        entity.syncState = .synced
        try mutations().forEach { context.delete($0) }
        try context.save()

        center.show(entity)
        center.undo(in: context)
        XCTAssertEqual(entity.syncState, .pendingDelete)
        XCTAssertEqual(try mutations().first?.op, .delete)
    }

    func testNewToastReplacesOldAndUndoOnlyReversesLatest() throws {
        let first = logFeeding()
        center.show(first)
        let second = logFeeding()
        center.show(second)
        XCTAssertEqual(center.current?.localID, second.localID)

        center.undo(in: context)
        XCTAssertEqual(try entities().map(\.localID), [first.localID])
    }

    func testToastAutoDismisses() async throws {
        center.show(logFeeding())
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(center.current)
        XCTAssertEqual(try entities().count, 1) // timing out never undoes
    }

    /// Ending sick mode: a toast about something that isn't a record, with its own undo.
    func testToastWithItsOwnUndo() throws {
        var undone = false
        center.show("Sick mode ended") { undone = true }
        XCTAssertEqual(center.current?.title, "Sick mode ended")
        XCTAssertNil(center.current?.kind)

        center.undo(in: context)
        XCTAssertTrue(undone)
        XCTAssertNil(center.current)
        XCTAssertEqual(try entities().count, 0)
    }

    func testUndoAfterRecordAlreadyDeletedIsNoOp() throws {
        let entity = logFeeding()
        center.show(entity)
        repo.delete(entity)
        center.undo(in: context)
        XCTAssertNil(center.current)
        XCTAssertEqual(try entities().count, 0)
    }
}
