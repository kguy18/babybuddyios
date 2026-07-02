import XCTest
@testable import BabyBuddy

/// Covers the local 14-day free trial: activation, expiration, the one-shot no-restart guarantee,
/// `daysRemaining` math, the once-only "trial ended" report, and graceful handling of corrupt
/// `UserDefaults`. Uses an injected clock + an isolated suite so nothing touches real state and no
/// test has to wait 14 real days.
@MainActor
final class TrialManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let day: TimeInterval = 24 * 60 * 60

    override func setUp() {
        super.setUp()
        suiteName = "test.trial.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: Activation

    func testFreshManagerHasNoTrial() {
        let trial = TrialManager(defaults: defaults)
        XCTAssertFalse(trial.hasStartedTrial)
        XCTAssertFalse(trial.isTrialActive)
        XCTAssertFalse(trial.isTrialExpired)
        XCTAssertNil(trial.trialStartDate)
        XCTAssertEqual(trial.daysRemaining, 0)
    }

    func testStartTrialActivatesForFourteenDays() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let trial = TrialManager(defaults: defaults, now: { clock })

        trial.startTrial()

        XCTAssertTrue(trial.hasStartedTrial)
        XCTAssertTrue(trial.isTrialActive)
        XCTAssertFalse(trial.isTrialExpired)
        XCTAssertEqual(trial.daysRemaining, 14)
        XCTAssertEqual(trial.trialStartDate, clock)

        // Still active mid-window, with days counting down (rounded up).
        clock = clock.addingTimeInterval(13 * day)
        XCTAssertTrue(trial.isTrialActive)
        XCTAssertEqual(trial.daysRemaining, 1)
    }

    func testStartTrialPersistsAcrossManagers() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        TrialManager(defaults: defaults, now: { clock }).startTrial()

        // A second manager reading the same store sees the started trial.
        let reloaded = TrialManager(defaults: defaults, now: { clock })
        XCTAssertTrue(reloaded.hasStartedTrial)
        XCTAssertTrue(reloaded.isTrialActive)

        clock = clock.addingTimeInterval(2 * day)
        XCTAssertEqual(reloaded.daysRemaining, 12)
    }

    // MARK: Expiration

    func testTrialExpiresAfterFourteenDays() {
        var clock = Date(timeIntervalSince1970: 2_000_000)
        let trial = TrialManager(defaults: defaults, now: { clock })
        trial.startTrial()

        clock = clock.addingTimeInterval(14 * day + 1) // just past the window
        XCTAssertFalse(trial.isTrialActive)
        XCTAssertTrue(trial.isTrialExpired)
        XCTAssertEqual(trial.daysRemaining, 0)
        XCTAssertTrue(trial.hasStartedTrial) // still "started"
    }

    func testExpiredTrialCannotRestart() {
        var clock = Date(timeIntervalSince1970: 3_000_000)
        let trial = TrialManager(defaults: defaults, now: { clock })
        trial.startTrial()
        let originalStart = trial.trialStartDate

        clock = clock.addingTimeInterval(30 * day) // long expired
        XCTAssertTrue(trial.isTrialExpired)

        trial.startTrial() // must be a permanent no-op
        XCTAssertEqual(trial.trialStartDate, originalStart)
        XCTAssertFalse(trial.isTrialActive)
        XCTAssertTrue(trial.isTrialExpired)
    }

    func testStartTrialIsIdempotentWhileActive() {
        var clock = Date(timeIntervalSince1970: 4_000_000)
        let trial = TrialManager(defaults: defaults, now: { clock })
        trial.startTrial()
        let start = trial.trialStartDate

        clock = clock.addingTimeInterval(5 * day)
        trial.startTrial() // second call ignored
        XCTAssertEqual(trial.trialStartDate, start)
    }

    // MARK: Trial-ended reporting (fires once)

    func testTrialEndReportedExactlyOnce() {
        var clock = Date(timeIntervalSince1970: 5_000_000)
        let trial = TrialManager(defaults: defaults, now: { clock })
        trial.startTrial()

        // Not expired yet → nothing reported.
        trial.reportTrialEndIfNeeded()
        XCTAssertFalse(defaults.bool(forKey: "purchases.trialEndReported"))

        clock = clock.addingTimeInterval(15 * day)
        trial.reportTrialEndIfNeeded()
        XCTAssertTrue(defaults.bool(forKey: "purchases.trialEndReported"))

        // Idempotent: further calls don't crash and don't un-report.
        trial.reportTrialEndIfNeeded()
        XCTAssertTrue(defaults.bool(forKey: "purchases.trialEndReported"))
    }

    func testReportTrialEndNoOpWhenNeverStarted() {
        let trial = TrialManager(defaults: defaults)
        trial.reportTrialEndIfNeeded()
        XCTAssertFalse(defaults.bool(forKey: "purchases.trialEndReported"))
    }

    // MARK: Reset

    func testResetClearsAllTrialState() {
        var clock = Date(timeIntervalSince1970: 6_000_000)
        let trial = TrialManager(defaults: defaults, now: { clock })
        trial.startTrial()
        clock = clock.addingTimeInterval(20 * day)
        trial.reportTrialEndIfNeeded()

        trial.reset()

        XCTAssertFalse(trial.hasStartedTrial)
        XCTAssertNil(trial.trialStartDate)
        XCTAssertFalse(trial.isTrialActive)
        XCTAssertFalse(defaults.bool(forKey: "purchases.trialEndReported"))
        // A fresh trial can be started again after a reset (debug/test only).
        trial.startTrial()
        XCTAssertTrue(trial.isTrialActive)
    }

    // MARK: Corrupt UserDefaults (must not crash)

    func testCorruptStartDateDegradesGracefully() {
        // A string where a Date is expected, and garbage for the bool flag.
        defaults.set("not-a-date", forKey: "purchases.trialStartDate")
        defaults.set("garbage", forKey: "purchases.hasStartedTrial")

        let trial = TrialManager(defaults: defaults) // must not crash
        XCTAssertNil(trial.trialStartDate)
        XCTAssertFalse(trial.hasStartedTrial)
        XCTAssertFalse(trial.isTrialActive)
        XCTAssertFalse(trial.isTrialExpired)
        XCTAssertEqual(trial.daysRemaining, 0)

        // The manager is still usable afterwards.
        trial.startTrial()
        XCTAssertTrue(trial.isTrialActive)
    }

    func testStartedFlagWithMissingDateIsInertNotExploitable() {
        // "Started" is true but there's no valid start date — the degenerate corrupt case. It must
        // not crash, must not read as active/expired, and must not allow a restart.
        defaults.set(true, forKey: "purchases.hasStartedTrial")
        defaults.set("corrupt", forKey: "purchases.trialStartDate")

        let trial = TrialManager(defaults: defaults)
        XCTAssertTrue(trial.hasStartedTrial)
        XCTAssertNil(trial.trialStartDate)
        XCTAssertFalse(trial.isTrialActive)
        XCTAssertFalse(trial.isTrialExpired)
        XCTAssertEqual(trial.daysRemaining, 0)

        trial.startTrial() // guarded by hasStartedTrial → no-op, no crash
        XCTAssertNil(trial.trialStartDate)
    }
}
