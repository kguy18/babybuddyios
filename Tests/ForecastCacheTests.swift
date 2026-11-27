import XCTest
@testable import BabyBuddy

/// ``ForecastCache`` skips rows older than the engine's lookback before decoding them, and that
/// leaves the estimate unchanged.
@MainActor
final class ForecastCacheTests: XCTestCase {
    /// Whole seconds, as the payloads' ISO strings keep them, so `timestamp` and the parsed start agree.
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())

    private func entity(_ kind: EntityKind, daysAgo: Double, hours: Double = 0.25) -> LocalEntity {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        var payload: [String: Any] = ["child": 1, kind.timeField: APIDate.isoDateTime.string(from: start)]
        if kind != .change { payload["end"] = APIDate.isoDateTime.string(from: start.addingTimeInterval(hours * 3600)) }
        return LocalEntity(kind: kind, serverID: nil, childID: 1, timestamp: start,
                           payload: try! JSONSerialization.data(withJSONObject: payload), syncState: .synced)
    }

    /// A year of feeds, sleeps and changes every three hours.
    private func history() -> [LocalEntity] {
        stride(from: 0.1, through: 365, by: 0.125).flatMap { day in
            [entity(.feeding, daysAgo: day), entity(.sleep, daysAgo: day + 0.05, hours: 1.5),
             entity(.change, daysAgo: day + 0.02)]
        }
    }

    func testRecordsSkipRowsOlderThanTheLookback() {
        let records = ForecastCache.records(history(), now: now)
        let cutoff = now.addingTimeInterval(-Double(ForecastEngine.lookbackDays + 1) * 86_400)
        XCTAssertFalse(records.isEmpty)
        XCTAssertTrue(records.allSatisfy { $0.start >= cutoff })
        XCTAssertEqual(Set(records.map(\.kind)), [.feeding, .sleep, .change])
    }

    func testSkippingOldRowsLeavesTheEstimateUnchanged() {
        let entities = history()
        // Every row, as the cache built them before it skipped any.
        let everything = entities.map { entity in
            ForecastRecord(id: entity.localID, childID: 1, kind: ForecastRecord.Kind(rawValue: entity.kindRaw)!,
                           start: entity.timestamp, end: entity.startEndDates.end, nap: nil,
                           excluded: false, conflicted: false)
        }
        let expected = ForecastEngine().snapshot(records: everything, timers: [], childID: 1,
                                                 lastSync: now, now: now)
        XCTAssertEqual(ForecastCache.snapshot(entities, childID: 1, lastSync: now, now: now), expected)
        XCTAssertGreaterThan(everything.count, ForecastCache.records(entities, now: now).count * 10)
    }
}
