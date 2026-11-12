import XCTest

/// Estimates on the Today tiles (a footer on the Feedings, Sleep, and Diapers tiles) and in What's
/// next below them, off by default.
/// `BB_SEED_FORECAST=1` turns them on and seeds a routine that makes all three ready at any hour.
final class ActivityForecastUITests: UITestCase {
    private func tile(_ kind: String) -> XCUIElement {
        app.descendants(matching: .any)["today-\(kind)"]
    }

    private func expectLabel(of element: XCUIElement, contains text: String, line: UInt = #line) {
        expect(element, line: line)
        expect(element, matching: NSPredicate(format: "label CONTAINS %@", text), timeout: 10,
               describedAs: "to mention \(text)", line: line)
    }

    /// Opens the estimates screen and returns its switch. A `Form` toggle's element is the whole
    /// row, so tapping it lands on the label: the real switch is nested at its trailing edge.
    private func estimatesSwitch(row: String) -> XCUIElement {
        let settings = app.buttons.labeled(row)
        for _ in 0..<8 where !settings.isHittable { app.swipeUp() }
        tap(settings)
        return app.switches["forecast-enabled"].switches.firstMatch
    }

    func testRegularRoutineShowsEstimatesAndSettingCanHideThem() {
        launch(["BB_SEED_FORECAST": "1"])
        expectLabel(of: tile("feeding"), contains: ", next around ")
        expectLabel(of: tile("sleep"), contains: ", nap around ")
        expectLabel(of: tile("change"), contains: ", next around ")
        XCTAssertFalse(expect(tile("tummyTime")).label.contains("around"))
        XCTAssertEqual(tile("change").frame.height, tile("tummyTime").frame.height, accuracy: 0.5,
                       "A tile without a footer matches the one beside it")

        tap(tab("Settings"))
        toggle(estimatesSwitch(row: "Activity estimates"), to: "0")
        tap(tab("Home"))
        XCTAssertFalse(expect(tile("feeding")).label.contains("around"))
    }

    func testRunningSleepTimerShowsAWakeUpEstimate() {
        launch(["BB_SEED_FORECAST": "1"])
        expectLabel(of: tile("sleep"), contains: ", nap around ")
        tap(app.buttons["Add"])
        tap(app.buttons["Start timer"])
        expect(app.navigationBars["Start Timer"])
        tap(app.buttons["Sleep"])
        tap(app.buttons["Start sleep timer"])
        expectLabel(of: tile("sleep"), contains: ", wakes around ")
    }

    func testGermanEstimatesAndSettingsStayLocalized() {
        launch(["BB_SEED_FORECAST": "1"], language: "de", locale: "de_DE")
        expectLabel(of: tile("feeding"), contains: ", nächste gegen ")
        expectLabel(of: tile("sleep"), contains: ", Nickerchen gegen ")
        tap(tab("Einstellungen"))
        let enabled = estimatesSwitch(row: "Aktivitätsschätzungen")
        expect(app.navigationBars["Aktivitätsschätzungen"])
        toggle(enabled, to: "0")
    }

    func testPortugueseEstimatesStayLocalized() {
        launch(["BB_SEED_FORECAST": "1"], language: "pt-BR", locale: "pt_BR")
        expectLabel(of: tile("feeding"), contains: ", próxima por volta de ")
        expectLabel(of: tile("sleep"), contains: ", soneca por volta de ")
    }

    func testChildSwitchDoesNotReuseEstimates() {
        launch(["BB_SEED_FORECAST": "1", "BB_SEED_SECOND_CHILD": "1"])
        expectLabel(of: tile("feeding"), contains: ", next around ")
        // A tap can land before the avatar's menu is ready; once in a suite run it opened nothing.
        // An open menu covers the avatar, so a slow one isn't tapped again.
        let avatar = app.buttons.labeled("Current child, Maya")
        let leo = app.buttons.labeled("Leo")
        tap(avatar)
        if !leo.waitForExistence(timeout: 3), avatar.isHittable { avatar.tap() }
        tap(leo)
        expect(app.buttons.labeled("Current child, Leo"))
        XCTAssertFalse(expect(tile("feeding")).label.contains("around"))
    }

    func testOffByDefault() {
        launch()
        XCTAssertFalse(expect(tile("feeding")).label.contains("around"))
        tap(tab("Settings"))
        expectValue(estimatesSwitch(row: "Activity estimates"), "0")
    }

    func testEstimateRemainsAfterOpeningTheDayTimeline() {
        launch(["BB_SEED_FORECAST": "1"])
        tap(expect(tile("feeding")))
        back(from: "Feeding · Today")
        expectLabel(of: tile("feeding"), contains: ", next around ")
    }

    // MARK: What's next

    private var whatsNext: XCUIElement { app.buttons["whats-next-toggle"] }
    private func row(_ kind: String) -> XCUIElement { app.descendants(matching: .any)["forecast-\(kind)"] }

    func testWhatsNextOpensWithEveryRowAndStaysOpen() {
        launch(["BB_SEED_FORECAST": "1"])
        expect(whatsNext)
        XCTAssertFalse(row("feeding").exists, "Closed on first turn-on")
        XCTAssertEqual(whatsNext.value as? String ?? "", "", "The tiles show the times, so the closed row adds none")

        tap(whatsNext)
        expectLabel(of: row("feeding"), contains: "Similar intervals")
        expect(row("nap"))
        expect(row("change"))
        expect(app.staticTexts.labeled("Based on logged routines"))

        tap(tab("Settings"))
        tap(tab("Home"))
        expect(row("feeding"))
        tap(whatsNext)
        expectGone(row("feeding"))
    }

    func testSettingsChooseWhereEstimatesShow() {
        launch(["BB_SEED_FORECAST": "1"])
        tap(tab("Settings"))
        // Tab switches below keep this screen pushed, so its switches stay reachable.
        let enabled = estimatesSwitch(row: "Activity estimates")
        let tiles = app.switches["forecast-tiles"].switches.firstMatch
        expectValue(tiles, "1")
        expectValue(app.switches["forecast-section"].switches.firstMatch, "1")
        expectValue(app.switches["forecast-widget"].switches.firstMatch, "1")

        toggle(tiles, to: "0")
        tap(tab("Home"))
        XCTAssertFalse(expect(tile("feeding")).label.contains("around"))
        expect(whatsNext, matching: NSPredicate(format: "value CONTAINS %@", " around "), timeout: 10,
               describedAs: "to show the soonest estimate")
        tap(whatsNext)
        expect(row("feeding"))

        tap(tab("Settings"))
        toggle(app.switches["forecast-section"].switches.firstMatch, to: "0")
        toggle(enabled, to: "0")
        expectGone(app.switches["forecast-tiles"])
        tap(tab("Home"))
        expect(tile("feeding"))
        XCTAssertFalse(whatsNext.exists)
    }

    func testWhatsNextHidesInSickMode() {
        launch(["BB_SEED_FORECAST": "1", "BB_SEED_SICK": "1"])
        allowNotificationsIfAsked()
        expect(app.buttons["End sick mode"])
        XCTAssertFalse(whatsNext.exists)
    }

    func testDisclaimerLivesInSettings() {
        launch()
        let disclaimer = "Based on logged routines"
        XCTAssertFalse(app.staticTexts.labeled(disclaimer).exists)
        tap(tab("Settings"))
        _ = estimatesSwitch(row: "Activity estimates")
        for _ in 0..<4 where !app.staticTexts.labeled(disclaimer).exists { app.swipeUp() }
        expect(app.staticTexts.labeled(disclaimer))
    }
}
