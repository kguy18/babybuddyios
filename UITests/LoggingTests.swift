import XCTest

/// Logging from Home: the chained sheets, the editor's save rules, and the undo toast.
final class LoggingTests: UITestCase {
    /// Undo actually undoes on each screen that hosts the toast (#115), and never opens the row under
    /// it. It does not guard the toast's placement: moved back onto the root `TabView`, where real
    /// touches fall through on iOS 26, XCUITest's synthesized taps still reach it and this passes.
    func testUndoToastTakesTaps() {
        launch(["BB_TOAST_SECONDS": "30"])

        // Home: log through the editor.
        let diapers = expect(element(labeled: "Diapers, "))
        let before = diapers.label
        openEditor("Diaper")
        expect(app.navigationBars["New Diaper Change"])
        tap(app.buttons["Save Diaper Change"])

        var toast = expect(app.otherElements["Logged Diaper Change"])
        XCTAssertNotEqual(diapers.label, before, "The new diaper should count toward today")
        XCTAssertTrue(app.buttons["Add"].isHittable, "The toast must sit above the + button (#22)")
        tap(app.buttons["Undo"])
        expectGone(toast)
        XCTAssertEqual(diapers.label, before)

        // Timeline: repeat the seeded tagged feeding, then undo it — over the list's own rows.
        tap(app.tabBars.buttons["Timeline"])
        let tagged = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, night'"))
        expect(tagged.firstMatch).swipeRight()
        let repeatAction = app.buttons["Repeat"]
        if repeatAction.waitForExistence(timeout: 2) { repeatAction.tap() } // unless the full swipe ran it
        toast = expect(app.otherElements["Logged Feeding"])
        XCTAssertEqual(tagged.count, 2)
        tap(app.buttons["Undo"])
        expectGone(toast)
        XCTAssertEqual(tagged.count, 1)
        XCTAssertFalse(app.navigationBars["Edit Feeding"].exists, "Undo opened the row underneath")
    }

    // Regression: #100 — Save looked tappable while a pumping without an amount was silently dropped.
    func testPumpingSaveBlockedUntilAmount() {
        launch(["BB_TOAST_SECONDS": "30"])
        openEditor("Pumping")
        let bar = expect(app.navigationBars["New Pumping"])
        let save = bar.buttons["Save"]
        let saveBottom = app.buttons["Save Pumping"]

        XCTAssertTrue(app.staticTexts["Enter how much was pumped — Baby Buddy needs an amount."].exists)
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(saveBottom.isEnabled)

        let amount = app.textFields["0"]
        amount.tap()
        amount.typeText("75")
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(saveBottom.isEnabled)

        save.tap()
        expectGone(bar)
        expect(app.otherElements["Logged Pumping"])
    }

    func testLogDiaperUpdatesHomeAndTimeline() {
        launch()
        let diapers = expect(element(labeled: "Diapers, "))
        let before = diapers.label

        openEditor("Diaper")
        let bar = expect(app.navigationBars["New Diaper Change"])
        let solid = app.switches["Solid"]
        XCTAssertEqual(solid.value as? String, "0")
        solid.tap()
        XCTAssertEqual(solid.value as? String, "1")
        tap(app.buttons["Save Diaper Change"])
        expectGone(bar)

        // Counted today, first in Latest, and queued for the server until a sync delivers it.
        XCTAssertNotEqual(diapers.label, before)
        let queued = "label BEGINSWITH 'Diaper Change, Wet, Solid' AND label CONTAINS 'waiting to sync'"
        expect(elements(queued).firstMatch)
        tap(app.tabBars.buttons["Timeline"])
        expect(elements(queued).firstMatch)
    }

    func testFeedingTagAutocomplete() {
        launch()
        openEditor("Feeding")
        let bar = expect(app.navigationBars["New Feeding"])

        let tags = app.textFields["Add a tag"]
        tags.tap()
        tags.typeText("hu")
        tap(app.buttons["hungry"]) // a cached server tag, suggested as you type
        expect(app.buttons["Remove tag hungry"])

        tags.tap()
        tags.typeText("newtag")
        expect(elements("label CONTAINS 'Create “newtag”'").firstMatch)
        tags.typeText("\n") // Return creates it, like the row
        expect(app.buttons["Remove tag newtag"])

        tap(bar.buttons["Save"])
        expectGone(bar)
        tap(app.tabBars.buttons["Timeline"])
        expect(elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, newtag'").firstMatch)
    }

    /// New records can switch kind and start a timer instead; existing ones can only be deleted.
    func testEditorModes() {
        launch()
        openEditor("Feeding")
        var bar = expect(app.navigationBars["New Feeding"])
        XCTAssertTrue(app.staticTexts["Pump"].exists, "A new entry offers the kind pills")
        XCTAssertTrue(app.buttons["Start timer instead"].exists)
        XCTAssertFalse(app.buttons["Delete Feeding"].exists)
        tap(bar.buttons["Cancel"])
        expectGone(bar)

        openEditor("Diaper")
        bar = expect(app.navigationBars["New Diaper Change"])
        XCTAssertFalse(app.buttons["Start timer instead"].exists, "Only feeding, sleep and tummy time can start a timer")
        tap(bar.buttons["Cancel"])
        expectGone(bar)

        // The seeded latest feeding: breast milk, left breast (#25).
        tap(app.buttons.labeled("Feeding, Breast Milk"))
        expect(app.navigationBars["Edit Feeding"])
        XCTAssertTrue(app.buttons["Breast"].isSelected, "The editor should open pre-filled")
        XCTAssertTrue(app.buttons.labeled("Left Breast").exists)
        XCTAssertTrue(app.buttons["Delete Feeding"].exists)
        XCTAssertFalse(app.staticTexts["Pump"].exists, "An existing record can't change kind")
        XCTAssertFalse(app.buttons["Start timer instead"].exists)
    }

    /// The "+" stack (#26). Update this when #78 makes its rows log in one tap.
    func testQuickAddMenu() {
        launch()
        tap(app.buttons["Add"])
        expect(app.buttons["Close"])
        for row in ["Start timer", "Feeding", "Diaper", "Sleep", "Tummy time"] {
            XCTAssertTrue(app.buttons[row].exists, "No quick-add row \(row)")
        }
        let more = app.buttons.labeled("More…")
        XCTAssertTrue(more.exists)

        // The dim closes the stack.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)).tap()
        expectGone(more)
        expect(app.buttons["Add"])

        tap(app.buttons["Add"])
        tap(app.buttons["Feeding"])
        expect(app.navigationBars["New Feeding"])
    }

    /// A dose with a next-dose interval waits on Home and on its timeline row, and a second dose of
    /// the same medication warns without blocking (#118).
    func testMedicationNextDose() {
        launch()
        openEditor("Medication")
        var bar = expect(app.navigationBars["New Medication"])
        XCTAssertFalse(bar.buttons["Save"].isEnabled, "A dose needs a name")
        let name = app.textFields["Name"]
        name.tap()
        name.typeText("Tylenol")
        tap(app.buttons.labeled("None")) // "Next dose after"
        tap(app.buttons["4h"])
        tap(bar.buttons["Save"])
        expectGone(bar)

        let waiting = element(labeled: "Tylenol, next dose OK at")
        expect(waiting)
        tap(app.tabBars.buttons["Timeline"])
        expect(elements("label BEGINSWITH 'Medication, Tylenol' AND label CONTAINS 'next dose OK at'").firstMatch)
        tap(app.tabBars.buttons["Home"])

        openEditor("Medication")
        bar = expect(app.navigationBars["New Medication"])
        let again = app.textFields["Name"]
        again.tap()
        again.typeText("Tylenol")
        expect(element(labeled: "Warning. Tylenol was last given at"))
        XCTAssertTrue(bar.buttons["Save"].isEnabled, "The warning mustn't block the dose")
        tap(bar.buttons["Cancel"])
        expectGone(bar)

        tap(waiting)
        expect(app.navigationBars["Edit Medication"])
        XCTAssertTrue(app.buttons.labeled("4h").exists, "The dose should reopen with its interval")
    }
}
