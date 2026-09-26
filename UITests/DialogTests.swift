import XCTest

/// Destructive and multi-choice prompts keep a way back. On iOS 26 SwiftUI anchors a
/// `confirmationDialog` to its source as a popover and UIKit drops the cancel action — this shipped
/// three times (#89, #90, #119) before `.alert` and `SignOutDialog` replaced every one.
final class DialogTests: UITestCase {
    // Regression: #119 — the editor's delete prompt had no Cancel on iOS 26.
    func testEditorDeleteAlertHasCancel() {
        launch(["BB_START_TAB": "timeline"])
        // The seeded 90-minutes-ago feeding: the only one carrying tags.
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Feeding, ' AND label CONTAINS 'tags: hungry, night'"))
            .firstMatch
        tap(row)
        let editor = expect(app.navigationBars["Edit Feeding"])

        tap(app.buttons["Delete Feeding"])
        let alert = expect(app.alerts["Delete this feeding?"])
        XCTAssertTrue(alert.buttons["Delete"].exists)
        alert.buttons["Cancel"].tap()
        expectGone(alert)
        XCTAssertTrue(editor.exists, "Cancel should leave the editor open")

        tap(app.buttons["Delete Feeding"])
        tap(app.alerts["Delete this feeding?"].buttons["Delete"])
        expectGone(editor)
        expectGone(row)
    }

    // Regression: #119 — Contact Support's choice of diagnostics had no Cancel on iOS 26.
    func testContactSupportAlertHasCancel() {
        launch(["BB_START_TAB": "settings"])
        let contact = app.buttons.labeled("Contact Support")

        tap(contact)
        let alert = expect(app.alerts["Contact Support"])
        XCTAssertTrue(alert.buttons["Include Device Details"].exists)
        XCTAssertTrue(alert.buttons["Don't Include"].exists)
        alert.buttons["Cancel"].tap()
        expectGone(alert)

        // With no mail account (the simulator) the fallback explains itself rather than doing nothing.
        tap(contact)
        tap(app.alerts["Contact Support"].buttons["Don't Include"])
        tap(app.alerts["Set Up Mail"].buttons["OK"])
    }

    // Regression: #87/#89/#90 — sign-out shipped as a confirmationDialog with no Cancel on iOS 26.
    func testSignOutCard() {
        launch(["BB_START_TAB": "settings", "BB_SEED_PENDING": "1"])
        expect(app.navigationBars["Settings"])

        openSignOut()
        // Each part of the card reads as itself, not all as the card's label.
        XCTAssertTrue(signOutCard.staticTexts["Sign out?"].exists)
        // Unsynced changes are the one thing sign-out destroys that the server can't give back.
        XCTAssertTrue(signOutCard.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "haven't reached this server yet")).firstMatch.exists)
        tap(signOutCard.buttons["Cancel"])
        expectGone(signOutCard)

        // The dim covers the floating tab bar: tapping where "Home" sits cancels, not switches tab.
        openSignOut()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.96)).tap()
        expectGone(signOutCard)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)

        openSignOut()
        tap(signOutCard.buttons["Sign out"])
        expect(app.staticTexts["Connect to your self-hosted server"])
    }

    // Regression: #66 — the login URL shipped prefilled (#1) and App Review rejected it.
    func testOnboardingStartsEmpty() {
        launch(["BB_START_TAB": "settings"])
        openSignOut()
        tap(signOutCard.buttons["Sign out"])

        let url = expect(app.textFields["Your server URL or IP address"])
        let value = url.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == url.placeholderValue, "URL field prefilled with \(value)")
        let connect = app.buttons["Connect"]
        XCTAssertFalse(connect.isEnabled)

        tap(app.buttons["Where do I find these?"])
        tap(app.alerts["Finding your details"].buttons["Got it"])

        url.tap()
        url.typeText("baby.example.com")
        XCTAssertFalse(connect.isEnabled, "Connect needs a token too")
        let token = app.secureTextFields["Paste your API token"]
        token.tap()
        token.typeText("abc")
        XCTAssertTrue(connect.isEnabled)
        token.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        XCTAssertFalse(connect.isEnabled)
    }

    /// #148: the custom header rows, in sign-in's Advanced configuration. A forbidden name is caught
    /// before any request goes out, so this needs no server.
    func testCustomHeaderRows() {
        launch(demo: false)
        let names = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Header name"))
        tap(app.buttons["Advanced configuration"])
        let sheet = expect(app.navigationBars["Advanced configuration"])
        tap(app.buttons["Add header"])
        tap(app.buttons["Add header"])
        XCTAssertEqual(names.count, 2)
        tap(app.buttons["Remove header"].firstMatch)
        expectGone(names.element(boundBy: 1))
        XCTAssertEqual(names.count, 1)
        replaceText(names.firstMatch, with: "Authorization")
        replaceText(app.secureTextFields["Header value"], with: "x")
        tap(sheet.buttons["Done"])
        expectGone(sheet)
        expect(element(labeled: "Advanced configuration"))

        replaceText(app.textFields["Your server URL or IP address"], with: "baby.example.com")
        replaceText(app.secureTextFields["Paste your API token"], with: "abc\n")
        expect(element(labeled: "Authorization carries your API token"))
    }

    /// #148: Settings lists the header names, and an edit that fails keeps the old set. A rejected
    /// name fails before the probe; the demo server's address would take a minute to time out.
    func testCustomHeaderEditInSettings() {
        launch(["BB_START_TAB": "settings"])
        tap(app.buttons.labeled("Custom headers"))
        expect(app.navigationBars["Custom headers"])
        tap(app.buttons["Add header"])
        replaceText(app.textFields["Header name"], with: "Cookie")
        replaceText(app.secureTextFields["Header value"], with: "x")
        tap(app.buttons["Save"])
        expect(element(labeled: "The app sets Cookie itself"))
        tap(app.navigationBars.buttons["Settings"])
        expect(element(labeled: "Custom headers"))
        XCTAssertTrue(app.staticTexts["None"].exists, "a failed edit saved the headers")
    }

    /// Anyone whose camera is refused — or who simply has the token on a clipboard — needs the way
    /// back out of the scanner, and it's the same screen App Review saw (#4, #15).
    /// `BB_SCANNER_PREVIEW` opens it over a black backdrop, so no camera is involved.
    func testScannerOffersManualEntry() {
        launch(["BB_SCANNER_PREVIEW": "1"], demo: false)
        expect(app.staticTexts["Point at the QR code"])
        expect(app.staticTexts["Scan QR code"])
        tap(elements("label CONTAINS 'Enter details manually'").firstMatch)
        expectGone(app.staticTexts["Point at the QR code"])
        expect(app.textFields["Your server URL or IP address"])
    }

    /// The sign-out card, which its modal trait exposes as an alert. Its buttons are queried inside
    /// it: the Settings row behind the clear cover is also a "Sign out" button, and still in the tree.
    private var signOutCard: XCUIElement {
        app.alerts.labeled("Sign out of ")
    }

    private func openSignOut() {
        tap(app.buttons["Sign out"])
        expect(signOutCard)
    }
}
