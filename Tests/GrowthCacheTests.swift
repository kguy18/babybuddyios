import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class GrowthCacheTests: XCTestCase {
    func testUsesGrowthPayloadFieldsAndExcludesPendingDeletes() throws {
        let container = LocalStore.makeContainer(inMemory: true)
        let context = container.mainContext
        for (id, kind, field, value) in [
            (1, EntityKind.weight, "weight", 5.4),
            (2, EntityKind.height, "height", 62.0),
            (3, EntityKind.headCircumference, "head_circumference", 41.0),
        ] {
            let payload: [String: Any] = ["id": id, "child": 1, "date": "2026-10-27", field: value]
            let data = try JSONSerialization.data(withJSONObject: payload)
            _ = try XCTUnwrap(LocalStore.upsertFromServer(data, kind: kind, in: context))
        }
        let all = try context.fetch(FetchDescriptor<LocalEntity>())
        let samples = GrowthCache.samples(all)
        XCTAssertEqual(Set(samples.map(\.metric)), Set(GrowthMetric.allCases))
        XCTAssertEqual(samples.first { $0.metric == .headCircumference }?.value, 41)
        let weight = try XCTUnwrap(all.first { $0.kind == .weight })
        weight.syncState = .pendingDelete
        XCTAssertEqual(GrowthCache.samples(all).count, 2)
    }

    func testBooleanValuesAndMalformedDatesAreNotMeasurements() throws {
        let entities: [LocalEntity] = try [
            ["date": "2026-10-27", "weight": true] as [String: Any],
            ["date": "2026-02-30", "weight": 5.4],
            ["date": "2026-10-27"],
        ].map { payload in
            LocalEntity(kind: .weight, serverID: nil, childID: 1, timestamp: .now,
                        payload: try JSONSerialization.data(withJSONObject: payload), syncState: .pendingCreate)
        }
        XCTAssertTrue(GrowthCache.samples(entities).isEmpty)
    }
}
