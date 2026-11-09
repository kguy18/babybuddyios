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

    /// History pages back a window at a time and stops at the child's birthday rather than asking
    /// the server forever (#17). Demo mode reveals a fixed historic set the same way a pull would.
    ///
    /// Filtered to notes first: the footer is the whole point of this test, and the demo child's
    /// thirty days of feedings, sleeps and changes would bury it hundreds of rows down. Notes are
    /// two rows, so the button stays on screen however far back the paging goes.
    func testLoadOlderActivityUntilItRunsOut() {
        launch(["BB_START_TAB": "timeline"])
        filterToNotes()
        let loadOlder = expect(app.buttons["Load older activity"])

        // Page back until the button goes, which is the horizon reaching the child's birthday. The
        // windows are 60 days each, so this is one iteration per two months of Maya's life.
        for _ in 0..<12 {
            // A short wait, not `exists`: mid-load the footer is a spinner instead of the button.
            guard loadOlder.waitForExistence(timeout: 3) else { break }
            loadOlder.tap()
        }
        expectGone(loadOlder)

        // And the history it fetched on the way: the oldest seeded note, 115 days back.
        expect(element(labeled: "Note, First real smile!"))
    }

    /// A search is worth keeping while you check something on Home — retyping it every time was
    /// what made the day drill-down (#24) annoying to use.
    func testSearchSurvivesADrillDown() {
        launch(["BB_START_TAB": "timeline"])
        let note = element(labeled: "Note, Looking out at the garden.")
        let search = app.searchFields.firstMatch
        tap(search)
        search.typeText("garden\n") // the keyboard would cover the tab bar
        expect(note)

        tap(tab("Home"))
        tap(expect(element(labeled: "Feedings, ")))
        back(from: "Feeding · Today")
        tap(tab("Timeline"))

        XCTAssertEqual(search.value as? String, "garden", "The search should survive the trip")
        expect(note)
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

    /// At the largest text a row's time goes under its title and a day's summary under the day:
    /// side by side, both broke mid-word or were cut off. The Filters sheet opens at full height,
    /// where at half height the date range was off the bottom.
    func testRowsDayHeadersAndFiltersAtTheLargestText() {
        launch(["BB_START_TAB": "timeline"], largestText: true)
        let today = expect(app.staticTexts["Today"])
        // "1 feed · 1 diaper", "3 feeds · 2h sleep", "2 events": the first one is today's.
        let summary = expect(app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' feed' OR "
            + "label CONTAINS ' diaper' OR label CONTAINS ' sleep' OR label CONTAINS ' event'")).firstMatch)
        XCTAssertGreaterThan(summary.frame.minY, today.frame.maxY - 1, "The summary should sit under the day")

        let row = expect(elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, night'").firstMatch)
        let title = expect(row.staticTexts["Feeding"])
        let time = expect(row.staticTexts.matching(NSPredicate(format: "label CONTAINS ':'")).firstMatch)
        XCTAssertGreaterThan(time.frame.minY, title.frame.maxY - 1, "The time should sit under the title")

        tap(app.buttons["Filters"])
        expect(app.navigationBars["Filters"])
        let to = expect(app.switches["To"])
        XCTAssertTrue(app.windows.firstMatch.frame.contains(to.frame), "The date range should be on screen")
    }

    /// At the largest text the empty search's Clear button scrolls clear of the keyboard: drawn
    /// over the list, it sat under it.
    func testNoResultsCanBeClearedAboveTheKeyboard() {
        launch(["BB_START_TAB": "timeline"], largestText: true)
        let feedings = elements("label BEGINSWITH 'Feeding, '")
        expect(feedings.firstMatch)
        let search = app.searchFields.firstMatch
        tap(search)
        search.typeText("zzqx")
        expect(app.keyboards.firstMatch)
        tap(app.buttons["Clear Search & Filters"])
        expect(feedings.firstMatch)
    }

    /// Narrows the timeline to notes, through the Filters sheet.
    private func filterToNotes() {
        tap(app.buttons["Filters"])
        let filters = expect(app.navigationBars["Filters"])
        tap(app.buttons.labeled("Type"))
        tap(app.buttons["Note"])
        tap(filters.buttons["Done"])
        expectGone(filters)
        expect(element(labeled: "Note, Looking out at the garden."))
    }
}
