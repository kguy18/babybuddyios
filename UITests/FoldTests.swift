import XCTest

/// iPhone Duo's open display (#215). XCUITest can't unfold a Duo, so `BB_FOLD=1` lays out the screens
/// and sheets as the open display does on whatever simulator runs these. On a phone the panes are
/// cramped: these check where things go and that they still work, not how they look.
final class FoldTests: UITestCase {
    /// The tapped record opens right of the list, ready to edit, with Save, Repeat and Delete in the
    /// toolbar. Each of them closes the pane again.
    func testTimelineOpensARecordBesideTheList() {
        launch(["BB_START_TAB": "timeline", "BB_FOLD": "1", "BB_TOAST_SECONDS": "30"])
        let empty = app.staticTexts["No activity open"]
        let rows = elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, night'")
        expect(empty)

        let row = rows.element(boundBy: 0)
        tap(row)
        let editorSave = expect(app.buttons["Save Feeding"])
        XCTAssertGreaterThan(editorSave.frame.minX, row.frame.maxX - 1, "The editor should open right of the list")
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

    /// Each sheet takes two columns, or for Add Activity one row of six per group.
    func testSheetsUseTwoColumns() {
        launch(["BB_FOLD": "1"])

        tap(app.buttons["Add"])
        tap(app.buttons.labeled("More…"))
        expect(app.navigationBars["Add Activity"])
        XCTAssertEqual(app.buttons["Feeding"].frame.midY, app.buttons["Note"].frame.midY, accuracy: 1,
                       "Every log kind should sit on one row")

        tap(app.buttons["Feeding"])
        let editor = expect(app.navigationBars["New Feeding"])
        XCTAssertGreaterThan(app.staticTexts["TAGS"].frame.minX, app.staticTexts["WHEN"].frame.minX + 50,
                             "Tags should sit right of When")
        tap(editor.buttons["Cancel"])
        expectGone(editor)

        // The seeded tummy time timer.
        tap(app.buttons["Stop"])
        expect(app.navigationBars["Stop Timer"])
        let resume = expect(app.buttons["Resume timer"])
        let restart = app.buttons["Restart from now"]
        // The summary, not a tile: below a half-height sheet the grid hasn't drawn its tiles.
        XCTAssertGreaterThan(resume.frame.minX, element(labeled: "Stopped after ").frame.maxX - 1,
                             "The choices should sit right of the summary")
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
