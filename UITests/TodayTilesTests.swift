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

        tap(app.tabBars.buttons["Settings"])
        tap(app.buttons.labeled("Today tiles, 4 on"))
        let bar = expect(app.navigationBars["Today Tiles"])
        toggle(app.switches["Pumping"], to: "1")
        toggle(app.switches["Tummy time"], to: "0")
        tap(bar.buttons.firstMatch) // back
        expect(app.buttons.labeled("Today tiles, 4 on"))

        tap(app.tabBars.buttons["Home"])
        XCTAssertTrue(expect(tile("pumping")).label.hasPrefix("Pumping, "))
        XCTAssertFalse(tile("tummyTime").exists)
        expect(tile("feeding"))
    }

    /// With every tile off, Home leaves out the Today section.
    func testNoTilesHidesToday() {
        launch(["BB_START_TAB": "settings"])
        tap(app.buttons.labeled("Today tiles, 4 on"))
        let bar = expect(app.navigationBars["Today Tiles"])
        for name in ["Feedings", "Sleep", "Diapers", "Tummy time"] {
            toggle(app.switches[name], to: "0")
        }
        tap(bar.buttons.firstMatch)
        expect(app.buttons.labeled("Today tiles, 0 on"))
        tap(app.tabBars.buttons["Home"])
        expect(app.staticTexts["LATEST"])
        XCTAssertFalse(app.staticTexts["TODAY"].exists)
        XCTAssertFalse(tile("feeding").exists)
    }
}
