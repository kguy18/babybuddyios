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
        tap(search.buttons["Clear text"])
        expect(element(labeled: "Feeding, "))

        tap(pill)
        tap(app.buttons["Leo Rivers"])
        expect(app.buttons.labeled("Current child, Leo"))
    }

    /// A Today tile's day keeps its list left of the fold and opens the tapped record right of it,
    /// as the Timeline tab does.
    func testDayTimelineOpensARecordBesideTheList() throws {
        try launchOpen()
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
}
