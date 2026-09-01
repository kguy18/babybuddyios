import XCTest
import SwiftData
@testable import BabyBuddy

/// Signing out (or signing in to a different server) must leave nothing behind: the previous
/// family's activities can't show up on the next server, and a queued write must never be
/// replayed against a server that never saw the record.
@MainActor
final class SignOutWipeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var savedChildID: Int?

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
        savedChildID = SharedDefaults.selectedChildID
    }

    override func tearDown() async throws {
        SharedDefaults.selectedChildID = savedChildID
    }

    func testWipeRemovesRecordsQueuedWritesAndImageBytes() throws {
        let repo = LocalRepository(context: context)
        let feeding = repo.create(kind: .feeding, payload: [
            "child": 1, "start": "2024-01-15T10:00:00-05:00", "end": "2024-01-15T10:20:00-05:00",
            "type": "formula", "method": "bottle",
        ])!
        let note = repo.create(kind: .note, payload: ["child": 1, "time": "2024-01-15T10:00:00-05:00", "note": "a"])!
        repo.enqueueImageUpload(for: note, imageData: Data("jpeg".utf8))
        LocalStore.upsertTag(TagDTO(slug: "nap", name: "nap", color: "#fff", last_used: nil), in: context)
        context.insert(ConflictRecord(localID: feeding.localID, kind: .feeding, op: .update, serverID: 7,
                                      localPayload: feeding.payload, serverPayload: feeding.payload,
                                      basePayload: feeding.payload))
        try context.save()
        SharedDefaults.selectedChildID = 1

        let filename = try XCTUnwrap(
            try context.fetch(FetchDescriptor<PendingImageUpload>()).first?.filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ImageUploadStore.url(for: filename).path))

        LocalStore.wipe(in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<LocalEntity>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingImageUpload>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CachedTag>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ConflictRecord>()).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ImageUploadStore.url(for: filename).path))
        XCTAssertNil(SharedDefaults.selectedChildID)
    }

    /// The same server typed with a trailing slash or different casing must *not* count as a
    /// move — that would wipe unsynced work on an ordinary re-login.
    func testServerKeyIgnoresTrailingSlashAndCase() throws {
        let key = { AppSession.serverKey(for: URL(string: $0)!) }
        XCTAssertEqual(key("https://baby.example.com/"), key("https://Baby.Example.com"))
        XCTAssertEqual(key("https://baby.example.com:8000/sub/"), key("https://baby.example.com:8000/sub"))
        XCTAssertNotEqual(key("https://baby.example.com"), key("https://other.example.com"))
    }
}
