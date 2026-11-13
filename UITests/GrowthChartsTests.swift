import XCTest

final class GrowthChartsTests: UITestCase {
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<14 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Growth element never became visible")
    }

    func testGrowthCardsDetailsAndConfirmedUnits() {
        launch(["BB_START_TAB": "trends", "BB_SEED_GROWTH": "1"])
        let settings = app.buttons["growth-settings"]
        reveal(settings)
        tap(settings)
        toggle(app.switches["growth-units-confirmed"].switches.firstMatch, to: "1")
        back(from: "Growth settings")

        let weight = app.buttons["growth-details-weight"]
        reveal(weight)
        tap(weight)
        expect(app.navigationBars["Weight"])
        expect(app.staticTexts["5.3 kg"])
        expect(app.staticTexts["4.8 kg"])
        back(from: "Weight")

        let height = app.buttons["growth-details-height"]
        reveal(height)
        tap(height)
        expect(app.navigationBars["Length / height"])
        expect(app.staticTexts["62 cm"])
        back(from: "Length / height")

        let head = app.buttons["growth-details-headCircumference"]
        reveal(head)
        tap(head)
        expect(app.navigationBars["Head circumference"])
        expect(app.staticTexts["41 cm"])
    }

    func testSparsePeriodAndEmptyState() {
        launch(["BB_START_TAB": "trends"])
        let weight = app.buttons["growth-details-weight"]
        reveal(weight)
        tap(weight)
        expect(app.navigationBars["Weight"])
        expect(app.staticTexts["Recorded measurements"])
        back(from: "Weight")
        let height = app.buttons["growth-details-height"]
        reveal(height)
        tap(height)
        expect(app.staticTexts["No measurements in this period"])
    }

    func testPeriodSwitchHidesOlderMeasurements() {
        launch(["BB_START_TAB": "trends", "BB_SEED_GROWTH": "1"])
        let settings = app.buttons["growth-settings"]
        reveal(settings)
        tap(app.buttons["Growth time period: 30 days"])
        let weight = app.buttons["growth-details-weight"]
        reveal(weight)
        tap(weight)
        expect(app.staticTexts["5.3"])
        XCTAssertFalse(app.staticTexts["4.8"].exists)
        XCTAssertFalse(app.staticTexts["4.2"].exists)
    }

    func testFeatureUsesGermanSystemLanguage() {
        launch(["BB_START_TAB": "trends", "BB_SEED_GROWTH": "1"], language: "de", locale: "de_DE")
        let settings = app.buttons["growth-settings"]
        reveal(settings)
        expect(app.staticTexts["Wachstum"])
        tap(settings)
        expect(app.navigationBars["Wachstumseinstellungen"])
        expect(app.switches["Ich habe die gespeicherten Einheiten geprüft"])
    }

    func testSwitchingChildrenDoesNotShowAnotherChildsGrowth() {
        launch(["BB_START_TAB": "trends", "BB_SEED_GROWTH": "1", "BB_SEED_SECOND_CHILD": "1"])
        tap(app.buttons.labeled("Current child, Maya Rivers"))
        tap(app.buttons["Leo Rivers"])
        let weight = app.buttons["growth-details-weight"]
        reveal(weight)
        tap(weight)
        expect(app.navigationBars["Weight"])
        expect(app.staticTexts["No measurements in this period"])
        XCTAssertFalse(app.staticTexts["5.3"].exists)
    }
}
