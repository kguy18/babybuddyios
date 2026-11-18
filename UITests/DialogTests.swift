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

    /// Nothing listens here, so the widget's load fails with "can't connect" in about a second. The
    /// tests wait 6 seconds, under the sheet's 8-second ready timeout, so they fail if a refused
    /// connection stops showing the fallback at once. Not port 1: WebKit blocks it as a restricted
    /// port without telling the navigation delegate, so only the timeout catches it.
    static let unreachableServer = "https://127.0.0.1:2"

    // Regression: #119 — Contact Support's choice of diagnostics had no Cancel on iOS 26. That choice
    // now comes up from Send Feedback ▸ Get Help when the feedback server can't be reached and the
    // user picks email instead.
    func testContactSupportAlertHasCancel() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK": Self.unreachableServer])
        openSendFeedback()

        emailSupportFromGetHelp()
        let alert = expect(app.alerts["Contact Support"])
        XCTAssertTrue(alert.buttons["Include Device Details"].exists)
        XCTAssertTrue(alert.buttons["Don't Include"].exists)
        alert.buttons["Cancel"].tap()
        expectGone(alert)

        // With no mail account (the simulator) the fallback explains itself rather than doing nothing.
        emailSupportFromGetHelp()
        tap(app.alerts["Contact Support"].buttons["Don't Include"])
        tap(app.alerts["Set Up Mail"].buttons["OK"])
    }

    private func emailSupportFromGetHelp() {
        tap(app.buttons.labeled("Get Help"))
        let sheet = expect(app.navigationBars["Get Help"])
        expect(app.staticTexts["Can't reach the feedback server"], timeout: 6)
        tap(app.buttons["Email Support"])
        expectGone(sheet)
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
        XCTAssertTrue(tab("Settings").isSelected)

        openSignOut()
        tap(signOutCard.buttons["Sign out"])
        expect(app.staticTexts["Connect to your self-hosted server"])
    }

    func testSignOutCardAtLargestText() {
        launch(["BB_START_TAB": "settings"], largestText: true)
        openSignOut()
        expect(signOutCard.staticTexts["Sign out?"])
        let cancel = expect(signOutCard.buttons["Cancel"])
        let confirm = expect(signOutCard.buttons["Sign out"])
        attachSickSettingsScreen("settings-sign-out-dialog")
        XCTAssertGreaterThan(confirm.frame.minY, cancel.frame.maxY)
        XCTAssertTrue(confirm.isHittable)
        tap(cancel)
        expectGone(signOutCard)

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
        tap(app.buttons["Add another header"])
        XCTAssertEqual(names.count, 2)
        tap(app.buttons["Remove header"].firstMatch)
        expectGone(names.element(boundBy: 1))
        XCTAssertEqual(names.count, 1)
        replaceText(names.firstMatch, with: "Authorization")
        replaceText(app.secureTextFields["Header value"], with: "x")
        tap(app.buttons["Save"])
        expectGone(sheet)
        expect(element(labeled: "Advanced configuration"))

        replaceText(app.textFields["Your server URL or IP address"], with: "baby.example.com")
        replaceText(app.secureTextFields["Paste your API token"], with: "abc\n")
        expect(element(labeled: "Authorization carries your API token"))
    }

    /// #148: after Cloudflare Access answers, Advanced configuration shows where sign-in stopped,
    /// asks for the service token by name, and shows the way through once it's filled in.
    /// `BB_GATE_PREVIEW` stands in for the gate.
    func testCloudflareServiceTokenSheet() {
        launch(["BB_GATE_PREVIEW": "cloudflareAccess"], demo: false)
        expect(app.navigationBars["Advanced configuration"])
        expect(element(labeled: "Where sign-in stopped"))
        expect(app.staticTexts["Stopped here"])
        let retry = app.buttons["Save and try again"]
        XCTAssertFalse(retry.isEnabled, "nothing to send yet")

        // Return on the Client ID moves to the Client Secret: typing there without a tap fails unless
        // it has keyboard focus.
        replaceText(app.textFields["Client ID"], with: "abc.access\n")
        expect(app.secureTextFields["Client Secret"]).typeText("s3cret\n")
        expect(element(labeled: "On the next try"))
        expectGone(app.staticTexts["Stopped here"])
        XCTAssertTrue(retry.isEnabled)

        revealSheetBar("Advanced configuration")
        tap(app.buttons["Cancel"])
        expectGone(app.navigationBars["Advanced configuration"])
        XCTAssertFalse(app.buttons.labeled("Advanced configuration ·").exists, "Cancel kept the edits")
    }

    /// #241: a Client ID copied from text that wrapped carries a line break the field can't show.
    /// Paste drops it, and a space along with it, rather than refusing the value at Save.
    /// `BB_PASTEBOARD` stands in for the copy: a write from this runner never reaches the app.
    func testPastedServiceTokenLosesItsLineBreak() {
        launch(["BB_GATE_PREVIEW": "cloudflareAccess", "BB_PASTEBOARD": "88bf3b6d8616\n1464f650 9f72.access\n"],
               demo: false)
        expect(app.navigationBars["Advanced configuration"])
        // By identifier: "Paste" is also the API token's button on the sign-in screen behind the sheet.
        tap(app.buttons["Paste CF-Access-Client-Id"])
        expectValue(app.textFields["Client ID"], "88bf3b6d86161464f6509f72.access")
    }

    /// #241: a sign-in that fails before any request goes out shows its error on the sign-in
    /// screen, once. Before, the gate from the try before was still recorded, so sign-in put
    /// Advanced configuration straight back over the error, and Save and try again looped. The
    /// address is left empty so the failure needs no server; a bad header fails the same way.
    func testAValidationErrorDoesNotReopenAdvancedConfiguration() {
        launch(["BB_GATE_PREVIEW": "cloudflareAccess"], demo: false)
        let sheet = app.navigationBars["Advanced configuration"]
        expect(sheet)
        replaceText(app.textFields["Client ID"], with: "abc.access\n")
        expect(app.secureTextFields["Client Secret"]).typeText("s3cret\n")
        tap(app.buttons["Save and try again"])
        expectGone(sheet)
        expect(element(labeled: "That doesn't look like a valid server address"))
        XCTAssertFalse(sheet.exists, "the error reopened Advanced configuration")
    }

    /// At the largest text size nothing is pinned over the sheet: Save and its note took half of it.
    /// Both scroll with the content, and the fields grow with the text.
    func testAdvancedConfigurationFitsTheLargestText() {
        launch(["BB_GATE_PREVIEW": "cloudflareAccess"], demo: false, largestText: true)
        expect(app.navigationBars["Advanced configuration"])
        let field = expect(app.textFields["Client ID"])
        let note = expect(app.staticTexts["Sent with every request to your server, never to another address."])
        let save = expect(app.buttons["Save and try again"])
        XCTAssertGreaterThan(note.frame.minY, field.frame.maxY, "The note should follow the fields")
        XCTAssertGreaterThan(save.frame.minY, note.frame.maxY, "Save should follow the note")
        XCTAssertGreaterThan(save.frame.maxY, app.windows.firstMatch.frame.maxY, "Save should scroll, not cover the sheet")
        XCTAssertGreaterThan(field.frame.height, 40, "The field should grow with the text")
        let stopped = app.staticTexts["Stopped here"]
        XCTAssertGreaterThan(stopped.frame.width, stopped.frame.height, "\"Stopped here\" should fit on one line")
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
        back(from: "Custom headers")
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

    func testOnboardingFitsTheLargestText() {
        launch(demo: false, largestText: true)
        let title = expect(app.staticTexts["Baby Buddy"])
        XCTAssertGreaterThan(title.frame.height, 50, "The welcome title should scale")
        let divider = expect(app.staticTexts["or enter details"])
        XCTAssertGreaterThan(divider.frame.width, divider.frame.height, "The divider should have room for words")
        let url = expect(app.textFields["Your server URL or IP address"])
        XCTAssertGreaterThan(url.frame.height, 40, "The URL should scale with its label")
        replaceText(url, with: "127.0.0.1:2\n")
        let token = expect(app.secureTextFields["Paste your API token"])
        XCTAssertGreaterThan(token.frame.height, 40, "The token should scale with its label")
        token.typeText("abc")
        let filled = XCTAttachment(screenshot: app.screenshot())
        filled.name = "onboarding-filled"
        filled.lifetime = .keepAlways
        add(filled)
        token.typeText("\n")
        expect(app.staticTexts["Couldn't connect"])
        let retry = expect(app.buttons["Try again"])
        XCTAssertTrue(retry.isEnabled)
        XCTAssertEqual(url.value as? String, "127.0.0.1:2", "A failed connection should keep the URL")
        let error = XCTAttachment(screenshot: app.screenshot())
        error.name = "onboarding-connect-error"
        error.lifetime = .keepAlways
        add(error)
    }

    func testScannerFitsTheLargestText() {
        launch(["BB_SCANNER_PREVIEW": "1"], demo: false, largestText: true)
        let title = expect(app.staticTexts["Scan QR code"].firstMatch)
        XCTAssertGreaterThan(title.frame.height, 40, "The scanner title should scale")
        let heading = expect(app.staticTexts["Point at the QR code"])
        let instructions = expect(app.staticTexts["Open User → Add a Device on your Baby Buddy site to show your login code."])
        let manual = expect(app.buttons["Enter details manually"])
        XCTAssertGreaterThan(heading.frame.minY, title.frame.maxY, "The viewfinder should clear the header")
        XCTAssertGreaterThan(manual.frame.minY, instructions.frame.maxY, "Manual entry should follow the instructions")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "qr-scanner-preview"
        shot.lifetime = .keepAlways
        add(shot)
        tap(manual)
        expectGone(heading)
        expect(app.staticTexts["Connect to your self-hosted server"])
    }

    func testDeniedScannerCanScrollToManualEntryAtTheLargestText() {
        launch(demo: false, largestText: true)
        tap(app.buttons.labeled("Scan QR code"))
        refuseCameraIfAsked()
        expect(app.staticTexts["Camera Access Needed"])
        let settings = expect(app.buttons["Open Settings"])
        let manual = expect(app.buttons["Enter details manually"])
        XCTAssertGreaterThan(manual.frame.minY, settings.frame.maxY)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "onboarding-scan-qr-no-camera"
        shot.lifetime = .keepAlways
        add(shot)
        tap(manual)
        expectGone(app.staticTexts["Camera Access Needed"])
        expect(app.staticTexts["Connect to your self-hosted server"])
    }

    /// Opt-in evidence capture. The same test runs against main and the fix, without layout assertions.
    func testOnboardingInventoryScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BB_CAPTURE_INVENTORY"] == "1",
                          "Only run while capturing the onboarding inventory")
        let large = ProcessInfo.processInfo.environment["BB_CAPTURE_DEFAULT"] != "1"
        func capture(_ name: String) {
            if large {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = name
                shot.lifetime = .keepAlways
                add(shot)
            } else {
                for (index, screen) in XCUIScreen.screens.enumerated() {
                    let shot = XCTAttachment(screenshot: screen.screenshot())
                    shot.name = "\(name)-display-\(index)"
                    shot.lifetime = .keepAlways
                    add(shot)
                }
            }
        }
        launch(demo: false, largestText: large)
        capture("onboarding")
        app.swipeUp()
        capture("onboarding-scrolled")
        replaceText(app.textFields["Your server URL or IP address"], with: "127.0.0.1:2\n")
        let token = expect(app.secureTextFields["Paste your API token"])
        token.typeText("abc")
        capture("onboarding-filled")
        token.typeText("\n")
        tap(app.staticTexts["Couldn't connect"])
        capture("onboarding-connect-error")

        launch(["BB_SCANNER_PREVIEW": "1"], demo: false, largestText: large)
        expect(app.staticTexts["Point at the QR code"])
        capture("qr-scanner-preview")
        app.swipeUp()
        app.swipeUp()
        capture("qr-scanner-preview-scrolled")

        launch(demo: false, largestText: large)
        tap(app.buttons.labeled("Scan QR code"))
        refuseCameraIfAsked()
        expect(app.staticTexts["Camera Access Needed"])
        capture("onboarding-scan-qr-no-camera")
        app.swipeUp()
        app.swipeUp()
        capture("onboarding-scan-qr-no-camera-scrolled")
    }

    private func refuseCameraIfAsked() {
        if app.staticTexts["Camera Access Needed"].exists { return }
        let refuse = springboard.alerts.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch
        if refuse.waitForExistence(timeout: 15) { refuse.tap() }
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
