import XCTest

final class SettingsTests: UITestCase {
    /// Nothing is for sale without a purchase backend, and the sheet says so rather than offering
    /// amounts that can't be bought (#58). Supporters see their status (#57).
    func testSupporterSheet() {
        launch(["BB_START_TAB": "settings"])
        tap(app.buttons.labeled("Baby Buddy App Supporter"))
        expect(app.staticTexts["Purchases aren't available in this build."])
        XCTAssertFalse(app.buttons.labeled("Tip").exists)
        tap(app.buttons["Maybe later"])
        expectGone(app.staticTexts["Purchases aren't available in this build."])

        // The nudges' and widgets' link opens the same sheet.
        app.open(URL(string: "babybuddy://supporter")!)
        expect(app.buttons["Maybe later"])

        launch(["BB_START_TAB": "settings", "BB_SUPPORTER": "1"])
        expect(app.buttons.labeled("Baby Buddy App Supporter, Active"))
    }

    /// Settings ▸ Undo after logging turns the toast off (#115).
    func testUndoAfterLoggingOff() {
        launch(["BB_START_TAB": "settings"])
        let undo = app.switches["Undo after logging"]
        expect(undo)
        XCTAssertEqual(undo.value as? String, "1")
        undo.tap()
        XCTAssertEqual(undo.value as? String, "0")

        tap(app.tabBars.buttons["Home"])
        openEditor("Diaper")
        let bar = expect(app.navigationBars["New Diaper Change"])
        tap(app.buttons["Save Diaper Change"])
        expectGone(bar)
        XCTAssertFalse(app.otherElements["Logged Diaper Change"].waitForExistence(timeout: 3))
    }
}
