import XCTest

/// The two local alerts the app schedules, from the Settings switch that turns them on to a tap on
/// the delivered banner. Tapping one while the app was in the background used to crash it (#116),
/// so these run the real round trip — Home, wait for the banner, tap it — rather than the deep link
/// it routes through.
///
/// Both alerts are compressed by a launch hook (`BB_TIMER_ALERT_SECONDS`, `BB_DOSE_ALERT_SECONDS`):
/// the shortest threshold Settings offers is 30 minutes, and the shortest dose interval four hours.
final class NotificationTests: UITestCase {
    /// The alerts live on their own screen behind a Settings row that reads their state; the
    /// per-activity thresholds only make sense while they're on, so they follow the switch (#116).
    /// Their rows are also how #118's medication reminders stayed separate from them.
    func testForgottenTimerAlertRows() {
        launch(["BB_START_TAB": "settings"])
        let rows = ["Feeding", "Sleep", "Tummy time", "Pumping"]

        // The Settings row is a link, not a switch, and says the alerts are off on a fresh install.
        XCTAssertFalse(app.switches["Forgotten timer alerts"].exists, "The switch is on the sub-screen")
        tap(app.buttons.labeled("Forgotten timer alerts, Off"))
        expect(app.navigationBars["Forgotten timer alerts"])

        let alerts = app.switches["Forgotten timer alerts"]
        expect(alerts)
        XCTAssertEqual(alerts.value as? String, "0", "Alerts are off on a fresh install")
        XCTAssertFalse(app.staticTexts["ALERT AFTER"].exists, "Thresholds showed while off")

        alerts.tap()
        allowNotificationsIfAsked() // turning them on is what asks for permission
        expect(app.staticTexts["ALERT AFTER"])
        for row in rows { expect(app.staticTexts[row]) }

        // Each row's menu holds the choices, and picking one redraws the row at once — it used
        // to hold the old value until the screen was reopened. Tummy time is the only activity
        // whose default threshold is an hour, so its menu button names itself. Its list runs
        // from 10 minutes to 4 hours; sleep's row (12h by default) still offers a day.
        tap(app.buttons["1h"])
        XCTAssertTrue(app.buttons["10m"].exists, "Ten minutes is offered for tummy time")
        XCTAssertEqual(app.buttons.matching(identifier: "12h").count, 1, "Only sleep's own row says 12h; the tummy menu doesn't offer it")
        tap(app.buttons["10m"])
        expect(app.buttons["10m"])
        expectGone(app.buttons["1h"])
        tap(app.buttons["10m"])
        tap(app.buttons["45m"])
        expect(app.buttons["45m"])
        expectGone(app.buttons["10m"])
        tap(app.buttons["12h"])
        expect(app.buttons["24h"])
        tap(app.buttons["24h"])
        expect(app.buttons["24h"])
        expectGone(app.buttons["12h"])

        alerts.tap()
        expectValue(alerts, "0")
        expectGone(app.staticTexts["ALERT AFTER"])

        // Back in Settings the row reads the switch's state — and on again, without leaving.
        tap(app.navigationBars.buttons.firstMatch)
        expect(app.buttons.labeled("Forgotten timer alerts, Off"))

        // A second visit shows the picks, not the values from before the first: the screen used
        // to keep the thresholds it was built with until the app was relaunched.
        tap(app.buttons.labeled("Forgotten timer alerts, Off"))
        expect(alerts)
        alerts.tap()
        expect(app.buttons["45m"])
        expect(app.buttons["24h"])
        alerts.tap()
        expectValue(alerts, "0")
        tap(app.navigationBars.buttons.firstMatch)
        expect(app.buttons.labeled("Forgotten timer alerts, Off"))

        // The medication switch is its own, and doesn't bring the threshold rows with it.
        let doses = app.switches["Medication reminders"]
        tap(doses)
        expectValue(doses, "1")
        for row in rows { XCTAssertFalse(app.staticTexts[row].exists, "\(row) came back with doses") }
    }

    /// Regression: #116 — a tapped alert routed into the app off the main actor, and the app
    /// crashed on its way back from the background. Fixed in #118. The tap shows the timer without
    /// stopping it: only Stop stops a timer (#146).
    func testForgottenTimerAlertTapShowsTheRunningTimer() {
        launch(["BB_TIMER_ALERT_SECONDS": "25"])
        allowNotificationsIfAsked() // the hook turns the alerts on, so the reset install asks

        // The seeded tummy-time timer is already past 25 s, so its alert may arrive right now as a
        // foreground banner — or not at all, since the clean-install reset clears pending
        // notifications and that can land after the first reconcile has scheduled this one. Either
        // way it's noise: it sits at the top of the screen, and the interruption monitor in `setUp`
        // swipes it away if it ever blocks a tap.
        //
        // A timer started now is the one whose alert can be made to arrive while the app is away.
        tap(app.buttons["Add"])
        tap(app.buttons["Start timer"])
        tap(app.buttons["Sleep"])
        tap(app.buttons["Start sleep timer"])
        expect(element(labeled: "Sleep running"))

        pressHome()
        tapNotification(containing: "Sleep timer still running")

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "The tap should bring the app back")
        expect(element(labeled: "Sleep running"))
        XCTAssertFalse(app.navigationBars["Stop Timer"].exists)
    }

    /// A tapped medication reminder logs the next dose, pre-filled from the last one (#118).
    func testMedicationReminderTapOpensPrefilledDose() {
        launch(["BB_DOSE_ALERT_SECONDS": "25"])
        allowNotificationsIfAsked()

        openEditor("Medication")
        let bar = expect(app.navigationBars["New Medication"])
        let name = app.textFields["Name"]
        name.tap()
        name.typeText("Tylenol")
        tap(app.buttons.labeled("None")) // "Next dose after"
        tap(app.buttons["4h"])
        tap(bar.buttons["Save"])
        expectGone(bar)

        pressHome()
        tapNotification(containing: "Tylenol: next dose OK")

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "The tap should bring the app back")
        expect(app.navigationBars["New Medication"]) // a new dose, not the old one reopened
        XCTAssertTrue(app.textFields.withValue("Tylenol").exists, "The name should carry over")
        XCTAssertTrue(app.buttons.labeled("4h").exists, "So should the interval")
    }

    // MARK: Helpers

    /// Taps through the system's notification prompt, which only the first test in a run sees:
    /// permission is granted per install, and the simulator is erased around the whole run, not
    /// around each test.
    /// An already-delivered alert, wherever it currently is: a banner while it's up, or its
    /// Notification Center row once it has expired.
    private func notification(containing text: String) -> XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Waits for an alert to arrive and opens the app from it.
    private func tapNotification(containing text: String) {
        let banner = notification(containing: text)
        if !banner.waitForExistence(timeout: 60) {
            // It may have come and gone while the app was away; Notification Center keeps it.
            openNotificationCenter()
            XCTAssertTrue(banner.waitForExistence(timeout: 10), "No notification mentioning “\(text)”")
        }
        banner.tap()
    }
}
