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

    func testTypeMenuFiltersAtLargestText() {
        launch(["BB_START_TAB": "timeline"], largestText: true)
        tap(app.buttons["Filters"])
        let filters = expect(app.navigationBars["Filters"])
        tap(app.buttons.labeled("Type"))
        let feeding = expect(app.buttons["Feeding"])
        attachScreen("timeline-type-compact-axxxl")
        tap(feeding)
        tap(filters.buttons["Done"])
        expect(element(labeled: "Feeding, "))
        XCTAssertEqual(elements("label BEGINSWITH 'Diaper Change, '").count, 0)
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
        // Demo data is relative to launch time, so which days show, and what each holds, moves
        // with the clock: just after midnight Today has one record or none. Take the first day.
        let summaries = NSPredicate(format: "label CONTAINS ' feed' OR label CONTAINS ' diaper' "
            + "OR label CONTAINS ' sleep' OR label CONTAINS ' event'")
        let day = expect(app.cells.containing(summaries).firstMatch)
        let header = day.staticTexts.element(boundBy: 0)
        let summary = day.staticTexts.matching(summaries).firstMatch
        XCTAssertNotEqual(header.label, summary.label, "The day's first text should be its name")
        XCTAssertGreaterThan(summary.frame.minY, header.frame.maxY - 1, "The summary should sit under the day")

        // The first row with a time on it, whatever kind it is: "Weight, 5.4, 12:00 AM".
        let row = expect(app.cells.buttons.matching(NSPredicate(format: "label MATCHES '.*[0-9]:[0-9][0-9].*'"))
            .firstMatch)
        let title = row.staticTexts.element(boundBy: 0)
        let time = expect(row.staticTexts.matching(NSPredicate(format: "label MATCHES '.*[0-9]:[0-9][0-9].*'"))
            .firstMatch)
        XCTAssertGreaterThan(time.frame.minY, title.frame.maxY - 1, "The time should sit under the title")

        tap(app.buttons["Filters"])
        expect(app.navigationBars["Filters"])
        let to = expect(app.switches["To"])
        XCTAssertTrue(app.windows.firstMatch.frame.contains(to.frame), "The date range should be on screen")
    }

    func testNoResultsCanBeClearedAboveTheKeyboard() {
        launch(["BB_START_TAB": "timeline"], largestText: true)
        checkEmptySearchWithKeyboard(app.searchFields.firstMatch)
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

extension UITestCase {
    /// Searches for nothing, then scrolls the empty result until "Clear Search & Filters" shows
    /// above the keyboard, and taps it. On an open iPhone Duo at the largest text only its top
    /// fits between the pane's header and the keyboard, so that is what has to show.
    func checkEmptySearchWithKeyboard(_ search: XCUIElement) {
        tap(search)
        search.typeText("zzqx")
        let keyboard = expect(app.keyboards.firstMatch)
        expect(app.staticTexts["No Results"])
        let clear = expect(app.buttons["Clear Search & Filters"])
        let results = app.scrollViews.containing(.button, identifier: "Clear Search & Filters").firstMatch
        let resultsTop = expect(results).frame.minY
        // On iPhone Duo the keyboard's frame leaves out its 44-point suggestions bar.
        let keyboardTop = keyboard.frame.minY - (hasRail ? 44 : 0)
        func shows() -> Bool { clear.frame.minY >= resultsTop && clear.frame.minY + 30 <= keyboardTop }
        for _ in 0..<8 where !shows() {
            // From the top of the results: a swipe starts at their centre, which the keyboard
            // covers on iPhone Duo.
            let from = results.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: 20))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -50)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        attachSickSettingsScreen("timeline-empty-search")
        XCTAssertTrue(keyboard.exists, "The keyboard should stay open while scrolling")
        XCTAssertTrue(shows(), "Clear Search & Filters should scroll above the keyboard")
        clear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 15)).tap()
        expectGone(app.staticTexts["No Results"])
    }
}
