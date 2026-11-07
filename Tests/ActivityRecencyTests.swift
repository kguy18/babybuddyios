import XCTest
@testable import BabyBuddy

final class ActivityRecencyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_730_000_000)

    func testCompletedSessionsUseTheirEnd() {
        let start = now.addingTimeInterval(-5400), end = now.addingTimeInterval(-1800)
        for (kind, basis) in [("sleep", ActivityRecency.Basis.woke), ("feeding", .feedEnded)] {
            let time = ActivityRecency.event(kind: kind, timestamp: start, start: start, end: end, now: now)
            XCTAssertEqual(time.date, end)
            XCTAssertEqual(time.basis, basis)
            XCTAssertFalse(time.isRunning)
        }
    }

    func testMissingReversedAndFutureEndsExplicitlyFallBackToStart() {
        let start = now.addingTimeInterval(-1200)
        for end in [nil, start.addingTimeInterval(-1), now.addingTimeInterval(1)] as [Date?] {
            for (kind, basis) in [("sleep", ActivityRecency.Basis.sleepStarted), ("feeding", .feedStarted)] {
                let time = ActivityRecency.event(kind: kind, timestamp: start, start: start, end: end, now: now)
                XCTAssertEqual(time.date, start)
                XCTAssertEqual(time.basis, basis)
            }
        }
    }

    func testMissingStartDoesNotInventCompletion() {
        let fallback = now.addingTimeInterval(-600)
        let time = ActivityRecency.event(kind: "sleep", timestamp: fallback, start: nil, end: now, now: now)
        XCTAssertEqual(time.date, fallback)
        XCTAssertEqual(time.basis, .sleepStarted)
    }

    func testZeroLengthSessionCanBeComplete() {
        let time = ActivityRecency.event(kind: "feeding", timestamp: now, start: now, end: now, now: now)
        XCTAssertEqual(time.basis, .feedEnded)
        XCTAssertEqual(time.date, now)
    }

    func testOtherKindsRetainTheirCanonicalTimestamp() {
        for kind in ["change", "tummyTime", "pumping", "note", "weight"] {
            let time = ActivityRecency.event(kind: kind, timestamp: now, start: .distantPast,
                                             end: .distantPast, now: now)
            XCTAssertEqual(time.date, now)
            XCTAssertEqual(time.basis, .event)
            XCTAssertNil(time.rowLabel)
        }
    }

    func testRunningAndStoppedTimersAreDistinctFromSavedSessions() {
        let start = now.addingTimeInterval(-1200)
        for (kind, running, stopped) in [("sleep", ActivityRecency.Basis.sleeping, ActivityRecency.Basis.sleepStopped),
                                         ("feeding", .feeding, .feedStopped)] {
            let timer = ActivityRecency.timer(kind: kind, start: start, stoppedAt: nil, now: now)
            XCTAssertEqual(timer?.basis, running)
            XCTAssertEqual(timer?.isRunning, true)
            let frozen = ActivityRecency.timer(kind: kind, start: start, stoppedAt: now, now: now)
            XCTAssertEqual(frozen?.basis, stopped)
            XCTAssertEqual(frozen?.isRunning, false)
            XCTAssertEqual(frozen?.date, now)
        }
    }

    func testInvalidAndUnrelatedTimersAreIgnored() {
        XCTAssertNil(ActivityRecency.timer(kind: "sleep", start: now.addingTimeInterval(1), stoppedAt: nil, now: now))
        XCTAssertNil(ActivityRecency.timer(kind: "sleep", start: now, stoppedAt: now.addingTimeInterval(-1), now: now))
        XCTAssertNil(ActivityRecency.timer(kind: "sleep", start: now, stoppedAt: now.addingTimeInterval(1), now: now))
        XCTAssertNil(ActivityRecency.timer(kind: "pumping", start: now, stoppedAt: nil, now: now))
    }

    func testWidgetWordingForFinishedSessions() {
        XCTAssertEqual(ActivityRecency(date: now, basis: .feedEnded).widgetLabel, "Last fed")
        XCTAssertEqual(ActivityRecency(date: now, basis: .woke).widgetLabel, "Awake")
        XCTAssertEqual(ActivityRecency(date: now, basis: .woke).tileLabel, "Awake")
    }

    func testRunningTimerWordingNamesItsFixedStartTime() {
        let time = now.formatted(date: .omitted, time: .shortened)
        let sleeping = ActivityRecency(date: now, basis: .sleeping), feeding = ActivityRecency(date: now, basis: .feeding)
        XCTAssertEqual(sleeping.widgetLabel, "Sleeping")
        XCTAssertEqual(sleeping.tileLabel, "Sleeping since")
        XCTAssertEqual(sleeping.sinceText, "since \(time)")
        XCTAssertEqual(sleeping.spokenTime(), "Sleeping since \(time)")
        XCTAssertEqual(feeding.tileLabel, "Feeding since")
        XCTAssertEqual(feeding.spokenTime(), "Feeding since \(time)")
    }

    func testGermanTimeLabelsAreInTheMainCatalog() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let german = try XCTUnwrap(Bundle(path: path))
        for (key, text) in ["Awake": "Wach", "Last fed": "Zuletzt gefüttert", "Sleeping since": "Schläft seit"] {
            XCTAssertEqual(german.localizedString(forKey: key, value: nil, table: nil), text)
        }
        let woke = german.localizedString(forKey: "Woke %@", value: nil, table: nil)
        XCTAssertEqual(String(format: woke, "vor 30 Minuten"), "vor 30 Minuten aufgewacht")
        let since = german.localizedString(forKey: "Sleeping since %@", value: nil, table: nil)
        XCTAssertEqual(String(format: since, "13:10"), "Schläft seit 13:10")
    }
}
