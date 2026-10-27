import XCTest

final class ActivityForecastUITests: UITestCase {
    func testRegularRoutineShowsEstimateAndSettingCanHideIt() {
        launch(["BB_SEED_FORECAST": "1"])
        expect(app.staticTexts["What's next"])
        expect(app.staticTexts["Next feeding"])
        expect(app.staticTexts["Similar intervals"].firstMatch)
        tap(app.tabBars.buttons["Settings"])
        let settings = app.buttons.labeled("Activity estimates")
        for _ in 0..<8 where !settings.isHittable { app.swipeUp() }
        tap(settings)
        toggle(app.switches["forecast-enabled"], to: "0")
        tap(app.tabBars.buttons["Home"])
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
}
