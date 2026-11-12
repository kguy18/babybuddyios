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

        tap(tab("Settings"))
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
        tap(tab("Timeline"))
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
        back(from: "Conflicts")
        expect(app.staticTexts["All clear"])
    }

    func testPendingChangesAtLargestText() {
        launch(["BB_START_TAB": "settings", "BB_SEED_PENDING": "1", "BB_OPEN_PENDING": "1"], largestText: true)
        expect(app.navigationBars["Pending Changes"])
        let title = expect(app.staticTexts["Added Pumping"])
        let time = expect(app.staticTexts["queue-time-Added Pumping"])
        XCTAssertGreaterThanOrEqual(time.frame.minY, title.frame.maxY - 1,
                                    "The timestamp should sit below the title")
        XCTAssertEqual(time.frame.minX, title.frame.minX, accuracy: 1,
                       "The timestamp should align with the title")

        let create = app.buttons["Create without timer"]
        for _ in 0..<8 {
            if create.exists && create.isHittable { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        tap(create)
        let prompt = expect(app.alerts["Create without the timer?"])
        tap(prompt.buttons["Cancel"])
        expectGone(prompt)
        XCTAssertTrue(create.exists, "Cancel should keep the queued timer conversion")
    }

    func testConflictResolutionAtLargestText() {
        launch(["BB_START_TAB": "settings", "BB_SEED_CONFLICT": "1"], largestText: true)
        tap(app.buttons.labeled("Conflicts"))
        expect(app.navigationBars["Conflicts"])
        let row = expect(app.buttons.labeled("Feeding"))
        XCTAssertTrue(row.label.contains("Changed on the server and on this device"))
        XCTAssertGreaterThan(row.frame.height, 100, "The inbox explanation should wrap")
        tap(row)
        expect(app.navigationBars["Resolve Conflict"])
        let mine = expect(app.buttons["Keep mine"])
        let server = expect(app.buttons["Keep server"])
        let merge = expect(app.buttons["Merge"])
        XCTAssertGreaterThanOrEqual(server.frame.minY, mine.frame.maxY - 1)
        XCTAssertGreaterThanOrEqual(merge.frame.minY, server.frame.maxY - 1)
        tap(mine)
        XCTAssertTrue(mine.isSelected)
        tap(server)
        XCTAssertTrue(server.isSelected)
        tap(merge)
        XCTAssertTrue(merge.isSelected)

        let mineTime = app.staticTexts["Mine"]
        let serverTime = app.staticTexts["Server"]
        app.scrollViews.firstMatch.swipeUp()
        expect(mineTime)
        expect(serverTime)
        XCTAssertGreaterThan(serverTime.frame.minY, mineTime.frame.maxY - 1,
                             "The Mine and Server times should stack")

        let localAmount = app.buttons.labeled("Amount, Mine,")
        let serverAmount = app.buttons.labeled("Amount, Server,")
        for _ in 0..<5 {
            if serverAmount.exists && serverAmount.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        expect(localAmount)
        expect(serverAmount)
        XCTAssertGreaterThanOrEqual(serverAmount.frame.minY, localAmount.frame.maxY - 1,
                                    "The field choices should stack")
        tap(app.buttons["All server"])
        XCTAssertTrue(serverAmount.isSelected)
        XCTAssertFalse(localAmount.isSelected)
        let save = app.buttons["Save merged feeding"]
        for _ in 0..<8 {
            if save.exists && save.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        tap(save)
        expect(app.staticTexts["No Conflicts"])
    }

}
