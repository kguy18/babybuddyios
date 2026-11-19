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

    func testGetHelpSignInStaysBesideTheFoldAtLargestText() throws {
        try launchOpen(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"], largestText: true)
        openSendFeedback()
        tap(app.buttons.labeled("Get Help"))
        let email = expect(app.textFields["Email"], timeout: 30)
        let sendCode = expect(app.buttons["Send Code"])
        let middle = app.windows.firstMatch.frame.midX
        XCTAssertGreaterThan(email.frame.minX, middle, "The email field should stay right of the fold")
        XCTAssertGreaterThan(sendCode.frame.minX, middle, "Send Code should stay with the email field")
    }

    func testOfflineGetHelpStaysBesideTheFold() throws {
        try launchOpen(["BB_START_TAB": "settings"])
        openSendFeedback()
        tap(app.buttons.labeled("Get Help"))
        let title = expect(app.staticTexts["Can't reach the feedback server"], timeout: 30)
        let email = expect(app.buttons["Email Support"])
        let middle = app.windows.firstMatch.frame.midX
        XCTAssertGreaterThan(title.frame.minX, middle, "The offline title should stay right of the fold")
        XCTAssertGreaterThan(email.frame.minX, middle, "Email Support should stay with the offline message")
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
        XCTAssertGreaterThan(footer.frame.minX, middle, "The footer should stay with the header card")
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
        XCTAssertGreaterThan(pink.frame.minX, middle)
        tap(pink)
        let cancel = expect(app.buttons["Cancel"])
        XCTAssertGreaterThan(cancel.frame.minX, middle)
        tap(cancel)
        back(from: "Medicine colors")

        tap(app.buttons["Sign out"])
        let signOut = expect(app.alerts.labeled("Sign out of "))
        XCTAssertGreaterThan(expect(signOut.buttons["Cancel"]).frame.minX, middle)
    }

    func testSettingsPickersStayRightOfTheFold() throws {
        try launchOpen(["BB_START_TAB": "settings"])
        let middle = app.windows.firstMatch.frame.midX

        tap(app.buttons.labeled("Today tiles, 4 on"))
        expect(app.navigationBars["Today Tiles"])
        XCTAssertGreaterThan(expect(app.staticTexts["Feedings"]).frame.minX, middle)
        XCTAssertGreaterThan(expect(app.switches["Feedings"]).frame.minX, middle)
        back(from: "Today Tiles")

        tap(app.buttons.labeled("App Icon, Center Peek"))
        expect(app.navigationBars["App Icon"])
        XCTAssertGreaterThan(expect(app.buttons.labeled("Center Peek")).frame.minX, middle)
        back(from: "App Icon")

        tap(app.buttons.labeled("Forgotten timer alerts, Off"))
        expect(app.navigationBars["Forgotten timer alerts"])
        XCTAssertGreaterThan(expect(app.scrollViews.staticTexts["Forgotten timer alerts"]).frame.minX, middle)
        XCTAssertGreaterThan(expect(app.switches["Forgotten timer alerts"]).frame.minX, middle)
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
        let row = elements("label BEGINSWITH 'Feeding, '").element(boundBy: 0)
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
        XCTAssertGreaterThan(expect(app.scrollViews.firstMatch).frame.minX, midX,
                             "The release list should sit right of the fold")
        tap(app.buttons["Continue"])
        expectGone(app.buttons["Continue"])
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

    /// Two columns can't hold the largest text, so the editor keeps to one, wide as the sheet.
    func testEditorKeepsOneColumnAtTheLargestText() throws {
        try launchOpen(largestText: true)
        openEditor("Feeding")
        expect(app.navigationBars["New Feeding"])
        let when = expect(app.staticTexts["WHEN"]), tags = expect(app.staticTexts["TAGS"])
        XCTAssertEqual(tags.frame.minX, when.frame.minX, accuracy: 1, "Tags should sit under When")
        XCTAssertGreaterThan(tags.frame.minY, when.frame.maxY, "Tags should sit under When")
    }

    func testTimerSheetsKeepOneColumnAtTheLargestText() throws {
        try launchOpen(largestText: true)
        tap(app.buttons["Stop"])
        expect(app.navigationBars["Stop Timer"])
        let stopScroll = app.scrollViews["screen-stop-timer"]
        let feeding = app.buttons["Feeding"]
        reveal(feeding, in: stopScroll)
        let sleep = expect(app.buttons["Sleep"])
        XCTAssertGreaterThan(sleep.frame.minY, feeding.frame.maxY)
        let resume = app.buttons["Resume timer"]
        reveal(resume, in: stopScroll)
        XCTAssertGreaterThan(resume.frame.minY, app.buttons["Pumping"].frame.maxY)
        tap(resume)
        expectGone(app.navigationBars["Stop Timer"])

        tap(app.buttons["Add"])
        tap(app.buttons["Start timer"])
        expect(app.navigationBars["Start Timer"])
        let startScroll = app.scrollViews["screen-start-timer"]
        XCTAssertGreaterThan(app.buttons["Sleep"].frame.minY, app.buttons["Feeding"].frame.maxY)
        reveal(app.buttons["Sleep"], in: startScroll)
        tap(app.buttons["Sleep"])
        let start = app.buttons["Start sleep timer"]
        reveal(start, in: startScroll)
        XCTAssertGreaterThan(start.frame.minY, app.buttons["Pumping"].frame.maxY)
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
        XCTAssertGreaterThan(row.frame.minX, app.windows.firstMatch.frame.midX,
                             "The inbox should stay in one pane")
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
