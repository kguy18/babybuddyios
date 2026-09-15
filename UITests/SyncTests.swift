import XCTest

/// The offline queue and conflicts, from seeded demo state — demo mode never reaches a server, so
/// these check the screens and their wiring; the sync rules themselves have unit tests.
final class SyncTests: UITestCase {
    /// Pending Changes lists what's queued, asks before discarding, and discarding a queued delete
    /// brings the record back (#23, #99, #102).
    func testPendingChanges() {
        launch(["BB_START_TAB": "timeline", "BB_SEED_PENDING": "1"])
        // Narrow the timeline to the two "night" records so both rows are on screen.
        let search = app.searchFields.firstMatch
        tap(search)
        search.typeText("night\n") // Return keeps the text but drops the keyboard off the tab bar
        let sleep = elements("label BEGINSWITH 'Sleep, ' AND label CONTAINS 'tags: night'").firstMatch
        expect(elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, night'").firstMatch)
        XCTAssertFalse(sleep.exists, "A queued delete hides its record")

        tap(app.tabBars.buttons["Settings"])
        tap(app.buttons.labeled("Pending changes"))
        let sheet = expect(app.navigationBars["Pending Changes"])

        let deleted = app.staticTexts["Deleted Sleep"]
        expect(deleted).swipeLeft()
        tap(app.buttons["Discard"])
        let discard = expect(app.alerts["Discard this change?"])
        tap(discard.buttons["Cancel"])
        expectGone(discard)
        XCTAssertTrue(deleted.exists, "Cancel should keep the change")

        deleted.swipeLeft()
        tap(app.buttons["Discard"])
        tap(app.alerts["Discard this change?"].buttons["Discard"])
        expectGone(deleted)

        // A timer conversion whose server timer is gone can still be filed, without the timer.
        tap(app.buttons["Create without timer"])
        tap(app.alerts["Create without the timer?"].buttons["Create"])
        expectGone(app.buttons["Create without timer"])

        tap(sheet.buttons["Done"])
        expectGone(sheet)
        tap(app.tabBars.buttons["Timeline"])
        expect(sleep)
    }

    /// A refused record says so on its row, and its editor links straight to Pending Changes (#107).
    func testBlockedRowOpensPendingChanges() {
        launch(["BB_START_TAB": "timeline", "BB_SEED_PENDING": "1"])
        tap(elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'sync needs attention'").firstMatch)
        expect(app.navigationBars["Edit Feeding"])

        tap(app.buttons.labeled("Couldn’t sync."))
        let sheet = expect(app.navigationBars["Pending Changes"])
        XCTAssertTrue(app.staticTexts["Needs attention"].exists)
        tap(sheet.buttons["Done"])
        expectGone(sheet)
        XCTAssertTrue(app.navigationBars["Edit Feeding"].exists, "Pending Changes opens over the editor")
    }

    // #16
    func testResolveConflictByMerge() {
        launch(["BB_START_TAB": "settings", "BB_SEED_CONFLICT": "1"])
        tap(app.buttons.labeled("Conflicts"))
        expect(app.navigationBars["Conflicts"])
        tap(app.buttons.labeled("Feeding"))

        expect(app.navigationBars["Resolve Conflict"])
        XCTAssertTrue(app.buttons["Merge"].isSelected, "Merge is the default when fields differ")
        tap(app.buttons["All server"])
        tap(app.buttons["Save merged feeding"])

        expect(app.staticTexts["No Conflicts"])
        tap(app.navigationBars["Conflicts"].buttons.firstMatch) // back
        expect(app.staticTexts["All clear"])
    }
}
