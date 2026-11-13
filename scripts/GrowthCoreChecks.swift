// Standalone verification when only Swift + Foundation are available, without XCTest.
import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() {
        FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
        exit(1)
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
func date(_ raw: String) -> Date {
    guard let result = GrowthDate.parse(raw, calendar: calendar) else { fatalError("Invalid test date: \(raw)") }
    return result
}

let referenceData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let reference = try JSONDecoder().decode(WHOGrowthReference.self, from: referenceData)
check(reference.isValid, "Six complete daily WHO tables")
let quantiles = [-1.8807936081512509, -1.0364333894937898, 0, 1.0364333894937898, 1.8807936081512509]
for table in reference.tables {
    for row in table.rows {
        for (index, z) in quantiles.enumerated() {
            let computed = WHOGrowthReference.value(l: row[1], m: row[2], s: row[3], z: z)
            check(computed.map { abs($0 - row[4 + index]) <= 0.001 } == true,
                  "LMS \(table.metric) \(table.sex) day \(row[0]) P\(WHOGrowthReference.percentiles[index])")
        }
    }
}
// Independent one-decimal birth examples from the WHO monthly PDF tables.
let birthExamples: [(GrowthMetric, GrowthReferenceSex, [Double])] = [
    (.weight, .boys, [2.5, 2.9, 3.3, 3.9, 4.3]),
    (.weight, .girls, [2.4, 2.8, 3.2, 3.7, 4.2]),
    (.height, .boys, [46.3, 47.9, 49.9, 51.8, 53.4]),
    (.height, .girls, [45.6, 47.2, 49.1, 51.1, 52.7]),
    (.headCircumference, .boys, [32.1, 33.1, 34.5, 35.8, 36.9]),
    (.headCircumference, .girls, [31.7, 32.7, 33.9, 35.1, 36.1]),
]
for (metric, sex, expected) in birthExamples {
    let row = reference.row(metric: metric, sex: sex, day: 0)!
    for index in expected.indices {
        check(abs(row[4 + index] - expected[index]) <= 0.051, "WHO PDF birth example \(metric) \(sex) P index \(index)")
    }
}
check(reference.row(metric: .weight, sex: .boys, day: -1) == nil, "No negative age lookup")
check(reference.row(metric: .weight, sex: .boys, day: 1857) == nil, "No extrapolation")
check(reference.row(metric: .weight, sex: .none, day: 0) == nil, "No inferred reference sex")
check(GrowthDate.parse("2026-02-30") == nil, "Reject impossible dates")
check(GrowthDate.parse("2026-1-01") == nil, "Reject malformed dates")
check(GrowthDate.ageDays(birth: date("2026-03-28"), date: date("2026-03-30"), calendar: calendar) == 2,
      "Age across spring DST")
check(GrowthDate.ageDays(birth: date("2024-02-28"), date: date("2024-03-01"), calendar: calendar) == 2,
      "Age across leap day")
var pacific = calendar
pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
let pacificDate = GrowthDate.parse("2026-03-08", calendar: pacific)!
check(pacific.component(.day, from: pacificDate) == 8, "Date-only in Pacific time")
var buddhist = Calendar(identifier: .buddhist)
buddhist.timeZone = calendar.timeZone
check(GrowthDate.parse("2026-10-27", calendar: buddhist) == date("2026-10-27"), "API dates remain Gregorian")

let birth = date("2024-01-01")
let day730 = calendar.date(byAdding: .day, value: 730, to: birth)!
let day731 = calendar.date(byAdding: .day, value: 731, to: birth)!
let median = reference.points(metric: .height, sex: .boys, birth: birth,
                              domain: day730...day731, calendar: calendar).filter { $0.percentile == 50 }
check(median.count == 2 && median[0].segment != median[1].segment, "Length/height break at day 731")
check(median[1].value < median[0].value, "Published length/height discontinuity retained")
let lastDate = calendar.date(byAdding: .day, value: 1856, to: birth)!
let sampled = reference.points(metric: .height, sex: .girls, birth: birth, domain: birth...lastDate,
                               calendar: calendar, maximumPointsPerCurve: 120).filter { $0.percentile == 50 }
check(sampled.count < 250, "Bound long-history chart marks")
for day in [0, 1, 90, 730, 731, 1856] {
    check(sampled.contains { $0.day == day }, "Sampled curve preserves day \(day)")
}
for point in sampled {
    check(point.value == reference.row(metric: .height, sex: .girls, day: point.day)?[6], "Sampled curve uses published day value")
}

func sample(_ raw: String, value: Double = 5, child: Int = 1,
            metric: GrowthMetric = .weight, excluded: Bool = false) -> GrowthSample {
    GrowthSample(id: UUID(), childID: child, metric: metric, date: date(raw), value: value, excluded: excluded)
}
let samples = [sample("2026-09-27"), sample("2026-09-28"), sample("2026-10-27"),
               sample("2026-10-27", value: 5.1), sample("2026-10-28"),
               sample("2026-10-26", child: 2), sample("2026-10-26", metric: .height),
               sample("2026-10-26", excluded: true), sample("2026-10-26", value: .nan),
               sample("2026-10-26", value: .infinity), sample("2026-10-26", value: 0)]
let series = GrowthSeries(calendar: calendar)
let filtered = series.samples(samples, childID: 1, metric: .weight, period: .month, now: date("2026-10-27"))
check(filtered.count == 3, "Period, child, kind, deletion, invalid values and future dates")
check(Set(filtered.map(\.id)).count == 3, "Two same-day readings retained")
check(series.samples(samples, childID: 1, metric: .weight, period: .all, now: date("2026-10-27")).count == 4,
      "Sparse all-history window")
let domain = GrowthSeries.yDomain([5.4, 5.4, .nan])
check(domain.lowerBound < 5.4 && domain.upperBound > 5.4, "Constant-series y scale")
check(GrowthSeries.yDomain([]) == 0...1, "Empty-series y scale")
var profile = GrowthProfile()
profile.sourceWeightUnit = .grams
check(profile.display(5400, metric: .weight) == 5400, "No conversion before units confirmed")
profile.unitsConfirmed = true
check(abs(profile.display(5400, metric: .weight) - 5.4) < 1e-10, "Grams to kilograms")
profile.displayWeightUnit = .grams
check(profile.display(5400, metric: .weight) == 5400, "Weight display in grams")
profile.sourceLengthUnit = .inches
check(profile.display(10, metric: .height) == 25.4, "Inches to centimeters")
check(GrowthWeightUnit.pounds.kilograms(1) == 0.45359237, "Exact pound conversion")
profile.showWHO = true
profile.referenceSex = .boys
check(profile.referenceBirthDate(birth: birth, calendar: calendar) == nil, "Age basis must be confirmed")
profile.chronologicalAgeConfirmed = true
check(profile.referenceBirthDate(birth: birth, calendar: calendar) == birth, "Explicit chronological age")
profile.useCorrectedAge = true
profile.dueDate = "2024-02-01"
check(profile.referenceBirthDate(birth: birth, calendar: calendar) == nil, "Due date must be documented")
profile.dueDateDocumented = true
check(profile.referenceBirthDate(birth: birth, calendar: calendar) == date("2024-02-01"), "Documented corrected age")
profile.dueDate = "2023-12-01"
check(profile.referenceBirthDate(birth: birth, calendar: calendar) == nil, "Due date cannot precede birth")
let suite = "GrowthCoreChecks.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
GrowthProfileStore.write(profile, childID: 1, defaults: defaults)
check(GrowthProfileStore.read(childID: 1, defaults: defaults) == profile, "Profile round trip")
check(GrowthProfileStore.read(childID: 2, defaults: defaults) == GrowthProfile(), "Separate children")
GrowthProfileStore.clear(defaults: defaults)
check(GrowthProfileStore.read(childID: 1, defaults: defaults) == GrowthProfile(), "No profile survives cache wipe")
print("Growth core: \(checks) checks passed, including 55,710 LMS comparisons across all six WHO tables.")
