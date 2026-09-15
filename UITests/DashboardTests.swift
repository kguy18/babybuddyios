import XCTest

/// Home's day summary and where it leads.
final class DashboardTests: UITestCase {
    /// A TODAY tile opens that kind's day (#24), whose own "+" logs into it (#40) — and the status
    /// widget's tile link lands on the same screen (#45).
    func testTodayTileDrillDown() {
        launch(["BB_TOAST_SECONDS": "30"])
        let tile = expect(element(labeled: "Feedings, "))
        let count = Int(tile.label.components(separatedBy: ", ").last ?? "") ?? -1

        tap(tile)
        let day = expect(app.navigationBars["Feeding · Today"])
        let rows = elements("label BEGINSWITH 'Feeding, '")
        XCTAssertEqual(rows.count, count, "The day should list what the tile counted")

        tap(app.buttons["Add Feeding"])
        let editor = expect(app.navigationBars["New Feeding"])
        tap(editor.buttons["Save"])
        let toast = expect(app.otherElements["Logged Feeding"])
        XCTAssertEqual(rows.count, count + 1)
        tap(app.buttons["Undo"])
        expectGone(toast)
        XCTAssertEqual(rows.count, count)

        tap(day.buttons.firstMatch) // back
        expect(element(labeled: "Feedings, "))
        app.open(URL(string: "babybuddy://day/feeding")!)
        expect(app.navigationBars["Feeding · Today"])
    }
}
