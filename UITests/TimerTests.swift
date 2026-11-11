import XCTest

/// Stopping the seeded "Tummy time" timer: every way out of the Stop Timer sheet.
final class TimerTests: UITestCase {
    /// Feeding needs details, so the sheet closes and the convert editor opens after it — a sheet
    /// presented while another is still dismissing is silently dropped.
    func testStopFeedingTimerConvertsInEditor() {
        launch(["BB_TOAST_SECONDS": "30"])
        tap(app.buttons["Stop"])
        expect(app.navigationBars["Stop Timer"])

        // Full height first: on iPhone Duo's short front display the half-height sheet's buttons
        // cover the tiles, and a tap on Feeding lands on "Log tummy time".
        expandSheet()
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

    func testStartTimerFitsTheLargestText() {
        launch(largestText: true)
        tap(app.buttons["Add"])
        tap(app.buttons["Start timer"])
        expect(app.navigationBars["Start Timer"])
        let scroll = app.scrollViews["screen-start-timer"]
        let feeding = expect(app.buttons["Feeding"])
        let sleep = expect(app.buttons["Sleep"])
        XCTAssertGreaterThan(sleep.frame.minY, feeding.frame.maxY, "Activities should have one row each")
        reveal(sleep, in: scroll)
        tap(sleep)
        let offset = app.buttons.labeled("Starts,")
        reveal(offset, in: scroll)
        tap(offset)
        tap(app.buttons["−30 min"])
        let start = app.buttons["Start sleep timer"]
        reveal(start, in: scroll)
        let untyped = app.buttons["Start without a type"]
        reveal(untyped, in: scroll)
        XCTAssertGreaterThan(start.frame.minY, app.buttons["Pumping"].frame.maxY,
                             "Start actions should follow the tiles in the scroll content")
        tap(start)
        expectGone(app.navigationBars["Start Timer"])
        expect(element(labeled: "Sleep running"))
    }

    func testStopTimerFitsTheLargestText() {
        let environment = ProcessInfo.processInfo.environment["BB_FOLD"] == "1" ? ["BB_FOLD": "1"] : [:]
        launch(environment, largestText: true)
        tap(app.buttons["Stop"])
        expect(app.navigationBars["Stop Timer"])
        let scroll = app.scrollViews["screen-stop-timer"]
        XCTAssertTrue(expect(app.staticTexts["stop-timer-activity"]).isHittable)
        let started = expect(app.staticTexts["Started"])
        let startTime = app.datePickers.firstMatch.buttons.firstMatch
        XCTAssertGreaterThan(startTime.frame.minY, started.frame.maxY,
                             "The start-time control should sit below its label at accessibility sizes")
        let feeding = app.buttons["Feeding"]
        reveal(feeding, in: scroll)
        tap(feeding)
        let log = app.buttons["Log feeding…"]
        reveal(log, in: scroll)
        let discard = app.buttons["Discard timer"]
        reveal(discard, in: scroll)
        let resume = expect(app.buttons["Resume timer"])
        let restart = expect(app.buttons["Restart from now"])
        XCTAssertGreaterThan(restart.frame.minY, resume.frame.maxY)
        XCTAssertGreaterThan(discard.frame.minY, restart.frame.maxY)
        for button in [log, resume, restart, discard] {
            revealAction(button, in: scroll)
            XCTAssertTrue(button.isHittable, "\(button.label) should be reachable by scrolling")
            let window = app.windows.firstMatch.frame
            if !window.contains(button.frame) {
                let tree = XCTAttachment(string: app.debugDescription)
                tree.name = "Stop timer action frames"
                add(tree)
            }
            XCTAssertTrue(window.contains(button.frame),
                          "\(button.label) frame \(button.frame) should fit inside window \(window), scroll \(scroll.frame)")
        }
        tap(resume)
        expectGone(app.navigationBars["Stop Timer"])
        expect(element(labeled: "Tummy time running"))
    }

    /// Hittable can include a button clipped by the bottom of a short Duo display.
    private func revealAction(_ button: XCUIElement, in scroll: XCUIElement) {
        for _ in 0..<10 {
            let viewport = scroll.frame.intersection(app.windows.firstMatch.frame)
            if button.exists && button.isHittable {
                let frame = button.frame
                if frame.minY >= viewport.minY && frame.maxY <= viewport.maxY { return }
                if frame.minY < viewport.minY {
                    scroll.swipeDown()
                    continue
                }
            }
            scroll.swipeUp()
        }
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
