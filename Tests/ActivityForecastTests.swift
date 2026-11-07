import XCTest
@testable import BabyBuddy

final class ActivityForecastTests: XCTestCase {
    private var engine: ForecastEngine {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return ForecastEngine(calendar: calendar)
    }
    private let base = ISO8601DateFormatter().date(from: "2026-06-15T00:00:00Z")!
    private func time(_ day: Int, _ hour: Double) -> Date { base.addingTimeInterval(Double(day) * 86400 + hour * 3600) }
    private func feed(_ day: Int, _ hour: Double, child: Int = 1) -> ForecastRecord {
        ForecastRecord(id: UUID(), childID: child, kind: .feeding, start: time(day, hour), end: time(day, hour + 0.25))
    }
    private func history() -> [ForecastRecord] {
        (-7..<0).flatMap { day in [9.0, 12, 15, 18, 21].map { feed(day, $0) } } + [feed(0, 9)]
    }
    private func sleepHistory() -> [ForecastRecord] {
        var records: [ForecastRecord] = []
        for day in -7..<0 {
            records.append(ForecastRecord(id: UUID(), childID: 1, kind: .sleep,
                                          start: time(day, -2), end: time(day, 7), nap: false))
            for hour in [9.0, 12, 15] {
                records.append(ForecastRecord(id: UUID(), childID: 1, kind: .sleep,
                                              start: time(day, hour), end: time(day, hour + 1), nap: true))
            }
        }
        records.append(ForecastRecord(id: UUID(), childID: 1, kind: .sleep,
                                      start: time(0, -2), end: time(0, 7), nap: false))
        return records
    }
    private func snapshot(_ records: [ForecastRecord], now: Date? = nil, timers: [ForecastTimer] = []) -> ForecastSnapshot {
        let now = now ?? time(0, 10)
        return engine.snapshot(records: records, timers: timers, childID: 1, lastSync: now, now: now)
    }

    func testFeedingUsesStartToStartAndRecentSimilarIntervals() throws {
        let cue = try XCTUnwrap(snapshot(history()).cues.first { $0.kind == .feeding })
        XCTAssertEqual(cue.state, .ready)
        let estimate = try XCTUnwrap(cue.estimate)
        XCTAssertEqual(estimate.anchor, time(0, 9))
        XCTAssertEqual(estimate.medianSeconds, 3 * 3600)
        XCTAssertEqual(estimate.observations.count, 10)
        XCTAssertGreaterThanOrEqual(estimate.distinctDays, 3)
        XCTAssertEqual(estimate.window.midpoint, time(0, 12))
    }

    func testNapUsesSleepEndRatherThanSleepStart() throws {
        let cue = try XCTUnwrap(snapshot(sleepHistory(), now: time(0, 8)).cues.first { $0.kind == .nap })
        XCTAssertEqual(cue.state, .ready)
        XCTAssertEqual(cue.estimate?.anchor, time(0, 7))
        XCTAssertEqual(cue.estimate?.window.midpoint, time(0, 9))
    }

    func testRunningSleepEstimatesWakeInsteadOfAnotherNap() {
        let timer = ForecastTimer(childID: 1, kind: .sleep, start: time(0, 9))
        let result = snapshot(sleepHistory(), now: time(0, 9.25), timers: [timer])
        XCTAssertEqual(result.cues.first { $0.kind == .nap }?.state, .inProgress)
        XCTAssertEqual(result.cues.first { $0.kind == .wake }?.estimate?.window.midpoint, time(0, 10))
    }

    func testNoEstimateFromSparseOrSingleDayHistory() {
        XCTAssertEqual(snapshot([feed(0, 9)]).cues.first?.state, .insufficient)
        XCTAssertEqual(snapshot((0..<8).map { feed(0, Double($0)) }).cues.first?.state, .insufficient)
    }

    func testElapsedEstimateDoesNotRollForwardOrBecomeOverdue() {
        let result = snapshot(history(), now: time(0, 15)).cues.first!
        XCTAssertEqual(result.state, .elapsed)
        XCTAssertTrue(snapshot(history(), now: time(0, 15)).ready.isEmpty)
    }

    func testStaleAndMissingSyncSuppressAllNumbers() {
        for lastSync in [nil, time(-1, 10), time(1, 10)] as [Date?] {
            let result = engine.snapshot(records: history(), timers: [], childID: 1, lastSync: lastSync, now: time(0, 10))
            XCTAssertTrue(result.ready.isEmpty)
            XCTAssertTrue(result.cues.allSatisfy { $0.state == .stale })
        }
    }

    func testOtherChildrenDeletedRecordsAndExactDuplicatesDoNotChangeEstimate() {
        let expected = snapshot(history()).cues.first?.estimate
        var deleted = feed(0, 9.5)
        deleted.excluded = true
        let records = history()
        let result = snapshot(records + records + [feed(0, 9.7, child: 2), deleted]).cues.first?.estimate
        XCTAssertEqual(result, expected)
    }

    func testIncompleteOrConflictedLatestRecordSuppressesEstimate() {
        var incomplete = feed(0, 9.5)
        incomplete.end = nil
        XCTAssertEqual(snapshot(history() + [incomplete]).cues.first?.state, .invalid)
        incomplete = feed(0, 9.5)
        incomplete.conflicted = true
        XCTAssertEqual(snapshot(history() + [incomplete]).cues.first?.state, .invalid)
        incomplete.end = time(0, 12)
        incomplete.conflicted = false
        XCTAssertEqual(snapshot(history() + [incomplete]).cues.first?.state, .invalid)
    }

    func testRunningAndStoppedTimersSuppressCorrespondingEstimate() {
        for stopped in [false, true] {
            let timer = ForecastTimer(childID: 1, kind: .feeding, start: time(0, 9.5), stopped: stopped)
            XCTAssertEqual(snapshot(history(), timers: [timer]).cues.first?.state, .inProgress)
        }
        let timer = ForecastTimer(childID: 1, kind: nil, start: time(0, 9.5))
        XCTAssertTrue(snapshot(history(), timers: [timer]).cues.allSatisfy { $0.state == .inProgress })
    }

    /// Three naps at about 9, 12:15, and 3:15, then bed at 7:30 PM. `day` 0 holds what is logged so far.
    private func threeNapDays(today naps: [Double]) -> [ForecastRecord] {
        func sleep(_ day: Int, _ start: Double, _ end: Double, nap: Bool) -> ForecastRecord {
            ForecastRecord(id: UUID(), childID: 1, kind: .sleep, start: time(day, start), end: time(day, end), nap: nap)
        }
        var records: [ForecastRecord] = []
        for day in -7..<0 {
            records.append(sleep(day, 19.5, 31, nap: false)) // 7:30 PM to 7:00 AM
            records += [9.0, 12.25, 15.25].map { sleep(day + 1, $0, $0 + 1, nap: true) }
        }
        return records.filter { $0.start < time(0, 0) } + naps.map { sleep(0, $0, $0 + 1, nap: true) }
    }

    func testNoNapIsPredictedAfterTheDaysLastNap() {
        let records = threeNapDays(today: [9, 12.25, 15.25])
        let result = snapshot(records, now: time(0, 16.5))
        XCTAssertEqual(result.cues.first { $0.kind == .nap }?.state, .insufficient)
        XCTAssertNil(result.tileEstimate(.sleep))
    }

    func testMidMorningNapEstimateStillWorksInAThreeNapRoutine() throws {
        let cue = try XCTUnwrap(snapshot(threeNapDays(today: [9]), now: time(0, 10.5)).cues.first { $0.kind == .nap })
        XCTAssertEqual(cue.state, .ready)
        XCTAssertEqual(cue.estimate?.anchor, time(0, 10))
    }

    func testOldConflictOnlyDropsItsOwnEvidence() {
        var records = history()
        records[1].conflicted = true
        let feeding = snapshot(records).cues.first
        XCTAssertEqual(feeding?.state, .ready)
        XCTAssertEqual(feeding?.estimate?.window.midpoint, time(0, 12))
        XCTAssertFalse(feeding?.estimate?.observations.isEmpty ?? true)

        var sleeps = sleepHistory()
        sleeps[0].conflicted = true
        XCTAssertEqual(snapshot(sleeps, now: time(0, 8)).cues.first { $0.kind == .nap }?.state, .ready)
        let timer = ForecastTimer(childID: 1, kind: .sleep, start: time(0, 9))
        XCTAssertEqual(snapshot(sleeps, now: time(0, 9.25), timers: [timer]).cues.first { $0.kind == .wake }?.state, .ready)
    }

    func testConflictedLatestSleepSuppressesNapAndWake() {
        var sleeps = sleepHistory()
        sleeps[sleeps.count - 1].conflicted = true
        XCTAssertEqual(snapshot(sleeps, now: time(0, 8)).cues.first { $0.kind == .nap }?.state, .invalid)
        let timer = ForecastTimer(childID: 1, kind: .sleep, start: time(0, 9))
        XCTAssertEqual(snapshot(sleeps, now: time(0, 9.25), timers: [timer]).cues.first { $0.kind == .wake }?.state, .invalid)
    }

    func testWindowPastMidnightShowsTimesOnly() {
        let now = time(0, 23.5)
        let window = ForecastWindow(start: time(1, 0.9), end: time(1, 1.5))
        XCTAssertEqual(ForecastFormat.window(window, now: now),
                       "\(ForecastFormat.time(window.start, now: now))\u{2013}\(ForecastFormat.time(window.end, now: now))")
        XCTAssertEqual(ForecastFormat.time(window.start, now: now),
                       window.start.formatted(date: .omitted, time: .shortened))
    }

    func testTimeMoreThanADayAwayKeepsItsDate() {
        let later = time(2, 9)
        XCTAssertEqual(ForecastFormat.time(later, now: time(0, 9)), later.formatted(date: .numeric, time: .shortened))
    }

    func testTileEstimateMapsKindsAndShowsOnlyReadyCues() {
        let sleeping = snapshot(sleepHistory(), now: time(0, 9.25),
                                timers: [ForecastTimer(childID: 1, kind: .sleep, start: time(0, 9))])
        XCTAssertEqual(sleeping.tileEstimate(.sleep)?.kind, .wake)
        XCTAssertEqual(snapshot(sleepHistory(), now: time(0, 8)).tileEstimate(.sleep)?.kind, .nap)
        XCTAssertEqual(snapshot(history()).tileEstimate(.feeding)?.kind, .feeding)
        XCTAssertNil(snapshot(history()).tileEstimate(.change))
        XCTAssertNil(snapshot(history(), now: time(0, 15)).tileEstimate(.feeding), "An elapsed cue shows nothing")
    }

    func testQuantilesAreDeterministic() {
        XCTAssertEqual(ForecastEngine.quantile([4, 1, 3, 2], fraction: 0.5), 2.5)
        XCTAssertEqual(ForecastEngine.quantile([], fraction: 0.5), 0)
        XCTAssertEqual(ForecastEngine.quantile([2], fraction: 0.1), 2)
    }

    func testWidgetExpiryHonorsWindowAndFreshnessCutoffs() {
        let value = snapshot(history())
        XCTAssertEqual(value.expires(lastSync: time(0, 10)), time(0, 10.25))
        XCTAssertEqual(value.expires(lastSync: time(0, 8.01)), time(0, 10.01))
        let nearEnd = snapshot(history(), now: time(0, 12.2))
        XCTAssertEqual(nearEnd.expires(lastSync: time(0, 12.2)), nearEnd.ready.first?.window.end)
    }

    func testIrregularIntervalsAreHidden() {
        let records = (-7..<0).flatMap { day in [feed(day, 9), feed(day, day.isMultiple(of: 2) ? 9.1 : 14.9)] } + [feed(0, 9)]
        XCTAssertEqual(snapshot(records).cues.first?.state, .irregular)
    }

    func testDiaperCueDescribesLoggingIntervals() {
        let records = history().map { ForecastRecord(id: $0.id, childID: 1, kind: .change, start: $0.start) }
        let cue = snapshot(records).cues.first { $0.kind == .change }
        XCTAssertEqual(cue?.state, .ready)
        XCTAssertEqual(cue?.estimate?.window.midpoint, time(0, 12))
    }

    func testNightSleepDoesNotBecomeAnObservedNap() {
        let records = sleepHistory().map { record -> ForecastRecord in
            var record = record
            record.nap = false
            return record
        }
        XCTAssertEqual(snapshot(records, now: time(0, 8)).cues.first { $0.kind == .nap }?.state, .insufficient)
    }

    func testOldHistoryDoesNotGiveFalseEvidence() {
        let records = history().map { record -> ForecastRecord in
            var record = record
            record = ForecastRecord(id: record.id, childID: 1, kind: .feeding,
                                    start: record.start.addingTimeInterval(-30 * 86400), end: record.end?.addingTimeInterval(-30 * 86400))
            return record
        }
        XCTAssertEqual(snapshot(records).cues.first?.state, .insufficient)
    }
}
