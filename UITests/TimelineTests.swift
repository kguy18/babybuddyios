import XCTest

/// Finding and changing history on the Timeline tab. Repeat and its undo live in LoggingTests.
final class TimelineTests: UITestCase {
    // #18
    func testSearchAndFilters() {
        launch(["BB_START_TAB": "timeline"])
        let feedings = elements("label BEGINSWITH 'Feeding, '")
        let changes = elements("label BEGINSWITH 'Diaper Change, '")
        expect(feedings.firstMatch)

        let search = app.searchFields.firstMatch
        tap(search)
        search.typeText("garden") // the seeded note's text
        expect(element(labeled: "Note, Looking out at the garden."))
        XCTAssertEqual(feedings.count, 0)

        tap(search.buttons["Clear text"])
        search.typeText("zzqx")
        expect(app.staticTexts["No Results"])
        tap(app.buttons["Clear Search & Filters"])
        expect(feedings.firstMatch)
        tap(app.navigationBars["Timeline"].buttons["Close"]) // an active search hides the toolbar

        tap(app.buttons["Filters"])
        let filters = expect(app.navigationBars["Filters"])
        tap(app.buttons.labeled("Type"))
        tap(app.buttons["Feeding"])
        tap(filters.buttons["Done"])
        expectGone(filters)
        expect(feedings.firstMatch)
        XCTAssertEqual(changes.count, 0, "Only feedings should pass the type filter")

        tap(app.buttons["Filters"])
        tap(app.buttons["Clear Filters"])
        tap(app.navigationBars["Filters"].buttons["Done"])
        expect(changes.firstMatch)
    }

    // #12
    func testSwipeToEditAndDelete() {
        launch(["BB_START_TAB": "timeline"])
        let row = elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, night'").firstMatch

        // A short drag shows the actions; a full swipe would run Delete.
        expect(row).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))
        tap(app.buttons["Edit"])
        let editor = expect(app.navigationBars["Edit Feeding"])
        tap(editor.buttons["Cancel"])
        expectGone(editor)

        // Delete asks nothing: the row just goes.
        expect(row).swipeLeft()
        let delete = app.buttons["Delete"]
        if delete.waitForExistence(timeout: 2) { delete.tap() } // unless the full swipe ran it
        expectGone(row)
    }
}
