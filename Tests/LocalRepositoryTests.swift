import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class LocalRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: LocalRepository!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
        repo = LocalRepository(context: context)
    }

    private func mutations() throws -> [PendingMutation] {
        try context.fetch(FetchDescriptor<PendingMutation>())
    }
    private func entities() throws -> [LocalEntity] {
        try context.fetch(FetchDescriptor<LocalEntity>())
    }

    func testCreateInsertsPendingCreate() throws {
        let entity = repo.create(kind: .feeding, payload: [
            "child": 1, "start": "2024-01-15T10:00:00-05:00", "end": "2024-01-15T10:20:00-05:00",
            "type": "formula", "method": "bottle",
        ])
        XCTAssertEqual(entity?.syncState, .pendingCreate)
        XCTAssertNil(entity?.serverID)
        XCTAssertEqual(entity?.childID, 1)
        let muts = try mutations()
        XCTAssertEqual(muts.count, 1)
        XCTAssertEqual(muts.first?.op, .create)
    }

    func testUpdateCoalescesWithPendingCreate() throws {
        let entity = repo.create(kind: .note, payload: ["child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "a"])!
        repo.update(entity, payload: ["child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "b"])

        // Still a single create mutation, payload refreshed; state stays pendingCreate.
        let muts = try mutations()
        XCTAssertEqual(muts.count, 1)
        XCTAssertEqual(muts.first?.op, .create)
        XCTAssertEqual(entity.syncState, .pendingCreate)
        XCTAssertEqual(entity.payloadObject["note"] as? String, "b")
    }

    func testDeleteUnsyncedRemovesEverything() throws {
        let entity = repo.create(kind: .note, payload: ["child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "x"])!
        repo.delete(entity)
        XCTAssertEqual(try entities().count, 0)
        XCTAssertEqual(try mutations().count, 0)
    }

    func testDeleteSyncedEnqueuesDelete() throws {
        // Simulate a synced record pulled from the server.
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": 99, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "x"])
        let entity = LocalStore.upsertFromServer(payload, kind: .note, in: context)!
        XCTAssertEqual(entity.syncState, .synced)

        repo.delete(entity)
        XCTAssertEqual(entity.syncState, .pendingDelete)
        let muts = try mutations()
        XCTAssertEqual(muts.count, 1)
        XCTAssertEqual(muts.first?.op, .delete)
        XCTAssertEqual(muts.first?.serverID, 99)
    }

    func testRepeatEventPreservesDurationAndRestampsToNow() throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": 42, "url": "http://x/42", "child": 1, "duration": "00:20:00",
            "start": "2024-01-15T10:00:00-05:00", "end": "2024-01-15T10:20:00-05:00",
            "type": "formula", "method": "bottle"])
        let original = LocalStore.upsertFromServer(payload, kind: .feeding, in: context)!

        let now = Date()
        let copy = repo.repeatEvent(original, now: now)!

        // A brand-new pending-create record, distinct from the source.
        XCTAssertEqual(copy.syncState, .pendingCreate)
        XCTAssertNil(copy.serverID)
        XCTAssertNotEqual(copy.localID, original.localID)

        // Server-assigned/computed fields are dropped.
        let p = copy.payloadObject
        XCTAssertNil(p["id"])
        XCTAssertNil(p["url"])
        XCTAssertNil(p["duration"])

        // Carried-over data survives.
        XCTAssertEqual(p["type"] as? String, "formula")
        XCTAssertEqual(p["child"] as? Int, 1)

        // 20-minute span preserved, ending now.
        let start = APIDate.parse(p["start"] as! String)!
        let end = APIDate.parse(p["end"] as! String)!
        XCTAssertEqual(end.timeIntervalSince(start), 20 * 60, accuracy: 1)
        XCTAssertEqual(end.timeIntervalSince(now), 0, accuracy: 1)

        // The original is untouched.
        XCTAssertEqual(original.serverID, 42)
    }

    func testRepeatEventRestampsTimeStampedRecord() throws {
        let entity = repo.create(kind: .note, payload: [
            "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "hello"])!
        let now = Date()
        let copy = repo.repeatEvent(entity, now: now)!

        let p = copy.payloadObject
        XCTAssertEqual(p["note"] as? String, "hello")
        let time = APIDate.parse(p["time"] as! String)!
        XCTAssertEqual(time.timeIntervalSince(now), 0, accuracy: 1)
    }

    func testEnqueueImageUploadQueuesAndPreviewsLocally() throws {
        let note = repo.create(kind: .note, payload: ["child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "x"])!
        repo.enqueueImageUpload(for: note, imageData: Data([0x1, 0x2, 0x3]))

        let uploads = try context.fetch(FetchDescriptor<PendingImageUpload>())
        XCTAssertEqual(uploads.count, 1)
        XCTAssertEqual(uploads.first?.localID, note.localID)
        XCTAssertEqual(uploads.first?.kind, .note)

        // The cached record points its image at the local file so it previews before upload, and
        // the bytes are on disk under that name.
        let imageURLString = note.payloadObject["image"] as? String
        XCTAssertNotNil(imageURLString)
        XCTAssertTrue(imageURLString?.hasPrefix("file://") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ImageUploadStore.url(for: uploads.first!.filename).path))

        ImageUploadStore.delete(uploads.first!.filename) // cleanup
    }

    func testEnqueueImageUploadCoalescesToLatest() throws {
        let note = repo.create(kind: .note, payload: ["child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "x"])!
        repo.enqueueImageUpload(for: note, imageData: Data([0x1]))
        let first = try XCTUnwrap(try context.fetch(FetchDescriptor<PendingImageUpload>()).first)
        repo.enqueueImageUpload(for: note, imageData: Data([0x2]))

        let uploads = try context.fetch(FetchDescriptor<PendingImageUpload>())
        XCTAssertEqual(uploads.count, 1, "a newer pick should replace the earlier queued one")
        XCTAssertNotEqual(uploads.first?.filename, first.filename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ImageUploadStore.url(for: first.filename).path),
                       "the superseded file should be deleted")

        ImageUploadStore.delete(uploads.first!.filename) // cleanup
    }

    func testEnqueueImageUploadIgnoresKindsWithoutImage() throws {
        let feeding = repo.create(kind: .feeding, payload: ["child": 1, "start": "2024-01-15T10:00:00-05:00"])!
        repo.enqueueImageUpload(for: feeding, imageData: Data([0x1]))
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingImageUpload>()).count, 0)
        XCTAssertNil(feeding.payloadObject["image"])
    }

    func testPullDoesNotClobberLocalEdit() throws {
        // A locally edited (pendingUpdate) record must survive a re-pull of the server version.
        let original = try JSONSerialization.data(withJSONObject: [
            "id": 7, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "server"])
        let entity = LocalStore.upsertFromServer(original, kind: .note, in: context)!
        repo.update(entity, payload: ["id": 7, "child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "mine"])
        XCTAssertEqual(entity.syncState, .pendingUpdate)

        // Server still has the old value; a pull must not overwrite the local edit.
        LocalStore.upsertFromServer(original, kind: .note, in: context)
        XCTAssertEqual(entity.payloadObject["note"] as? String, "mine")
    }
}
