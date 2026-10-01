import XCTest

/// The Editor's Baby picker (`EntityEditorView/showsChildPicker`): hidden for a single-child
/// household, offered and functional once there's a second child to move a record to.
final class ReassignChildTests: UITestCase {
    /// The demo household has just Maya, so the gate (`children.count > 1`) should keep the
    /// picker off the Editor entirely.
    func testPickerHiddenWithOneChild() {
        launch(["BB_START_TAB": "timeline"])
        let row = elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, night'").firstMatch
        expect(row).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))
        tap(app.buttons["Edit"])
        expect(app.navigationBars["Edit Feeding"])

        XCTAssertFalse(app.staticTexts["Baby"].exists, "A single-child household has nothing to reassign to")
    }

    /// With a second child seeded, reassigning a feeding moves it off the original child's
    /// Timeline and onto the new one's — the same move `LocalRepositoryTests.testUpdateReassignsChild`
    /// checks at the repository layer, exercised here end to end through the UI and the
    /// ChildSwitcher.
    func testReassignMovesActivityToOtherChild() {
        launch(["BB_START_TAB": "timeline", "BB_SEED_SECOND_CHILD": "1"])
        let row = elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, night'").firstMatch
        expect(row).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))
        tap(app.buttons["Edit"])
        let editor = expect(app.navigationBars["Edit Feeding"])

        expect(app.staticTexts["Baby"])
        tap(app.buttons.labeled("Maya Guy")) // the Baby row's current-child menu trigger
        tap(app.buttons["Leo Guy"])
        tap(editor.buttons["Save"])
        expectGone(editor)

        // Still viewing Maya's Timeline: the feeding just left it.
        expectGone(row)

        // Switch to Leo through the ChildSwitcher and find it there instead.
        tap(app.buttons.labeled("Current child, Maya Guy"))
        tap(app.buttons["Leo Guy"])
        expect(row)
    }
}
