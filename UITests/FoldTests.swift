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

    /// Launches with `environment` on the open display's layouts: forced with `BB_FOLD` when the
    /// runner asks for it, and otherwise only on the open display itself, skipping anywhere else.
    /// The app's window tells: 951 pt wide open, against 466 folded and at most 440 on other
    /// iPhones. SpringBoard's frame doesn't, as it still reads the front display's on an open Duo.
    private func launchOpen(_ environment: [String: String] = [:], largestText: Bool = false) throws {
        launch(forced ? environment.merging(["BB_FOLD": "1"]) { $1 } : environment, largestText: largestText)
        guard !forced else { return }
        let width = app.windows.firstMatch.frame.width
        try XCTSkipUnless(width >= 900, "Needs iPhone Duo's open display (scripts/ui-test.sh --duo-open) or "
                          + "TEST_RUNNER_BB_FOLD=1; this window is \(Int(width)) pt wide")
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
        tap(app.alerts.buttons["Delete"])
        expect(empty)
        XCTAssertEqual(rows.count, 1, "Delete should remove the repeated feeding")
    }

    /// The support nudge comes up at the bottom of the pane right of the fold rather than as a card
    /// centred across it, and still takes no for an answer.
    func testSupportNudgeSitsRightOfTheFold() {
        launch(["BB_NUDGE": "gentle", "BB_FOLD": "1"])
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

    /// Two columns can't hold the largest text, so the editor keeps to one, wide as the sheet.
    func testEditorKeepsOneColumnAtTheLargestText() throws {
        try launchOpen(largestText: true)
        openEditor("Feeding")
        expect(app.navigationBars["New Feeding"])
        let when = expect(app.staticTexts["WHEN"]), tags = expect(app.staticTexts["TAGS"])
        XCTAssertEqual(tags.frame.minX, when.frame.minX, accuracy: 1, "Tags should sit under When")
        XCTAssertGreaterThan(tags.frame.minY, when.frame.maxY, "Tags should sit under When")
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

    func testSyncScreensKeepContentBesideTheFold() throws {
        try launchOpen(["BB_START_TAB": "settings", "BB_SEED_PENDING": "1", "BB_OPEN_PENDING": "1"])
        let pending = expect(app.navigationBars["Pending Changes"])
        let title = expect(app.staticTexts["Added Pumping"])
        let queue = expect(app.collectionViews.firstMatch)
        XCTAssertGreaterThan(queue.frame.minX, app.windows.firstMatch.frame.midX,
                             "The whole pending list should stay right of the fold")
        XCTAssertGreaterThan(title.frame.minX, app.windows.firstMatch.frame.midX,
                             "Pending rows should stay right of the fold")
        tap(pending.buttons["Done"])

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

}
