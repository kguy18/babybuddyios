import XCTest

/// Stopping the seeded "Tummy time" timer: every way out of the Stop Timer sheet.
final class TimerTests: UITestCase {
    /// Feeding needs details, so the sheet closes and the convert editor opens after it — a sheet
    /// presented while another is still dismissing is silently dropped.
    func testStopFeedingTimerConvertsInEditor() {
        launch(["BB_TOAST_SECONDS": "30"])
        tap(app.buttons["Stop"])
        expect(app.navigationBars["Stop Timer"])

        tap(app.buttons["Feeding"])
        tap(app.buttons["Log feeding…"])

        let editor = expect(app.navigationBars["Convert to Feeding"])
        tap(editor.buttons["Save"])
        expectGone(editor)
        expect(app.otherElements["Logged Feeding"])
        expect(app.buttons.labeled("Start a timer"))
        XCTAssertFalse(app.buttons["Stop"].exists)
    }

    func testStopTimerOneTapLogAndDiscard() {
        launch(["BB_TOAST_SECONDS": "30"])
        let tummy = expect(element(labeled: "Tummy time, "))
        var before = tummy.label

        // Tummy time is preselected from the timer's name and logs in one tap.
        tap(app.buttons["Stop"])
        tap(app.buttons["Log tummy time"])
        expect(app.otherElements["Logged Tummy Time"])
        expect(app.buttons.labeled("Start a timer"))
        XCTAssertNotEqual(tummy.label, before, "The logged tummy time should count toward today")

        // Discarding (on a fresh install, so the timer is back) files nothing.
        launch(["BB_TOAST_SECONDS": "30"])
        before = expect(tummy).label
        tap(app.buttons["Stop"])
        tap(app.buttons["Discard timer"])
        expect(app.buttons.labeled("Start a timer"))
        XCTAssertEqual(tummy.label, before)
        XCTAssertFalse(app.otherElements["Logged Tummy Time"].exists)
    }

    /// Stop freezes the timer (#146): the sheet's duration holds still, closing the sheet leaves the
    /// timer stopped on Home, and Resume sets it running again.
    func testStopFreezesAndResumeRestarts() {
        launch()
        tap(app.buttons["Stop"])
        let duration = expect(element(labeled: "Stopped after "))
        let frozen = duration.label
        sleep(3)
        XCTAssertEqual(duration.label, frozen, "The duration kept counting after Stop")

        tap(app.buttons["Close"])
        let card = expect(element(labeled: "Tummy time stopped after "))
        XCTAssertFalse(app.buttons["Stop"].exists)

        tap(app.buttons["Log timer"])
        XCTAssertEqual(expect(element(labeled: "Stopped after ")).label, frozen, "Reopened, still the Stop tap's number")
        tap(app.buttons["Resume timer"])
        expectGone(card)
        expect(element(labeled: "Tummy time running"))
        expect(app.buttons["Stop"])
    }

    /// Timers run side by side: a typed one names itself after its activity, an untyped one doesn't.
    func testStartTypedAndUntypedTimers() {
        launch()
        let startSheet = app.navigationBars["Start Timer"]

        tap(app.buttons["Add"])
        tap(app.buttons["Start timer"])
        expect(startSheet)
        tap(app.buttons["Sleep"])
        tap(app.buttons["Start sleep timer"])
        expectGone(startSheet)
        expect(element(labeled: "Sleep running"))

        tap(app.buttons["Add"])
        tap(app.buttons["Start timer"])
        expect(startSheet)
        tap(app.buttons["Feeding"])
        tap(app.buttons["Start without a type"]) // offered once a type is picked
        expectGone(startSheet)
        expect(element(labeled: "Timer running"))
        XCTAssertTrue(element(labeled: "Tummy time running").exists)
        XCTAssertTrue(element(labeled: "Sleep running").exists)
    }

    /// A nap noticed late: the timer starts 30 minutes back, so it has already run 30 minutes.
    func testBackdatedStart() {
        launch()
        tap(app.buttons["Stop"])
        tap(app.buttons["Discard timer"]) // one timer, so one Stop button below
        tap(app.buttons["Add"])
        tap(app.buttons["Start timer"])
        tap(app.buttons["Sleep"])
        tap(app.buttons["−30 min"])
        tap(app.buttons["Start sleep timer"])

        tap(app.buttons["Stop"])
        expect(app.staticTexts.labeled("30:"))
    }

    /// Restart puts the seeded 8-minute timer back to zero, and it keeps running.
    func testRestartFromNow() {
        launch()
        tap(app.buttons["Stop"])
        expect(app.staticTexts.labeled("8:"))
        tap(app.buttons["Restart from now"])
        expectGone(app.navigationBars["Stop Timer"])

        tap(app.buttons["Stop"])
        expect(app.staticTexts.labeled("0:0"))
    }
}
