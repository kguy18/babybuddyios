import XCTest

/// iPhone Duo's open display (#215). XCUITest can't unfold a Duo: `scripts/ui-test.sh --duo-open`
/// unfolds one with duoctl first, and these run on the real open display there. Anywhere else they
/// skip, unless the test runner has `BB_FOLD=1` (`TEST_RUNNER_BB_FOLD=1 scripts/ui-test.sh ...`),
/// which lays out the screens and sheets as the open display does on whatever simulator runs them.
/// On a phone those panes are cramped: there these check where things go and that they still work,
/// not how they look.
final class FoldTests: UITestCase {
    /// Whether the runner forces the open layouts with `BB_FOLD=1` rather than running on the open display.
    private let forced = ProcessInfo.processInfo.environment["BB_FOLD"] == "1"

    /// The window width the first test measured. The display can't change during a run, so the
    /// tests after it skip without a launch of their own: on CI's iPhone Duo front display each
    /// launch-and-skip took 20 s to 3 min, which put the shard holding this class past its cap.
    private static var measuredWidth: CGFloat?

    /// Launches with `environment` on the open display's layouts: forced with `BB_FOLD` when the
    /// runner asks for it, and otherwise only on the open display itself, skipping anywhere else.
    /// The app's window tells: 951 pt wide open, against 466 folded and at most 440 on other
    /// iPhones. SpringBoard's frame doesn't, as it still reads the front display's on an open Duo.
    private func launchOpen(_ environment: [String: String] = [:], largestText: Bool = false, demo: Bool = true) throws {
        if !forced, let width = Self.measuredWidth { try skipUnlessOpen(width) }
        launch(forced ? environment.merging(["BB_FOLD": "1"]) { $1 } : environment, demo: demo, largestText: largestText)
        guard !forced else { return }
        let width = app.windows.firstMatch.frame.width
        Self.measuredWidth = width
        try skipUnlessOpen(width)
    }

    private func skipUnlessOpen(_ width: CGFloat) throws {
        try XCTSkipUnless(width >= 900, "Needs iPhone Duo's open display (scripts/ui-test.sh --duo-open) or "
                          + "TEST_RUNNER_BB_FOLD=1; this window is \(Int(width)) pt wide")
    }

    func testFeedbackKeepsTheNoteBesideTheActions() throws {
        try checkFeedbackPanes(largestText: false)
    }

    func testFeedbackKeepsTheNoteBesideTheActionsAtLargestText() throws {
        try checkFeedbackPanes(largestText: true)
    }

    private func checkFeedbackPanes(largestText: Bool) throws {
        try launchOpen(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"], largestText: largestText)
        openSendFeedback()
        let note = expect(element(labeled: "Hi, I'm Kurtis."))
        let request = expect(app.buttons.labeled("Request a Feature"))
        let noteFrame = note.frame
        let requestFrame = request.frame
        captureFeedbackInventory()
        XCTAssertGreaterThan(requestFrame.minX, noteFrame.maxX, "Actions should sit beside the note")
        XCTAssertGreaterThan(requestFrame.minX, app.windows.firstMatch.frame.midX)
        XCTAssertLessThan(noteFrame.maxX, app.windows.firstMatch.frame.midX)
        tap(app.buttons.labeled("Request a Feature"))
        let board = expect(app.navigationBars["Request a Feature"])
        expect(app.webViews.staticTexts["Stub widget: new-post"], timeout: 30)
        tap(board.buttons["Close"])
        expectGone(board)
    }

    func testGetHelpSignInUsesBothPanesAtLargestText() throws {
        try launchOpen(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"], largestText: true)
        openSendFeedback()
        tap(app.buttons.labeled("Get Help"))
        expect(app.textFields["Email"], timeout: 30)
        assertLeftOfFold(app.staticTexts["Sign in with your email so I can reply to you."])
        assertRightOfFold(app.textFields["Email"])
        assertRightOfFold(app.buttons["Send Code"])
        attachScreen("settings-panes-help-sign-in")
    }

    func testOfflineGetHelpUsesBothPanesAtLargestText() throws {
        try launchOpen(["BB_START_TAB": "settings"], largestText: true)
        openSendFeedback()
        tap(app.buttons.labeled("Get Help"))
        let title = expect(app.staticTexts["Can't reach the feedback server"], timeout: 30)
        assertLeftOfFold(title)
        assertRightOfFold(app.buttons["Email Support"])
        attachScreen("settings-panes-help-offline")
    }

    func testFeedbackAccountStaysBesideTheFoldAtLargestText() throws {
        try launchOpen(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-in"], largestText: true)
        openSendFeedback()
        tap(app.buttons.labeled("Feedback Account"))
        let signOut = expect(app.buttons["Sign Out of Feedback"])
        let deletion = expect(app.buttons["Delete Feedback Account"])
        let middle = app.windows.firstMatch.frame.midX
        XCTAssertGreaterThan(signOut.frame.minX, middle, "Sign Out should stay right of the fold")
        XCTAssertGreaterThan(deletion.frame.minX, middle, "Delete should stay in the same pane")
    }

    func testCustomHeadersStayBesideTheFold() throws {
        try checkCustomHeaderPane(largestText: false)
    }

    func testCustomHeadersStayBesideTheFoldAtLargestText() throws {
        try checkCustomHeaderPane(largestText: true)
    }

    private func checkCustomHeaderPane(largestText: Bool) throws {
        try launchOpen(["BB_START_TAB": "settings"], largestText: largestText)
        tap(app.buttons.labeled("Custom headers"))
        expect(app.navigationBars["Custom headers"])
        let add = expect(app.buttons["Add header"])
        let footer = expect(app.staticTexts.labeled("Only for a server behind an access gate"))
        attachScreen("settings-custom-headers")
        let middle = app.windows.firstMatch.frame.midX
        XCTAssertGreaterThan(add.frame.minX, middle, "The header card should stay right of the fold")
        assertLeftOfFold(footer)
        tap(add)
        let name = expect(app.textFields["Header name"])
        XCTAssertGreaterThan(name.frame.minX, middle, "Added fields should stay in the same pane")
        let paste = expect(app.buttons.labeled("Paste"))
        XCTAssertGreaterThan(paste.frame.minX, middle, "Paste should stay in the same pane")
        attachScreen("settings-custom-headers-add")
        tap(app.buttons["Remove header"])
        expectGone(name)
    }

    func testSickModeSettingsAndDialogsStayBesideTheFold() throws {
        try launchOpen(["BB_START_TAB": "settings", "BB_SEED_SICK": "1", "BB_TEMP_UNIT": "f"])
        allowNotificationsIfAsked()
        let middle = app.windows.firstMatch.frame.midX

        tap(app.buttons.labeled("Fever line"))
        XCTAssertGreaterThan(expect(app.buttons["99.5°F"]).frame.minX, middle)
        back(from: "Fever line")

        tap(app.buttons.labeled("Temperature checks"))
        XCTAssertGreaterThan(expect(app.buttons["Off"]).frame.minX, middle)
        back(from: "Temperature checks")

        tap(app.buttons["Medicine colors"])
        tap(app.buttons.labeled("Ibuprofen"))
        let pink = expect(app.buttons["Pink"])
        assertLeftOfFold(pink)
        tap(pink)
        let cancel = expect(app.buttons["Cancel"])
        XCTAssertGreaterThan(cancel.frame.minX, middle)
        tap(cancel)
        back(from: "Medicine colors")

        tap(app.buttons["Sign out"])
        let signOut = expect(app.alerts.labeled("Sign out of "))
        XCTAssertGreaterThan(expect(signOut.buttons["Cancel"]).frame.minX, middle)
    }

    func testSettingsPickersUseBothPanes() throws {
        try checkSettingsPickers(largestText: false)
    }

    func testSettingsPickersUseBothPanesAtLargestText() throws {
        try checkSettingsPickers(largestText: true)
    }

    private func checkSettingsPickers(largestText: Bool) throws {
        try launchOpen(["BB_START_TAB": "settings"], largestText: largestText)

        tap(app.buttons.labeled("Today tiles, 4 on"))
        expect(app.navigationBars["Today Tiles"])
        assertLeftOfFold(app.staticTexts.labeled("Drag to change the order on Home."))
        assertRightOfFold(app.switches["Feedings"])
        attachScreen("settings-panes-tiles")
        back(from: "Today Tiles")

        tap(app.buttons.labeled("App Icon, Center Peek"))
        expect(app.navigationBars["App Icon"])
        assertLeftOfFold(app.buttons["Center Peek"].firstMatch)
        assertRightOfFold(app.buttons["Peek Wave"].firstMatch)
        XCTAssertTrue(app.buttons["Center Peek"].firstMatch.isSelected)
        attachScreen("settings-panes-icons")
        back(from: "App Icon")

        tap(app.buttons.labeled("Forgotten timer alerts, Off"))
        expect(app.navigationBars["Forgotten timer alerts"])
        assertLeftOfFold(app.staticTexts.labeled("Get a notification when a timer runs longer than expected"))
        assertRightOfFold(app.switches["Forgotten timer alerts"])
        attachScreen("settings-panes-timers")
    }

    func testSickModeDetailsUseBothPanesAtLargestText() throws {
        try launchOpen(["BB_START_TAB": "settings", "BB_SEED_SICK": "1", "BB_TEMP_UNIT": "f"], largestText: true)
        allowNotificationsIfAsked()

        tap(app.buttons.labeled("Fever line"))
        assertLeftOfFold(app.staticTexts.labeled("A reading at or over this line counts as a fever."))
        assertRightOfFold(app.buttons["99.5°F"])
        attachScreen("settings-panes-fever")
        back(from: "Fever line")

        tap(app.buttons.labeled("Temperature checks"))
        assertLeftOfFold(app.staticTexts.labeled("While sick mode is on"))
        assertRightOfFold(app.buttons["Off"])
        attachScreen("settings-panes-checks")
        back(from: "Temperature checks")

        tap(app.buttons["Medicine colors"])
        assertRightOfFold(app.staticTexts.labeled("Each medicine gets the next color"))
        assertRightOfFold(app.buttons["Reset to server colors"])
        assertLeftOfFold(app.buttons.labeled("Acetaminophen"))
        attachScreen("settings-panes-medicines")
    }

    func testStaleAfterChoicesStayClearOfTheFold() throws {
        try launchOpen(["BB_START_TAB": "settings"], largestText: true)
        tap(app.buttons["30 min"])
        expect(app.navigationBars["Stale after"])
        assertLeftOfFold(app.staticTexts.labeled("The sync time on Home"))
        assertRightOfFold(app.buttons["15 min"])
        attachScreen("settings-panes-stale")
        tap(app.buttons["15 min"])
        expect(app.navigationBars["Settings"])
        expect(app.buttons["15 min"])
    }

    func testRoadmapTitleFitsWithSignIn() throws {
        try launchOpen(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"], largestText: true)
        openSendFeedback()
        tap(app.buttons.labeled("Roadmap and Updates"))
        expect(app.webViews.staticTexts["Stub widget: home"], timeout: 30)
        let bar = expect(app.navigationBars["Roadmap and Updates"])
        let title = expect(bar.staticTexts["Roadmap and Updates"].firstMatch)
        XCTAssertGreaterThan(title.frame.width, 115, "The title needs room for all three words")
        attachScreen("settings-panes-roadmap")
    }

    /// The tapped record opens right of the list, ready to edit, with Save, Repeat and Delete in the
    /// toolbar. Each of them closes the pane again.
    func testTimelineOpensARecordBesideTheList() throws {
        try launchOpen(["BB_START_TAB": "timeline", "BB_TOAST_SECONDS": "30"])
        let empty = app.staticTexts["No activity open"]
        let rows = elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, night'")
        expect(empty)

        let row = rows.element(boundBy: 0)
        tap(row)
        let editorSave = expect(app.buttons["Save Feeding"])
        XCTAssertGreaterThan(editorSave.frame.minX, row.frame.maxX - 1, "The editor should open right of the list")
        if !forced {
            // On the real open display the fold is the window's middle: the list ends before it
            // and the editor starts after it.
            let middle = app.windows.firstMatch.frame.midX
            XCTAssertLessThanOrEqual(row.frame.maxX, middle, "The list should end left of the fold")
            XCTAssertGreaterThanOrEqual(editorSave.frame.minX, middle, "The editor should start right of the fold")
        }
        expect(row, matching: NSPredicate { _, _ in row.isSelected }, timeout: 5, describedAs: "to read as selected")
        tap(app.buttons["Save"])
        expect(empty)

        tap(row)
        tap(app.buttons["Repeat"])
        expect(app.otherElements["Logged Feeding"])
        expect(empty)
        XCTAssertEqual(rows.count, 2, "Repeat should log the feeding again")

        tap(rows.element(boundBy: 0))
        tap(app.buttons["Delete"])
        let confirmation = expect(app.otherElements["Delete this feeding?"])
        XCTAssertFalse(app.alerts.firstMatch.exists, "Pane deletion should stay inside the editor")
        tap(confirmation.buttons["Cancel"])
        expectGone(confirmation)
        XCTAssertEqual(rows.count, 2, "Cancel should keep the feeding")
        tap(app.buttons["Delete"])
        tap(confirmation.buttons["Delete"])
        expect(empty)
        XCTAssertEqual(rows.count, 1, "Delete should remove the repeated feeding")
    }

    func testDeleteConfirmationStaysInThePaneAtTheLargestText() throws {
        try launchOpen(["BB_START_TAB": "timeline"], largestText: true)
        let row = elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, night'").firstMatch
        reveal(row, in: expect(app.collectionViews.firstMatch), below: app.textFields["Search notes, tags, type…"])
        tap(row)
        tap(app.buttons["Delete"])
        let confirmation = expect(app.otherElements["Delete this feeding?"])
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertGreaterThan(confirmation.frame.minX, app.windows.firstMatch.frame.midX,
                             "The confirmation should stay right of the fold")
        tap(confirmation.buttons["Cancel"])
        expectGone(confirmation)
        XCTAssertTrue(row.exists, "Cancel should keep the record")
    }

    /// The search field and the child pill sit in the list's pane: in the navigation bar they ran
    /// across the fold. Both still work there.
    func testTimelineSearchAndChildPillSitLeftOfTheFold() throws {
        try launchOpen(["BB_START_TAB": "timeline", "BB_SEED_SECOND_CHILD": "1"])
        let middle = app.windows.firstMatch.frame.midX
        let search = expect(app.textFields["Search notes, tags, type…"])
        let pill = expect(app.buttons.labeled("Current child, Maya"))
        XCTAssertLessThanOrEqual(search.frame.maxX, middle, "The search field should end left of the fold")
        XCTAssertLessThanOrEqual(pill.frame.maxX, middle, "The child pill should end left of the fold")
        XCTAssertFalse(app.searchFields.firstMatch.exists, "The navigation bar should have no search field")

        tap(search)
        search.typeText("garden\n")
        expect(element(labeled: "Note, Looking out at the garden."))
        XCTAssertEqual(elements("label BEGINSWITH 'Feeding, '").count, 0, "The search should filter the list")
        tap(app.buttons["Clear text"])
        expect(element(labeled: "Feeding, "))

        tap(pill)
        tap(app.buttons["Leo Rivers"])
        expect(app.buttons.labeled("Current child, Leo"))
    }

    func testTimelineTypeChoicesStayBesideTheFold() throws {
        try checkTimelineTypeChoices(largestText: false)
    }

    func testTimelineTypeChoicesStayBesideTheFoldAtLargestText() throws {
        try checkTimelineTypeChoices(largestText: true)
    }

    private func checkTimelineTypeChoices(largestText: Bool) throws {
        try launchOpen(["BB_START_TAB": "timeline"], largestText: largestText)
        tap(app.buttons["Filters"])
        let filters = expect(app.navigationBars["Filters"])
        let type = app.buttons.labeled("Type")
        tap(type)
        let choices = expect(app.navigationBars["Type"])
        let allTypes = expect(app.buttons["All Types"])
        XCTAssertTrue(allTypes.isSelected)
        assertRightOfFold(allTypes)
        attachSickSettingsScreen(largestText ? "timeline-type-open-axxxl-after" : "timeline-type-open-default-after")

        let note = app.buttons["Note"]
        reveal(note, in: expect(app.scrollViews.containing(.button, identifier: "All Types").firstMatch))
        assertRightOfFold(note)
        tap(note)
        expectGone(choices)
        expect(filters)
        XCTAssertEqual(type.value as? String, "Note")
        tap(filters.buttons["Done"])
        expect(element(labeled: "Note, Looking out at the garden."))
        XCTAssertEqual(elements("label BEGINSWITH 'Feeding, '").count, 0)
    }

    func testTimelineEmptySearchCanBeClearedAboveTheKeyboard() throws {
        try launchOpen(["BB_START_TAB": "timeline"])
        checkEmptySearchWithKeyboard(app.textFields["Search notes, tags, type…"])
    }

    func testTimelineEmptySearchCanBeClearedAtLargestText() throws {
        try launchOpen(["BB_START_TAB": "timeline"], largestText: true)
        checkEmptySearchWithKeyboard(app.textFields["Search notes, tags, type…"])
    }

    /// A Today tile's day keeps its list left of the fold and opens the tapped record right of it,
    /// as the Timeline tab does.
    func testDayTimelineOpensARecordBesideTheList() throws {
        try launchOpen()
        // Log one now: soon after midnight the demo has no feedings today.
        openEditor("Feeding")
        let new = expect(app.navigationBars["New Feeding"])
        tap(new.buttons["Save"])
        expectGone(new)
        tap(expect(element(labeled: "Feedings, ")))
        let empty = expect(app.staticTexts["No activity open"])
        let row = expect(elements("label BEGINSWITH 'Feeding, '").firstMatch)
        let add = expect(app.buttons["Add Feeding"])
        attachSickSettingsScreen("day-timeline")
        XCTAssertFalse(add.frame.intersects(row.frame), "Add should leave the first activity row clear")
        expectAddButtonInRail("Add Feeding")
        tap(add)
        tap(expect(new).buttons["Cancel"])
        expectGone(new)
        tap(row)
        let editorSave = expect(app.buttons["Save Feeding"])
        XCTAssertGreaterThan(editorSave.frame.minX, row.frame.maxX - 1, "The editor should open right of the list")
        tap(app.buttons["Save"])
        expect(empty)
    }

    /// Home's day pane says nothing is logged under its header: drawn over the pane, the empty
    /// state's icon covered the header's counts.
    func testHomeEmptyStateSitsUnderTheHeader() throws {
        try launchOpen(["BB_SEED_SECOND_CHILD": "1"], largestText: true)
        let avatar = app.buttons.labeled("Current child, Maya")
        let leo = app.buttons.labeled("Leo")
        tap(avatar)
        if !leo.waitForExistence(timeout: 3), avatar.isHittable { avatar.tap() }
        tap(leo)
        let nothing = expect(app.staticTexts["Nothing logged today"])
        let header = expect(elements("label BEGINSWITH 'Today, '").firstMatch)
        XCTAssertGreaterThan(nothing.frame.minY, header.frame.maxY - 1, "The empty state should sit under the header")
    }

    func testSignOutCopySitsBesideItsActionsAtTheLargestText() throws {
        try launchOpen(["BB_START_TAB": "settings"], largestText: true)
        allowNotificationsIfAsked()
        tap(app.buttons["Sign out"])

        let dialog = expect(app.alerts.labeled("Sign out of "))
        let copy = expect(dialog.staticTexts.labeled("The activities cached on this device"))
        let cancel = expect(dialog.buttons["Cancel"])
        assertLeftOfFold(copy)
        assertRightOfFold(cancel)
        assertRightOfFold(dialog.buttons["Sign out"])
        // The copy has the whole left pane; past its height it scrolls there.
        XCTAssertTrue(app.windows.firstMatch.frame.contains(dialog.staticTexts["Sign out?"].frame),
                      "The heading should be in view")
        XCTAssertTrue(cancel.isHittable, "Cancel should be in view")
        tap(cancel)
        expectGone(dialog)
    }

    func testGentleNudgeCopySitsBesideItsActionsAtTheLargestText() throws {
        try launchOpen(["BB_NUDGE": "gentle"], largestText: true)
        allowNotificationsIfAsked()
        let copy = expect(app.staticTexts.labeled("Every feature is free"))
        let reminder = expect(app.staticTexts["Reminders can be turned off in Settings."])
        let later = expect(app.buttons["Maybe later"])
        assertLeftOfFold(copy)
        assertLeftOfFold(reminder)
        assertRightOfFold(app.buttons["Become a Supporter"])
        assertRightOfFold(later)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(copy.frame), "The whole body should be in view")
        tap(later)
        expectGone(later)
    }

    /// The Undo toast comes up under the day's timeline, left of the fold: at the bottom of the
    /// pane right of it, it covered the running timer's Stop button.
    func testUndoToastLeavesTheTimerUncoveredAtTheLargestText() throws {
        try launchOpen(["BB_TOAST_SECONDS": "90"], largestText: true)
        allowNotificationsIfAsked()
        openEditor("Diaper")
        let sheet = expect(app.navigationBars["New Diaper Change"])
        tap(sheet.buttons["Save"])
        expectGone(sheet)
        let toast = expect(element(labeled: "Logged Diaper Change"))
        let stop = expect(app.buttons["Stop"])
        attachScreen("undo-open")
        assertLeftOfFold(toast)
        assertRightOfFold(stop)
        XCTAssertTrue(app.buttons["Undo"].isHittable)
        tap(stop)
        expect(app.navigationBars["Stop Timer"])
    }

    /// The support nudge comes up at the bottom of the pane right of the fold rather than as a card
    /// centred across it, and still takes no for an answer.
    func testSupportNudgeSitsRightOfTheFold() {
        launch(["BB_NUDGE": "gentle", "BB_FOLD": "1"])
        // The demo's running timer asks for notification permission on a freshly erased simulator.
        // While that prompt is up the app isn't active, so the Dashboard never offers the nudge;
        // answering it makes the app active again, which checks once more.
        allowNotificationsIfAsked()
        let support = expect(app.buttons["Become a Supporter"])
        let later = expect(app.buttons["Maybe later"])
        let window = app.windows.firstMatch.frame
        // Right of the middle: with no fold reported, as on a phone, the fold is the middle 40 pt.
        XCTAssertGreaterThan(support.frame.minX, window.midX, "The nudge should sit right of the fold")
        XCTAssertGreaterThan(later.frame.minX, window.midX, "The nudge should sit right of the fold")
        // The bottom quarter: a centred card on the open display ends well above it.
        XCTAssertGreaterThan(later.frame.maxY, window.minY + window.height * 0.75, "The nudge should sit at the bottom")
        tap(later)
        expectGone(later)
    }

    /// The What's New card after an update puts its heading and buttons left of the fold and the
    /// release list right of it.
    func testWhatsNewSplitsAtTheFold() throws {
        try launchOpen(["BB_WHATSNEW_UPGRADE": "1"])
        // The demo's running timer asks for notification permission on a freshly erased simulator,
        // and the prompt would take the tap on Continue.
        allowNotificationsIfAsked()
        let midX = app.windows.firstMatch.frame.midX
        XCTAssertLessThan(expect(app.buttons["Continue"]).frame.maxX, midX, "Continue should sit left of the fold")
        XCTAssertGreaterThan(expect(app.scrollViews["whats-new-releases"]).frame.minX, midX,
                             "The release list should sit right of the fold")
        tap(app.buttons["Continue"])
        expectGone(app.buttons["Continue"])
    }

    func testWhatsNewUpgradeNotesScrollBesideContinueAtTheLargestText() throws {
        try launchOpen(["BB_WHATSNEW_UPGRADE": "1"], largestText: true)
        allowNotificationsIfAsked()
        let continueButton = expect(app.buttons["Continue"])
        let notes = expect(app.scrollViews["whats-new-releases"])
        let firstNote = expect(notes.staticTexts.firstMatch)
        let initialTop = firstNote.frame.minY
        assertLeftOfFold(continueButton)
        assertRightOfFold(firstNote)
        XCTAssertLessThanOrEqual(firstNote.frame.maxY, notes.frame.maxY)
        notes.swipeUp()
        XCTAssertLessThan(firstNote.frame.minY, initialTop)
        tap(continueButton)
        expectGone(continueButton)
    }

    /// Acknowledgements: the credit left of the fold, the other licences right of it.
    func testAcknowledgementsSplitAtTheFold() throws {
        try launchOpen(["BB_START_TAB": "settings"])
        tap(app.buttons["Acknowledgements"])
        let midX = app.windows.firstMatch.frame.midX
        XCTAssertLessThan(expect(app.staticTexts["Based on Baby Buddy"]).frame.maxX, midX,
                          "The credit should sit left of the fold")
        XCTAssertGreaterThan(expect(app.staticTexts["Baby Buddy"]).frame.minX, midX,
                             "Baby Buddy's licence should sit right of the fold")
    }

    /// The milestone sheet and the supporter sheet it opens each put the ask left of the fold and
    /// the buttons right of it.
    func testSupportSheetsSplitAtTheFold() throws {
        try launchOpen(["BB_NUDGE": "milestone"])
        allowNotificationsIfAsked()
        let midX = app.windows.firstMatch.frame.midX
        XCTAssertLessThan(expect(elements("label CONTAINS 'activities logged'").firstMatch).frame.maxX, midX,
                          "The milestone should sit left of the fold")
        let support = expect(app.buttons["Become a Supporter"])
        XCTAssertGreaterThan(support.frame.minX, midX, "Become a Supporter should sit right of the fold")
        XCTAssertGreaterThan(expect(app.buttons["Not now"]).frame.minX, midX, "Not now should sit right of the fold")

        tap(support)
        XCTAssertLessThan(expect(app.staticTexts["Support Baby Buddy Companion"]).frame.maxX, midX,
                          "The ask should sit left of the fold")
        XCTAssertGreaterThan(expect(app.buttons["Maybe later"]).frame.minX, midX,
                             "Maybe later should sit right of the fold")
    }

    /// The kind pills split three and three either side of the fold, where one row put "Tummy"
    /// on it, and the feeding types keep to the left column.
    func testEditorPillsSplitAtTheFold() throws {
        try launchOpen()
        openEditor("Feeding")
        expect(app.navigationBars["New Feeding"])
        let editor = app.scrollViews["screen-editor"]
        for name in ["Feeding", "Diaper", "Sleep"] { assertLeftOfFold(editor.staticTexts[name]) }
        for name in ["Tummy", "Pump", "Note"] { assertRightOfFold(editor.staticTexts[name]) }
        for name in ["Breast", "Formula", "Fortified", "Solid"] { assertLeftOfFold(editor.buttons[name]) }
        tap(editor.staticTexts["Tummy"])
        expect(app.navigationBars["New Tummy Time"])
    }

    func testEditorFieldsStayBesideTheFoldAtTheLargestText() throws {
        try launchOpen(largestText: true)
        allowNotificationsIfAsked()
        openEditor("Feeding")
        expect(app.navigationBars["New Feeding"])
        attachScreen("editor-axxxl")
        assertLeftOfFold(app.staticTexts["WHEN"])
        // Start's date and time pills, each on a line of its own.
        assertLeftOfFold(app.datePickers.element(boundBy: 0))
        assertLeftOfFold(app.datePickers.element(boundBy: 1))
        assertRightOfFold(app.staticTexts["TAGS"])
        assertRightOfFold(app.buttons["Save Feeding"])
    }

    func testConflictChoicesStayBesideTheFoldAtTheLargestText() throws {
        try launchOpen(["BB_START_TAB": "settings", "BB_SEED_CONFLICT": "1", "BB_OPEN_CONFLICT": "1"],
                       largestText: true)
        expect(app.navigationBars["Resolve Conflict"])
        attachScreen("conflict-axxxl")
        let mine = app.buttons.labeled("Amount, Mine,")
        let server = app.buttons.labeled("Amount, Server,")
        assertLeftOfFold(mine)
        assertRightOfFold(server)
    }

    func testSettingsSheetsStayBesideTheFoldAtTheLargestText() throws {
        try launchOpen(["BB_START_TAB": "settings"], largestText: true)
        allowNotificationsIfAsked()
        let settings = app.scrollViews.firstMatch
        let whatsNew = app.buttons.labeled("What's New")
        if !whatsNew.isHittable { reveal(whatsNew, in: settings) }
        tap(whatsNew)
        let done = app.buttons["Done"]
        let releases = app.scrollViews["whats-new-releases"]
        assertLeftOfFold(done)
        assertRightOfFold(releases)
        attachScreen("whats-new-axxxl")
        reveal(element(labeled: "Activity estimates"), in: releases)
        tap(done)
        expectGone(done)

        let supporter = app.buttons.labeled("Baby Buddy App Supporter")
        if !supporter.isHittable { reveal(supporter, in: settings) }
        tap(supporter)
        assertLeftOfFold(app.staticTexts["Support Baby Buddy Companion"])
        let later = app.buttons["Maybe later"]
        assertRightOfFold(later)
        attachScreen("supporter-axxxl")
        tap(later)
        expectGone(later)
    }

    func testAdvancedConfigurationKeepsSaveByTheHeaders() throws {
        try launchOpen(demo: false)
        tap(app.buttons["Advanced configuration"])
        expect(app.navigationBars["Advanced configuration"])
        tap(app.buttons["Add header"])
        let add = expect(app.buttons["Add another header"])
        let save = expect(app.buttons["Save"])
        assertRightOfFold(save)
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.minY - add.frame.maxY, 28)
        attachScreen("settings-panes-advanced")
    }

    func testAdvancedConfigurationStaysBesideTheFoldAtTheLargestText() throws {
        try launchOpen(["BB_GATE_PREVIEW": "cloudflareAccess"], largestText: true, demo: false)
        expect(app.navigationBars["Advanced configuration"])
        attachScreen("advanced-axxxl")
        assertLeftOfFold(element(labeled: "Where sign-in stopped"))
        assertRightOfFold(app.textFields["Client ID"])
        let label = expect(app.staticTexts["Client ID"])
        XCTAssertGreaterThan(label.frame.width, label.frame.height, "\"Client ID\" should fit on one line")
        let add = expect(app.buttons["Add another header"])
        let save = expect(app.buttons["Save and try again"])
        assertRightOfFold(save)
        XCTAssertLessThanOrEqual(save.frame.minY - add.frame.maxY, 28,
                       "Save should sit directly below the headers")
    }

    // The fold is the middle 40 pt of the open window. Allow one point for frame rounding.
    private func assertLeftOfFold(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let edge = app.windows.firstMatch.frame.midX - 19
        XCTAssertLessThanOrEqual(expect(element, file: file, line: line).frame.maxX, edge,
                                 "\(element) should end before the fold", file: file, line: line)
    }

    private func assertRightOfFold(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let edge = app.windows.firstMatch.frame.midX + 19
        XCTAssertGreaterThanOrEqual(expect(element, file: file, line: line).frame.minX, edge,
                                    "\(element) should start after the fold", file: file, line: line)
    }

    func testTimerSheetsKeepControlsBesideTheFoldAtTheLargestText() throws {
        try launchOpen(largestText: true)
        allowNotificationsIfAsked()
        tap(app.buttons["Stop"])
        expect(app.navigationBars["Stop Timer"])
        let stopScroll = app.scrollViews["screen-stop-timer"]
        let feeding = app.buttons["Feeding"]
        let sleep = expect(app.buttons["Sleep"])
        assertLeftOfFold(feeding)
        XCTAssertGreaterThan(sleep.frame.minY, feeding.frame.maxY)
        let resume = app.buttons["Resume timer"]
        assertRightOfFold(resume)
        tap(feeding)
        // Log heads the right column, above the quiet actions, rather than pinned across the fold.
        let log = expect(app.buttons["Log feeding…"])
        XCTAssertTrue(log.isHittable, "Log should be visible as soon as a type is picked")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(log.frame))
        assertRightOfFold(log)
        XCTAssertLessThan(log.frame.maxY, resume.frame.minY, "Log should sit above Resume")
        reveal(resume, in: stopScroll)
        tap(resume)
        expectGone(app.navigationBars["Stop Timer"])

        tap(app.buttons["Add"])
        tap(app.buttons["Start timer"])
        expect(app.navigationBars["Start Timer"])
        let startScroll = app.scrollViews["screen-start-timer"]
        let startSleep = app.buttons["Sleep"]
        assertLeftOfFold(startSleep)
        XCTAssertGreaterThan(startSleep.frame.minY, app.buttons["Feeding"].frame.maxY)
        reveal(startSleep, in: startScroll)
        tap(startSleep)
        let start = expect(app.buttons["Start sleep timer"])
        XCTAssertTrue(start.isHittable, "Start should be visible as soon as a type is picked")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(start.frame))
        let starts = app.staticTexts["Starts"]
        assertRightOfFold(starts)
        // The date and time pills fit the column: at the largest size they ran off the sheet.
        for picker in app.datePickers.allElementsBoundByIndex {
            XCTAssertLessThanOrEqual(picker.frame.maxX, start.frame.maxX + 1, "\(picker) should fit the sheet")
        }
        reveal(starts, in: startScroll)
        XCTAssertGreaterThan(starts.frame.width, starts.frame.height, "\"Starts\" should fit on one line")
        XCTAssertTrue(start.isHittable, "Start should still be visible after scrolling the details")
        tap(start)
        expectGone(app.navigationBars["Start Timer"])
        expect(element(labeled: "Sleep running"))
    }

    /// At the largest text size Add Activity takes two tiles to a row, not six, so the labels fit,
    /// and Home's "+" is in the rail, where it opens the quick-add stack.
    func testAddActivityTakesTwoColumnsAtTheLargestText() throws {
        try launchOpen(largestText: true)
        expectAddButtonInRail()
        tap(app.buttons["Add"])
        tap(app.buttons.labeled("More…"))
        expect(app.navigationBars["Add Activity"])
        let feeding = expect(app.buttons["Feeding"])
        XCTAssertEqual(expect(app.buttons["Diaper"]).frame.midY, feeding.frame.midY, accuracy: 1,
                       "Diaper should sit beside Feeding")
        XCTAssertGreaterThan(expect(app.buttons["Sleep"]).frame.minY, feeding.frame.maxY - 1,
                             "Sleep should start the next row")
    }

    /// Sick mode's Home shares the pane, and its "+" is in the rail too.
    func testSickHomeKeepsTheAddButtonInTheRail() throws {
        try launchOpen(["BB_SEED_SICK": "1"], largestText: true)
        allowNotificationsIfAsked()
        expect(app.buttons["Log temperature"])
        expectAddButtonInRail()
    }

    /// Each sheet takes two columns, or for Add Activity one row of six per group.
    func testSheetsUseTwoColumns() throws {
        try launchOpen()

        tap(app.buttons["Add"])
        tap(app.buttons.labeled("More…"))
        expect(app.navigationBars["Add Activity"])
        XCTAssertEqual(app.buttons["Feeding"].frame.midY, app.buttons["Note"].frame.midY, accuracy: 1,
                       "Every log kind should sit on one row")

        tap(app.buttons["Feeding"])
        let editor = expect(app.navigationBars["New Feeding"])
        // The activity pills run across the top of both columns.
        assertRightOfFold(app.staticTexts["Pump"])
        XCTAssertLessThan(app.staticTexts["Pump"].frame.maxY, app.staticTexts["TAGS"].frame.minY)
        XCTAssertGreaterThan(app.staticTexts["TAGS"].frame.minX, app.staticTexts["WHEN"].frame.minX + 50,
                             "Tags should sit right of When")
        // The narrow column keeps "End" whole beside its duration and date pills: it wrapped to
        // "En / d" even at the default text size.
        let end = app.staticTexts["End"]
        XCTAssertGreaterThan(end.frame.width, end.frame.height, "\"End\" should fit on one line")
        tap(editor.buttons["Cancel"])
        expectGone(editor)

        // The seeded tummy time timer.
        tap(app.buttons["Stop"])
        expect(app.navigationBars["Stop Timer"])
        let resume = expect(app.buttons["Resume timer"])
        let restart = app.buttons["Restart from now"]
        XCTAssertGreaterThan(resume.frame.minX, element(labeled: "Stopped after ").frame.maxX - 1,
                             "The choices should sit right of the summary")
        // The summary fits its narrow column: in #219 its name wrapped to two lines and "Started"
        // to a letter per line.
        let started = app.staticTexts["Started"]
        XCTAssertGreaterThan(started.frame.width, started.frame.height, "\"Started\" should fit on one line")
        XCTAssertLessThan(app.staticTexts["stop-timer-activity"].frame.height, 30,
                          "The activity's name should fit on one line")
        // The sheet opens tall enough to show the tiles: at half height they were cut off.
        let tile = expect(app.buttons["Feeding"])
        XCTAssertTrue(app.windows.firstMatch.frame.contains(tile.frame), "The first tile should be on screen")
        XCTAssertGreaterThan(restart.frame.minY, resume.frame.maxY - 1, "The choices should stack")
        XCTAssertGreaterThan(app.buttons["Discard timer"].frame.minY, restart.frame.maxY - 1)
        tap(restart)
        expectGone(app.navigationBars["Stop Timer"])

        tap(app.buttons["Add"])
        tap(app.buttons["Start timer"])
        let start = expect(app.navigationBars["Start Timer"])
        tap(app.buttons["Sleep"])
        let startSleep = expect(app.buttons["Start sleep timer"])
        XCTAssertGreaterThan(startSleep.frame.minX, app.buttons["Feeding"].frame.minX + 50,
                             "Start should sit right of the activities")
        let starts = expect(app.staticTexts["Starts"])
        XCTAssertGreaterThan(starts.frame.width, starts.frame.height, "\"Starts\" should fit on one line")
        tap(startSleep)
        expectGone(start)
        expect(element(labeled: "Sleep running"))
    }

    /// Trends lays its cards in a column each side of the fold, which ran through every chart when
    /// they were one column across it. The period control still switches them all.
    func testTrendsCardsSitEitherSideOfTheFold() throws {
        try launchOpen(["BB_START_TAB": "trends"])
        let middle = app.windows.firstMatch.frame.midX
        let sleep = expect(app.staticTexts["Sleep"])
        let feedings = expect(app.staticTexts["Feedings"])
        XCTAssertGreaterThan(sleep.frame.minX, middle, "Sleep should sit right of the fold")
        XCTAssertLessThan(feedings.frame.maxX, middle, "Feedings should sit left of the fold")
        tap(app.buttons["30 days"])
        XCTAssertTrue(app.buttons["30 days"].isSelected, "30 days should read as selected")
        XCTAssertGreaterThan(app.staticTexts["Sleep"].frame.minX, middle, "Sleep should stay right of the fold")
    }

    /// Settings puts the account and sync sections left of the fold and the app's own settings
    /// right of it, so no row runs across the fold.
    func testSettingsSplitsAtTheFold() throws {
        try launchOpen(["BB_START_TAB": "settings"])
        let server = expect(app.staticTexts["SERVER"])
        let notifications = expect(app.staticTexts["NOTIFICATIONS"])
        XCTAssertGreaterThan(notifications.frame.minX, server.frame.minX + 100,
                             "Notifications should start the right pane")
        XCTAssertLessThan(notifications.frame.minY, expect(app.staticTexts["SICK MODE"]).frame.minY,
                          "Notifications should sit at the top of its pane, not under Sick mode")
        if !forced {
            let middle = app.windows.firstMatch.frame.midX
            XCTAssertLessThanOrEqual(expect(app.staticTexts["Stale after"]).frame.maxX, middle,
                                     "The Server card should end left of the fold")
            XCTAssertGreaterThanOrEqual(notifications.frame.minX, middle,
                                        "Notifications should start right of the fold")
        }
        // Both panes still work: a menu on the left, a switch on the right.
        tap(app.buttons["30 min"])
        tap(app.buttons["15 min"])
        expect(app.buttons["15 min"])
        let undo = expect(app.switches["Undo after logging"])
        XCTAssertGreaterThan(undo.frame.minX, server.frame.minX + 100)
    }

    func testPendingChangesUsesTheSheetWidth() throws {
        try checkPendingChanges(largestText: false)
    }

    func testPendingChangesUsesTheSheetWidthAtLargestText() throws {
        try checkPendingChanges(largestText: true)
    }

    private func checkPendingChanges(largestText: Bool) throws {
        try launchOpen(["BB_START_TAB": "settings", "BB_SEED_PENDING": "1", "BB_OPEN_PENDING": "1"],
                       largestText: largestText)
        expect(app.navigationBars["Pending Changes"])
        let title = expect(app.staticTexts["Added Pumping"])
        let queue = expect(app.collectionViews.firstMatch)
        let queueFrame = queue.frame
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(queueFrame.width, window.width * 0.6, "The queue should use the sheet width")
        XCTAssertLessThan(title.frame.minX, window.midX, "Pending rows should start left of the fold")

        // Swipe from the card's trailing end, clear of the fold.
        let cell = queue.cells.firstMatch
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: cell.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        tap(app.buttons["Discard"])
        let prompt = expect(app.alerts["Discard this change?"])
        tap(prompt.buttons["Cancel"])
        expectGone(prompt)
        XCTAssertTrue(title.exists, "Cancel should keep the change")

        if largestText {
            let photo = app.staticTexts["Note photo"]
            XCTAssertFalse(photo.exists && photo.isHittable, "The last entry should start below the viewport")
            // Start on the left side of the sheet, which previously had no scrolling content.
            let start = queue.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8))
            let end = queue.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25))
            for _ in 0..<5 {
                if photo.exists && photo.isHittable { break }
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            XCTAssertTrue(photo.exists && photo.isHittable, "Scrolling should reveal the last entry")
        }
    }

    func testConflictScreensKeepContentBesideTheFold() throws {
        try launchOpen(["BB_START_TAB": "settings", "BB_SEED_CONFLICT": "1"])
        tap(app.buttons.labeled("Conflicts"))
        let row = expect(app.buttons.labeled("Feeding"))
        assertLeftOfFold(app.staticTexts["1 to resolve"])
        assertRightOfFold(row)
        attachScreen("settings-panes-conflicts")
        tap(row)
        expect(app.navigationBars["Resolve Conflict"])
        let mine = expect(app.buttons.labeled("Amount, Mine,"))
        let server = expect(app.buttons.labeled("Amount, Server,"))
        XCTAssertGreaterThanOrEqual(server.frame.minX - mine.frame.maxX, 39,
                                    "Mine and Server should have the fold between them")
        XCTAssertEqual(mine.frame.minY, server.frame.minY, accuracy: 1)
        if !forced {
            let middle = app.windows.firstMatch.frame.midX
            XCTAssertLessThan(mine.frame.maxX, middle)
            XCTAssertGreaterThan(server.frame.minX, middle)
        }
        tap(app.buttons["All server"])
        XCTAssertTrue(server.isSelected)
        tap(app.buttons["Save merged feeding"])
        expect(app.staticTexts["No Conflicts"])

        // Resolution also opens as a sheet. Its sizing must leave room for both fold panes.
        try launchOpen(["BB_START_TAB": "settings", "BB_SEED_CONFLICT": "1", "BB_OPEN_CONFLICT": "1"])
        expect(app.navigationBars["Resolve Conflict"])
        let sheetMine = expect(app.buttons.labeled("Amount, Mine,"))
        let sheetServer = expect(app.buttons.labeled("Amount, Server,"))
        XCTAssertGreaterThanOrEqual(sheetServer.frame.minX - sheetMine.frame.maxX, 39)
        XCTAssertEqual(sheetMine.frame.minY, sheetServer.frame.minY, accuracy: 1)
        if !forced {
            let middle = app.windows.firstMatch.frame.midX
            XCTAssertLessThan(sheetMine.frame.maxX, middle, "The sheet's Mine card should end before the fold")
            XCTAssertGreaterThan(sheetServer.frame.minX, middle, "The sheet's Server card should start after the fold")
        }
    }

    func testOnboardingAndScannerKeepContentBesideTheFold() throws {
        try launchOpen(demo: false)
        let welcome = expect(app.staticTexts["Baby Buddy"])
        let url = expect(app.textFields["Your server URL or IP address"])
        XCTAssertGreaterThan(url.frame.minX, welcome.frame.maxX, "The manual form should sit right of the welcome")
        if !forced {
            XCTAssertLessThan(welcome.frame.maxX, app.windows.firstMatch.frame.midX)
            XCTAssertGreaterThan(url.frame.minX, app.windows.firstMatch.frame.midX)
        }
        try launchOpen(["BB_SCANNER_PREVIEW": "1"], demo: false)
        let instructions = expect(app.staticTexts["Point at the QR code"])
        let manual = expect(app.buttons["Enter details manually"])
        XCTAssertLessThan(instructions.frame.maxX, app.windows.firstMatch.frame.midX,
                          "Scanner instructions should stay left of the viewfinder")
        XCTAssertLessThan(manual.frame.maxX, app.windows.firstMatch.frame.midX)
        tap(manual)
        expectGone(instructions)
        expect(app.textFields["Your server URL or IP address"])
    }

}
