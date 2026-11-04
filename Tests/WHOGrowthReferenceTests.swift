import XCTest
@testable import BabyBuddy

final class WHOGrowthReferenceTests: XCTestCase {
    private func load() throws -> WHOGrowthReference {
        #if SWIFT_PACKAGE
        return try XCTUnwrap(WHOGrowthReference.load(bundle: .module))
        #else
        return try XCTUnwrap(WHOGrowthReference.load())
        #endif
    }

    func testEveryPublishedDailyCentileAgainstLMS() throws {
        let reference = try load()
        XCTAssertTrue(reference.isValid)
        // Standard-normal quantiles for P3, P15, P50, P85, P97. Published columns are
        // rounded to three decimals; LMS columns are themselves rounded by WHO.
        let z = [-1.8807936081512509, -1.0364333894937898, 0, 1.0364333894937898, 1.8807936081512509]
        var count = 0
        for table in reference.tables {
            XCTAssertEqual(table.rows.count, 1857)
            for row in table.rows {
                for (index, quantile) in z.enumerated() {
                    let value = try XCTUnwrap(WHOGrowthReference.value(l: row[1], m: row[2], s: row[3], z: quantile))
                    XCTAssertEqual(value, row[index + 4], accuracy: 0.001,
                                   "\(table.metric) \(table.sex) day \(row[0]) P\(WHOGrowthReference.percentiles[index])")
                    count += 1
                }
            }
        }
        XCTAssertEqual(count, 55710)
    }

    func testOfficialBirthExamplesForBothReferenceSexes() throws {
        let reference = try load()
        // WHO official percentile tables, birth rows. Values below are independently
        // transcribed from the monthly PDF tables, which round to one decimal.
        let examples: [(GrowthMetric, GrowthReferenceSex, [Double])] = [
            (.weight, .boys, [2.5, 2.9, 3.3, 3.9, 4.3]),
            (.weight, .girls, [2.4, 2.8, 3.2, 3.7, 4.2]),
            (.height, .boys, [46.3, 47.9, 49.9, 51.8, 53.4]),
            (.height, .girls, [45.6, 47.2, 49.1, 51.1, 52.7]),
            (.headCircumference, .boys, [32.1, 33.1, 34.5, 35.8, 36.9]),
            (.headCircumference, .girls, [31.7, 32.7, 33.9, 35.1, 36.1]),
        ]
        for (metric, sex, expected) in examples {
            let row = try XCTUnwrap(reference.row(metric: metric, sex: sex, day: 0))
            for index in expected.indices { XCTAssertEqual(row[4 + index], expected[index], accuracy: 0.051) }
        }
    }

    func testLimitsAndLengthDiscontinuity() throws {
        let reference = try load()
        XCTAssertNil(reference.row(metric: .weight, sex: .boys, day: -1))
        XCTAssertNotNil(reference.row(metric: .weight, sex: .boys, day: 1856))
        XCTAssertNil(reference.row(metric: .weight, sex: .boys, day: 1857))
        XCTAssertNil(reference.row(metric: .weight, sex: .none, day: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let birth = GrowthDate.parse("2024-01-01", calendar: calendar)!
        let end = calendar.date(byAdding: .day, value: 731, to: birth)!
        let start = calendar.date(byAdding: .day, value: 730, to: birth)!
        let points = reference.points(metric: .height, sex: .boys, birth: birth,
                                      domain: start...end, calendar: calendar)
        let median = points.filter { $0.percentile == 50 }
        XCTAssertEqual(median.count, 2)
        XCTAssertNotEqual(median[0].segment, median[1].segment)
        XCTAssertLessThan(median[1].value, median[0].value)
        XCTAssertEqual(points.map(\.id).count, Set(points.map(\.id)).count)
    }

    func testNoExtrapolationBeforeDueDateOrAfterReferenceRange() throws {
        let reference = try load()
        let birth = GrowthDate.parse("2026-02-01")!
        let earlier = GrowthDate.parse("2026-01-01")!
        XCTAssertTrue(reference.points(metric: .weight, sex: .girls, birth: birth, domain: earlier...earlier).isEmpty)
        let late = Calendar.current.date(byAdding: .day, value: 1900, to: birth)!
        XCTAssertTrue(reference.points(metric: .weight, sex: .girls, birth: birth, domain: late...late).isEmpty)
    }

    func testLMSZeroLimitAndInvalidInputs() throws {
        XCTAssertEqual(try XCTUnwrap(WHOGrowthReference.value(l: 0, m: 10, s: 0.1, z: 1)), 10 * exp(0.1), accuracy: 1e-10)
        XCTAssertNil(WHOGrowthReference.value(l: 1, m: -1, s: 0.1, z: 1))
        XCTAssertNil(WHOGrowthReference.value(l: 1, m: 10, s: 0.1, z: 4))
        XCTAssertNil(WHOGrowthReference.value(l: .nan, m: 10, s: 0.1, z: 1))
    }

    func testLongHistorySamplingKeepsEndpointsAndPostureBreak() throws {
        let reference = try load()
        let birth = GrowthDate.parse("2020-01-01")!
        let end = Calendar.current.date(byAdding: .day, value: 1856, to: birth)!
        let points = reference.points(metric: .height, sex: .girls, birth: birth,
                                      domain: birth...end, maximumPointsPerCurve: 120)
        let median = points.filter { $0.percentile == 50 }
        XCTAssertLessThan(median.count, 250)
        for day in [0, 1, 90, 730, 731, 1856] { XCTAssertTrue(median.contains { $0.day == day }) }
        for point in median {
            XCTAssertEqual(point.value, reference.row(metric: .height, sex: .girls, day: point.day)?[6])
        }
    }
}
