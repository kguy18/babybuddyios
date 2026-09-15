import XCTest

/// Every tab renders the seeded demo data — the canary for a crash or a blank screen.
final class SmokeTests: UITestCase {
    func testTabsRenderDemoData() {
        launch()

        // Home: the seeded running timer, and the day summary beneath it.
        expect(element(labeled: "Tummy time running"))
        XCTAssertTrue(app.buttons["Stop"].exists)
        XCTAssertTrue(app.staticTexts["TODAY"].exists)
        XCTAssertTrue(app.staticTexts["LATEST"].exists)

        tap(app.tabBars.buttons["Timeline"])
        expect(element(labeled: "Feeding, "))

        tap(app.tabBars.buttons["Trends"])
        for card in ["Sleep", "Feedings", "Diapers", "Tummy Time", "Pumping"] {
            expect(app.staticTexts[card])
        }

        tap(app.tabBars.buttons["Settings"])
        for section in ["SERVER", "NOTIFICATIONS", "QUICK LOG", "SUPPORT"] {
            expect(app.staticTexts[section])
        }
        XCTAssertTrue(app.buttons.labeled("Sign out").exists)
    }

    /// Every Trends card survives each period (#32, #114), and the picker says which is chosen.
    func testTrendsPeriodSwitch() {
        launch(["BB_START_TAB": "trends"])
        for period in ["7 days", "14 days", "30 days"] {
            let segment = app.buttons[period]
            tap(segment)
            XCTAssertTrue(segment.isSelected, "\(period) should read as selected")
            for card in ["Sleep", "Feedings", "Diapers", "Tummy Time", "Pumping"] {
                XCTAssertTrue(app.staticTexts[card].exists, "\(card) card missing at \(period)")
            }
        }
    }
}
