import XCTest

/// Home's day summary and where it leads.
final class DashboardTests: UITestCase {
    func testLatestExplainsSessionEndWhileTimelineRetainsItsStartTime() {
        launch()
        // On an open display, Home also contains start-based rows in its Today pane.
        let sleep = expect(elements("label BEGINSWITH 'Sleep, ' AND label CONTAINS 'Woke'").firstMatch)
        expect(elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'Feeding finished'").firstMatch)
        tap(sleep)
        expect(app.navigationBars["Timeline"])
        let rows = elements("label BEGINSWITH 'Sleep, '")
        XCTAssertGreaterThan(rows.count, 0)
        for row in rows.allElementsBoundByIndex {
            XCTAssertFalse(row.label.contains("Woke"), "Timeline rows retain their original start-time meaning")
        }
    }

    /// A TODAY tile opens that kind's day (#24), whose own "+" logs into it (#40) — and the status
    /// widget's tile link lands on the same screen (#45).
    func testTodayTileDrillDown() {
        launch(["BB_TOAST_SECONDS": "30"])
        let tile = expect(element(labeled: "Feedings, "))
        let count = Int(tile.label.components(separatedBy: ", ").last ?? "") ?? -1

        tap(tile)
        expect(app.navigationBars["Feeding · Today"])
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

        back(from: "Feeding · Today")
        expect(element(labeled: "Feedings, "))
        app.open(URL(string: "babybuddy://day/feeding")!)
        expect(app.navigationBars["Feeding · Today"])
    }

    /// Latest shows the newest record of every kind, occasional ones included: the seeded note and
    /// weigh-in, and a dose as soon as it is logged.
    func testLatestShowsEveryKind() {
        launch()
        expect(element(labeled: "Note, Looking out at the garden."))
        expect(element(labeled: "Weight, 5.4"))
        XCTAssertFalse(element(labeled: "Medication, ").exists)

        openEditor("Medication")
        let bar = expect(app.navigationBars["New Medication"])
        let name = app.textFields["Name"]
        name.tap()
        name.typeText("Tylenol")
        tap(bar.buttons["Save"])
        expectGone(bar)
        expect(element(labeled: "Medication, Tylenol"))
    }

    /// A Latest row opens the Timeline filtered to its kind, not the record's editor: every
    /// cached sleep, grouped by day, and nothing else.
    func testLatestRowOpensFilteredTimeline() {
        launch()
        tap(element(labeled: "Sleep, "))
        expect(app.navigationBars["Timeline"])
        XCTAssertFalse(app.navigationBars["Edit Sleep"].exists)
        XCTAssertGreaterThan(elements("label BEGINSWITH 'Sleep, '").count, 1)
        XCTAssertEqual(elements("label BEGINSWITH 'Feeding, '").count, 0, "Only sleep passes the filter")

        tap(app.buttons["Filters"])
        tap(app.buttons["Clear Filters"])
        tap(app.navigationBars["Filters"].buttons["Done"])
        expect(elements("label BEGINSWITH 'Feeding, '").firstMatch)
    }

    /// The three support surfaces, each forced onto the Dashboard by `BB_NUDGE` rather than by
    /// aging an install a week (#59). Every one of them takes no for an answer, and the milestone's
    /// ask opens the supporter sheet.
    func testSupportNudgeSurfaces() {
        let gentle = app.staticTexts["Enjoying Baby\u{00a0}Buddy\u{00a0}Companion?"]
        launch(["BB_NUDGE": "gentle"])
        expect(gentle)
        tap(app.buttons["Maybe later"])
        expectGone(gentle)

        launch(["BB_NUDGE": "milestone"])
        expect(app.staticTexts["MILESTONE"]) // the eyebrow is uppercased in the design system
        expect(elements("label CONTAINS 'activities logged'").firstMatch)
        tap(app.buttons["Become a Supporter"])
        expect(app.staticTexts["Purchases aren't available in this build."])

        launch(["BB_NUDGE": "banner"])
        let banner = element(labeled: "Free for everyone. If the app helps")
        expect(banner)
        tap(app.buttons["Dismiss"])
        expectGone(banner)
    }
}
