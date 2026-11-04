import XCTest

final class ActivityForecastUITests: UITestCase {
    func testGermanRoutineAndSettingsStayLocalized() {
        launch(["BB_SEED_FORECAST": "1"], language: "de", locale: "de_DE")
        expect(app.staticTexts["Was kommt als Nächstes?"])
        expect(app.staticTexts["Nächste Mahlzeit"])
        tap(tab("Einstellungen"))
        let settings = app.buttons.labeled("Aktivitätsschätzungen")
        for _ in 0..<8 where !settings.isHittable { app.swipeUp() }
        tap(settings)
        expect(app.navigationBars["Aktivitätsschätzungen"])
        toggle(app.switches["forecast-enabled"], to: "0")
        tap(tab("Übersicht"))
        XCTAssertFalse(app.staticTexts["Was kommt als Nächstes?"].exists)
    }

    func testRegularRoutineShowsEstimateAndSettingCanHideIt() {
        launch(["BB_SEED_FORECAST": "1"])
        expect(app.staticTexts["What's next"])
        expect(app.staticTexts["Next feeding"])
        expect(app.staticTexts["Similar intervals"].firstMatch)
        tap(tab("Settings"))
        let settings = app.buttons.labeled("Activity estimates")
        for _ in 0..<8 where !settings.isHittable { app.swipeUp() }
        tap(settings)
        toggle(app.switches["forecast-enabled"], to: "0")
        tap(tab("Home"))
        XCTAssertFalse(app.staticTexts["What's next"].exists)
    }

    func testChildSwitchDoesNotReuseForecast() {
        launch(["BB_SEED_FORECAST": "1", "BB_SEED_SECOND_CHILD": "1"])
        expect(app.staticTexts["Similar intervals"].firstMatch)
        tap(app.buttons.labeled("Current child, Maya Guy"))
        tap(app.buttons["Leo Guy"])
        expect(app.staticTexts["Next feeding"])
        XCTAssertFalse(app.staticTexts["Similar intervals"].exists)
        expect(app.staticTexts["More similar entries across at least three days are needed."].firstMatch)
    }

    func testOffByDefault() {
        launch()
        XCTAssertFalse(app.staticTexts["What's next"].exists)
    }

    func testEstimateRemainsOnHomeAfterOpeningTheDayTimeline() {
        launch(["BB_SEED_FORECAST": "1"])
        expect(app.staticTexts["What's next"])
        tap(app.descendants(matching: .any)["today-feeding"])
        back(from: "Feeding · Today")
        expect(app.staticTexts["What's next"])
        expect(app.staticTexts["Similar intervals"].firstMatch)
    }
}
