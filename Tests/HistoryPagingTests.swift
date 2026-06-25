import XCTest
import SwiftData
@testable import BabyBuddy

/// Covers the "load older history" window/merge logic: per-kind range-filter selection,
/// the query parameters that actually reach the server, the deletion-reconciliation window
/// invariant, the horizon paging math, and that merging an older batch never drops cached data.
final class HistoryPagingTests: XCTestCase {

    // MARK: EntityKind windowing & range-filter params

    /// Only the high-volume event kinds are windowed; children, timers, and growth
    /// measurements are pulled in full (measurements expose no range filter on the API).
    func testWindowedKinds() {
        let windowed: Set<EntityKind> = [.feeding, .change, .sleep, .tummyTime, .pumping,
                                         .note, .temperature, .medication]
        for kind in EntityKind.allCases {
            XCTAssertEqual(kind.isWindowed, windowed.contains(kind), "\(kind) windowing")
        }
    }

    /// Start/end events filter on `start`; time-stamped records expose `date_*` (mapped onto
    /// their `time` field) — i.e. the filter base is *not* the same as `timeField` for changes,
    /// notes, temperature, and medications. Verified against upstream `api/filters.py`.
    func testRangeFilterParam() {
        for kind in [EntityKind.feeding, .sleep, .tummyTime, .pumping] {
            XCTAssertEqual(kind.rangeFilterParam, "start", "\(kind) should filter on start")
        }
        for kind in [EntityKind.change, .note, .temperature, .medication] {
            XCTAssertEqual(kind.rangeFilterParam, "date", "\(kind) should filter on date")
        }
    }

    // MARK: ListQuery parameter emission

    func testListQueryEmitsStartRangeParams() {
        let lo = Date(timeIntervalSince1970: 1_700_000_000)
        let hi = Date(timeIntervalSince1970: 1_705_000_000)
        var q = ListQuery(ordering: "-start")
        q.timeParam = "start"; q.timeMin = lo; q.timeMax = hi
        let items = Dictionary(uniqueKeysWithValues: q.items().map { ($0.name, $0.value) })

        XCTAssertEqual(items["start_min"], APIDate.isoDateTime.string(from: lo))
        XCTAssertEqual(items["start_max"], APIDate.isoDateTime.string(from: hi))
        XCTAssertNil(items["date_min"])
        XCTAssertEqual(items["ordering"], "-start")
    }

    func testListQueryDefaultsToDateRangeParams() {
        var q = ListQuery()                 // timeParam defaults to "date"
        q.timeMin = Date(timeIntervalSince1970: 1_700_000_000)
        q.child = 3; q.offset = 100; q.limit = 50
        let items = Dictionary(uniqueKeysWithValues: q.items().map { ($0.name, $0.value) })

        XCTAssertNotNil(items["date_min"])
        XCTAssertNil(items["start_min"])
        XCTAssertEqual(items["child"], "3")
        XCTAssertEqual(items["offset"], "100")
        XCTAssertEqual(items["limit"], "50")
    }

    // MARK: reconcileDeletions window invariant

    /// The core invariant: a narrower rolling-window pull must never purge a synced record
    /// older than its `windowStart` (those come from "load older" history paging), while it
    /// still purges in-window records the server dropped. Pending/conflicted state is immune.
    func testShouldPurgeWindowInvariant() {
        let windowStart = Date(timeIntervalSince1970: 1_705_000_000)
        let older = windowStart.addingTimeInterval(-86_400)      // a day before the window
        let inWindow = windowStart.addingTimeInterval(86_400)    // a day inside the window
        let present: Set<Int> = [1, 2]

        // Older-than-window record the server didn't return: PRESERVED.
        XCTAssertFalse(SyncActor.shouldPurge(
            syncState: .synced, timestamp: older, serverID: 99,
            serverIDs: present, windowStart: windowStart))

        // In-window record the server didn't return: PURGED (deleted elsewhere).
        XCTAssertTrue(SyncActor.shouldPurge(
            syncState: .synced, timestamp: inWindow, serverID: 99,
            serverIDs: present, windowStart: windowStart))

        // In-window record the server still returns: kept.
        XCTAssertFalse(SyncActor.shouldPurge(
            syncState: .synced, timestamp: inWindow, serverID: 1,
            serverIDs: present, windowStart: windowStart))

        // Unsynced local edits are never purged, regardless of window.
        for state in [SyncState.pendingCreate, .pendingUpdate, .pendingDelete, .conflicted] {
            XCTAssertFalse(SyncActor.shouldPurge(
                syncState: state, timestamp: inWindow, serverID: 99,
                serverIDs: present, windowStart: windowStart), "\(state) must survive")
        }
    }

    /// For non-windowed kinds (full pull, `windowStart == nil`) age is irrelevant: any synced
    /// record the server no longer returns is purged.
    func testShouldPurgeFullPullPurgesByAbsence() {
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        XCTAssertTrue(SyncActor.shouldPurge(
            syncState: .synced, timestamp: old, serverID: 7, serverIDs: [1], windowStart: nil))
        XCTAssertFalse(SyncActor.shouldPurge(
            syncState: .synced, timestamp: old, serverID: 1, serverIDs: [1], windowStart: nil))
    }

    // MARK: Horizon paging math

    func testNextHistoryChunkStepsBackByChunk() {
        // Paging uses calendar-day arithmetic (DST-aware), matching the rolling-window pull,
        // so derive the expectation the same way rather than with fixed 86 400-second days.
        let cal = Calendar.current
        let floor = Date(timeIntervalSince1970: 1_600_000_000)
        let horizon = cal.date(byAdding: .day, value: 100, to: floor)!   // 100 days above floor
        let chunk = SyncEngine.nextHistoryChunk(horizon: horizon, chunkDays: 60, floor: floor)
        XCTAssertEqual(chunk?.end, horizon)
        XCTAssertEqual(chunk?.start, cal.date(byAdding: .day, value: -60, to: horizon)!)
    }

    func testNextHistoryChunkClampsToFloor() {
        let cal = Calendar.current
        let floor = Date(timeIntervalSince1970: 1_600_000_000)
        let horizon = cal.date(byAdding: .day, value: 30, to: floor)!    // less than a chunk above
        let chunk = SyncEngine.nextHistoryChunk(horizon: horizon, chunkDays: 60, floor: floor)
        XCTAssertEqual(chunk?.start, floor, "should clamp to the floor, not overshoot")
        XCTAssertEqual(chunk?.end, horizon)
    }

    func testNextHistoryChunkStopsAtFloor() {
        let floor = Date(timeIntervalSince1970: 1_600_000_000)
        XCTAssertNil(SyncEngine.nextHistoryChunk(horizon: floor, chunkDays: 60, floor: floor))
        XCTAssertFalse(SyncEngine.hasMoreHistory(horizon: floor, floor: floor))
        XCTAssertTrue(SyncEngine.hasMoreHistory(
            horizon: floor.addingTimeInterval(86_400), floor: floor))
    }

    // MARK: Merge preserves cached data

    /// Upserting an older batch (as `pullOlderWindow` does) must add the older records without
    /// disturbing already-cached recent ones, and re-revealing the same older record is a no-op.
    @MainActor
    func testOlderBatchMergePreservesExisting() throws {
        let container = LocalStore.makeContainer(inMemory: true)
        let context = container.mainContext

        func upsert(id: Int, daysAgo: Int) {
            let when = APIDate.isoDateTime.string(from: Date().addingTimeInterval(Double(-daysAgo) * 86_400))
            let data = try! JSONSerialization.data(withJSONObject: [
                "id": id, "child": 1, "time": when, "wet": true, "solid": false])
            LocalStore.upsertFromServer(data, kind: .change, in: context)
        }

        upsert(id: 1, daysAgo: 2)            // recent (within window)
        upsert(id: 2, daysAgo: 120)          // older (load-older territory)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocalEntity>()).count, 2)

        upsert(id: 2, daysAgo: 120)          // re-reveal the older record: idempotent
        upsert(id: 3, daysAgo: 200)          // a deeper history page
        let all = try context.fetch(FetchDescriptor<LocalEntity>())
        XCTAssertEqual(all.count, 3, "merge must not drop or duplicate cached records")
        XCTAssertEqual(Set(all.compactMap(\.serverID)), [1, 2, 3])
    }
}
