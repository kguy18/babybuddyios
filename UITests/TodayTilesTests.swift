import XCTest

/// Settings ▸ Appearance ▸ Today tiles picks the tiles under TODAY on Home (#188).
final class TodayTilesTests: UITestCase {
    /// A Home tile by kind. Latest repeats the tiles' labels, so tiles carry an identifier.
    private func tile(_ kind: String) -> XCUIElement {
        app.descendants(matching: .any)["today-\(kind)"]
    }

    func testChosenTilesShowOnHome() {
        launch()
        expect(tile("tummyTime"))
        XCTAssertFalse(tile("pumping").exists)

        tap(tab("Settings"))
        tap(app.buttons.labeled("Today tiles, 4 on"))
        expect(app.navigationBars["Today Tiles"])
        toggle(app.switches["Pumping"], to: "1")
        toggle(app.switches["Tummy time"], to: "0")
        back(from: "Today Tiles")
        expect(app.buttons.labeled("Today tiles, 4 on"))

        tap(tab("Home"))
        XCTAssertTrue(expect(tile("pumping")).label.hasPrefix("Pumping, "))
        XCTAssertFalse(tile("tummyTime").exists)
        expect(tile("feeding"))
    }

    func testTileSwitchSitsBelowItsNameAtLargestText() {
        launch(["BB_START_TAB": "settings"], largestText: true)
        tap(app.buttons.labeled("Today tiles, 4 on"))
        expect(app.navigationBars["Today Tiles"])

        let name = expect(app.staticTexts["Feedings"])
        let control = expect(app.switches["Feedings"])
        XCTAssertGreaterThan(name.frame.width, name.frame.height, "Feedings should fit on one line")
        XCTAssertGreaterThanOrEqual(control.frame.minY, name.frame.maxY - 1)
        tap(control)
        back(from: "Today Tiles")
        expect(app.buttons.labeled("Today tiles, 3 on"))
    }

    /// With every tile off, Home leaves out the Today section.
    func testNoTilesHidesToday() {
        launch(["BB_START_TAB": "settings"])
        tap(app.buttons.labeled("Today tiles, 4 on"))
        expect(app.navigationBars["Today Tiles"])
        for name in ["Feedings", "Sleep", "Diapers", "Tummy time"] {
            toggle(app.switches[name], to: "0")
        }
        back(from: "Today Tiles")
        expect(app.buttons.labeled("Today tiles, 0 on"))
        tap(tab("Home"))
        expect(app.staticTexts["LATEST"])
        XCTAssertFalse(app.staticTexts["TODAY"].exists)
        XCTAssertFalse(tile("feeding").exists)
    }
}
