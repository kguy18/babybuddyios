import XCTest
@testable import BabyBuddy

final class GrowthSeriesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
    private func date(_ raw: String) -> Date { GrowthDate.parse(raw, calendar: calendar)! }
    private func sample(_ raw: String, value: Double = 5, child: Int = 1,
                        metric: GrowthMetric = .weight, excluded: Bool = false) -> GrowthSample {
        GrowthSample(id: UUID(), childID: child, metric: metric, date: date(raw), value: value, excluded: excluded)
    }

    func testSparseHistoryRetainsActualReadingsOnly() {
        let input = [sample("2026-10-27", value: 5.4), sample("2026-08-01", value: 4.5),
                     sample("2026-09-01", value: 5.1)]
        let result = GrowthSeries(calendar: calendar).samples(input, childID: 1, metric: .weight,
                                                            period: .all, now: date("2026-10-27"))
        XCTAssertEqual(result.map(\.value), [4.5, 5.1, 5.4])
        XCTAssertEqual(result.count, 3) // No fake zero-filled or averaged days.
    }

    func testChildKindWindowAndDeletionAreRespected() {
        let input = [sample("2026-09-28"), sample("2026-09-27"), sample("2026-10-27"),
                     sample("2026-10-28"), sample("2026-10-26", child: 2),
                     sample("2026-10-26", metric: .height), sample("2026-10-26", excluded: true),
                     sample("2026-10-26", value: .nan), sample("2026-10-26", value: .infinity),
                     sample("2026-10-26", value: 0), sample("2026-10-26", value: -1)]
        let result = GrowthSeries(calendar: calendar).samples(input, childID: 1, metric: .weight,
                                                            period: .month, now: date("2026-10-27"))
        XCTAssertEqual(result.map(\.date), [date("2026-09-28"), date("2026-10-27")])
    }

    func testSameDayReadingsAreNotDiscarded() {
        let input = [sample("2026-10-27", value: 5), sample("2026-10-27", value: 5.1)]
        let result = GrowthSeries(calendar: calendar).samples(input, childID: 1, metric: .weight,
                                                            period: .all, now: date("2026-10-27"))
        XCTAssertEqual(Set(result.map(\.id)), Set(input.map(\.id)))
    }

    func testDateOnlyDoesNotMoveIntoPreviousDayInUS() {
        var pacific = calendar
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let parsed = GrowthDate.parse("2026-03-08", calendar: pacific)!
        XCTAssertEqual(pacific.component(.day, from: parsed), 8)
        XCTAssertEqual(GrowthDate.string(parsed, calendar: pacific), "2026-03-08")
    }

    func testDatesAreStrictEvenWithNonGregorianUserCalendar() {
        XCTAssertNil(GrowthDate.parse("2026-02-30", calendar: calendar))
        XCTAssertNil(GrowthDate.parse("2026-1-01", calendar: calendar))
        XCTAssertNil(GrowthDate.parse("2026-01-01T00:00:00Z", calendar: calendar))
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        XCTAssertEqual(GrowthDate.parse("2026-10-27", calendar: buddhist), date("2026-10-27"))
    }

    func testAgeCountsCalendarDaysAcrossDSTAndLeapYear() {
        XCTAssertEqual(GrowthDate.ageDays(birth: date("2026-03-28"), date: date("2026-03-30"), calendar: calendar), 2)
        XCTAssertEqual(GrowthDate.ageDays(birth: date("2024-02-28"), date: date("2024-03-01"), calendar: calendar), 2)
    }

    func testSinglePointAndEmptyDomainsAreNonzero() {
        XCTAssertEqual(GrowthSeries.yDomain([]), 0...1)
        let domain = GrowthSeries.yDomain([5.4, 5.4, .nan])
        XCTAssertLessThan(domain.lowerBound, 5.4)
        XCTAssertGreaterThan(domain.upperBound, 5.4)
        let x = GrowthSeries(calendar: calendar).xDomain([sample("2026-10-27")], period: .all,
                                                       now: date("2026-10-27"))
        XCTAssertGreaterThan(x.upperBound, x.lowerBound)
    }

    func testUnitsMustBeConfirmedBeforeConversion() {
        var profile = GrowthProfile()
        profile.sourceWeightUnit = .grams
        XCTAssertEqual(profile.display(5400, metric: .weight), 5400)
        profile.unitsConfirmed = true
        XCTAssertEqual(profile.display(5400, metric: .weight), 5.4, accuracy: 1e-10)
        profile.displayWeightUnit = .grams
        XCTAssertEqual(profile.display(5400, metric: .weight), 5400, accuracy: 1e-10)
        profile.sourceWeightUnit = .pounds
        profile.displayWeightUnit = .kilograms
        XCTAssertEqual(profile.display(1, metric: .weight), 0.45359237, accuracy: 1e-10)
        profile.sourceLengthUnit = .inches
        XCTAssertEqual(profile.display(10, metric: .height), 25.4, accuracy: 1e-10)
        XCTAssertEqual(profile.display(10, metric: .headCircumference), 25.4, accuracy: 1e-10)
    }

    func testWHOAgeRequiresExplicitData() {
        let birth = date("2026-01-01")
        var profile = GrowthProfile()
        XCTAssertNil(profile.referenceBirthDate(birth: birth, calendar: calendar))
        profile.unitsConfirmed = true
        profile.showWHO = true
        profile.referenceSex = .boys
        XCTAssertNil(profile.referenceBirthDate(birth: birth, calendar: calendar))
        profile.chronologicalAgeConfirmed = true
        XCTAssertEqual(profile.referenceBirthDate(birth: birth, calendar: calendar), birth)
        XCTAssertNil(profile.referenceBirthDate(birth: nil, calendar: calendar))
    }

    func testCorrectedAgeRequiresDocumentedValidDueDate() {
        let birth = date("2026-01-01")
        var profile = GrowthProfile()
        profile.unitsConfirmed = true
        profile.showWHO = true
        profile.referenceSex = .girls
        profile.useCorrectedAge = true
        profile.dueDate = "2026-02-01"
        XCTAssertNil(profile.referenceBirthDate(birth: birth, calendar: calendar))
        profile.dueDateDocumented = true
        let reference = profile.referenceBirthDate(birth: birth, calendar: calendar)!
        XCTAssertEqual(reference, date("2026-02-01"))
        XCTAssertEqual(GrowthDate.ageDays(birth: reference, date: date("2026-02-03"), calendar: calendar), 2)
        profile.dueDate = "2025-12-31"
        XCTAssertNil(profile.referenceBirthDate(birth: birth, calendar: calendar))
    }

    func testProfilesAreSeparateAndClearOnSignOut() {
        let suite = "GrowthTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var profile = GrowthProfile()
        profile.dueDate = "2026-02-01"
        GrowthProfileStore.write(profile, childID: 1, defaults: defaults)
        XCTAssertEqual(GrowthProfileStore.read(childID: 1, defaults: defaults), profile)
        XCTAssertEqual(GrowthProfileStore.read(childID: 2, defaults: defaults), GrowthProfile())
        defaults.set(true, forKey: "unrelated")
        GrowthProfileStore.clear(defaults: defaults)
        XCTAssertEqual(GrowthProfileStore.read(childID: 1, defaults: defaults), GrowthProfile())
        XCTAssertTrue(defaults.bool(forKey: "unrelated"))
    }
}
