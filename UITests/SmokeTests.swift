import XCTest

/// Every tab renders the seeded demo data — the canary for a crash or a blank screen — plus the
/// two sweeps that belong to no one screen: the lock and the accessibility audit.
final class SmokeTests: UITestCase {
    func testTabsRenderDemoData() {
        launch()

        // Home: the seeded running timer, and the day summary beneath it.
        expect(element(labeled: "Tummy time running"))
        XCTAssertTrue(app.buttons["Stop"].exists)
        XCTAssertTrue(app.staticTexts["TODAY"].exists)
        XCTAssertTrue(app.staticTexts["LATEST"].exists)

        tap(tab("Timeline"))
        expect(element(labeled: "Feeding, "))

        tap(tab("Trends"))
        for card in ["Sleep", "Feedings", "Diapers", "Tummy Time", "Pumping"] {
            expect(app.staticTexts[card])
        }

        tap(tab("Settings"))
        for section in ["SUPPORT THE APP", "SERVER", "NOTIFICATIONS", "QUICK LOG", "FEEDBACK"] {
            expect(app.staticTexts[section])
        }
        XCTAssertTrue(app.buttons.labeled("Sign out").exists)
        // The build number sits at the foot of Settings, where a bug report's screenshot finds it.
        XCTAssertTrue(app.staticTexts.labeled("Version 1.").exists)
    }

    /// Someone updating from a release older than the card itself has no version recorded, and
    /// 1.1.0 build 1 took that for a fresh install: the first What's New card reached nobody. A
    /// plain demo launch must still show none — every other test here would trip over it.
    func testUpdateFromBeforeTheCardShowsWhatsNew() {
        launch(["BB_WHATSNEW_UPGRADE": "1"])

        expect(app.staticTexts["What's New"])
        XCTAssertTrue(app.staticTexts.labeled("Version ").exists)
        tap(app.buttons["Continue"])
        expect(element(labeled: "Tummy time running"))
        XCTAssertFalse(app.staticTexts["What's New"].exists)
    }

    /// A full-screen cover presents above the lock, so a locked launch holds the card back until
    /// the unlock rather than putting it in front of Face ID.
    func testWhatsNewWaitsBehindTheLock() {
        launch(["BB_WHATSNEW_UPGRADE": "1", "BB_LOCK": "1"])

        expect(element(labeled: "Baby Buddy is locked"))
        XCTAssertFalse(app.staticTexts["What's New"].waitForExistence(timeout: 3),
                       "The What's New card came up over the lock screen")
    }

    /// The Face ID gate has to shut the app away from both hands and VoiceOver (#33). Nobody
    /// answers the automatic biometric prompt, so the lock stays up — which is the state to test.
    func testLockIsAModalBarrier() {
        launch(["BB_LOCK": "1"])

        // The lock has to be an accessibility *container* carrying `.isModal`, which is what keeps
        // VoiceOver inside it; XCUITest surfaces such a container as an Alert, the same way the
        // sign-out card reads since #120. Without it the trait lands on nothing and a screen reader
        // walks straight out into the Dashboard the lock is covering.
        let barrier = expect(app.alerts.firstMatch)
        XCTAssertTrue(barrier.staticTexts["Baby Buddy is locked"].exists)
        XCTAssertTrue(barrier.buttons["Unlock"].exists)

        // Touches stop at it too. (The tab bar stays in the raw element tree either way — the modal
        // trait steers VoiceOver's traversal, it doesn't prune the hierarchy — so this taps where
        // the tab bar sits rather than asking for the button.)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.94)).tap()
        XCTAssertFalse(app.navigationBars["Timeline"].waitForExistence(timeout: 3),
                       "A tap got through the lock")
        expect(element(labeled: "Baby Buddy is locked"))
    }

    /// XCTest's own accessibility audit on the four tabs and the editor — the sweep that catches
    /// what no assertion here would think to look for (#33, #59). See ``audit()`` for the
    /// categories it runs and the ones the app already fails everywhere.
    func testAccessibilityAudit() throws {
        launch()
        try audit()

        for name in ["Timeline", "Trends", "Settings"] {
            tap(tab(name))
            expect(app.navigationBars[name])
            try audit()
        }

        tap(tab("Home"))
        openEditor("Feeding")
        expect(app.navigationBars["New Feeding"])
        try audit()
    }

    /// The audit, minus the categories the app already fails everywhere, so the sweep is about new
    /// findings rather than the backlog. What's excluded today, and why it isn't a test problem:
    ///
    /// - **contrast**: the muted captions on the tinted cards sit under the ratio — mostly
    ///   "nearly passed", with the relative times ("45 minutes ago") failing outright.
    /// - **dynamicType**: sizes are pinned through `BBFont`, so every row reports it.
    /// - **textClipped**: the Server row truncates a long host.
    /// - **hitRegion**: the Settings menu buttons ("30 min") are 18pt tall.
    /// - **sufficientElementDescription**: decorative `Image(systemName:)` glyphs read as their
    ///   symbol names ("clock.arrow.circlepath") instead of being hidden.
    ///
    /// All five are worth fixing — they're palette, type-scale and `.accessibilityHidden` decisions
    /// across the design system, not something a test PR should quietly change. What stays strict:
    /// undetected elements, wrong traits, missing actions and broken containers — the class of bug
    /// #120 fixed on the sign-out card.
    private func audit() throws {
        try app.performAccessibilityAudit(for: .all.subtracting(
            [.contrast, .dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]))
    }

    func testTrendsExactValuesAndTapSelection() {
        launch(["BB_START_TAB": "trends"])
        let values = expect(app.buttons["sleep-values"])
        let chart = expect(app.descendants(matching: .any)["sleep-chart"])
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expect(app.descendants(matching: .any)["sleep-selected-value"])
        tap(values)
        expect(app.navigationBars["Chart values"])
        XCTAssertEqual(app.cells.count, 7)
        let firstWeekValue = expect(app.cells.firstMatch.staticTexts.firstMatch).label
        tap(app.buttons["Done"])
        expectGone(app.navigationBars["Chart values"])
        tap(app.buttons.labeled("14 days"))
        tap(app.buttons["sleep-values"])
        expect(app.navigationBars["Chart values"])
        XCTAssertNotEqual(expect(app.cells.firstMatch.staticTexts.firstMatch).label, firstWeekValue,
                          "The list follows the selected window")
    }

    func testGermanChartValues() {
        launch(["BB_START_TAB": "trends"], language: "de", locale: "de_DE")
        let values = expect(app.buttons["sleep-values"])
        XCTAssertEqual(values.label, "Werte anzeigen")
        tap(values)
        expect(app.navigationBars["Diagrammwerte"])
        expect(app.buttons["Fertig"])
        XCTAssertEqual(app.cells.count, 7)
    }

    /// Every Trends card survives each period (#32, #114), and the picker says which is chosen.
    func testTrendsPeriodSwitch() {
        launch(["BB_START_TAB": "trends"])
        for period in ["7 days", "14 days", "30 days"] {
            let segment = app.buttons[period]
            tap(segment)
            XCTAssertTrue(segment.isSelected, "\(period) should read as selected")
            for card in ["Sleep", "Feedings", "Diapers", "Tummy Time", "Pumping", "Temperature"] {
                XCTAssertTrue(app.staticTexts[card].exists, "\(card) card missing at \(period)")
            }
        }
    }

    /// The sick spell as one picture (#79): the temperature card's peak, the fever line it's read
    /// against, and a tally of each medicine marked on it. `BB_SEED_SICK=1` seeds a day and a half
    /// of fever stored in °F, on a phone the en_US launch locale puts in °F too.
    func testTrendsTemperatureCard() throws {
        launch(["BB_START_TAB": "trends", "BB_SEED_SICK": "1"])
        allowNotificationsIfAsked()
        expect(app.staticTexts["Temperature"])
        expect(app.staticTexts["Peak 102.8°F"])
        expect(app.staticTexts["Fever line at 100.4°F"])
        for (medicine, doses) in [("Acetaminophen", 4), ("Ibuprofen", 2)] {
            expect(elements("label BEGINSWITH '\(medicine)' AND label CONTAINS '\(doses) doses'")
                .firstMatch)
        }
        // The one screen in the suite whose audit sees a chart with marks on it: eleven readings
        // and six doses, each of which has to carry its own label and value.
        try audit()
    }
}
