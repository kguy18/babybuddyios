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

    /// Settings ▸ App Icon offers all six icons with none of them locked, marks the one in use, and
    /// names it on the row that opens it (#62).
    ///
    /// It stops short of tapping one. Switching is a `UIApplication.setAlternateIconName` round
    /// trip, and the simulator doesn't honour it reliably: over repeated runs the change took
    /// sometimes and the switch *back* to the primary icon never did, with no error from the API —
    /// the same reason ``AppIconOption/matching(alternateIconName:)`` is the part covered by unit
    /// tests. The manual checklist keeps the tap.
    func testAppIconPicker() {
        launch(["BB_START_TAB": "settings"])
        tap(app.buttons.labeled("App Icon, Center Peek")) // the row names the icon in use
        let bar = expect(app.navigationBars["App Icon"])

        let centerPeek = iconTile("Center Peek")
        expect(centerPeek)
        XCTAssertTrue(centerPeek.isSelected, "The primary icon is the one on the Home Screen")
        for icon in ["Happy Low Peek", "Low Peek", "Peek Wave", "Side Peek Left", "Side Peek Right"] {
            let tile = iconTile(icon)
            XCTAssertTrue(tile.exists, "\(icon) is missing from the grid")
            XCTAssertFalse(tile.isSelected, "\(icon) shouldn't be marked as the current icon")
            XCTAssertTrue(tile.isHittable, "\(icon) should be pickable — every icon is free")
        }

        tap(bar.buttons.firstMatch) // back
        expect(app.buttons.labeled("App Icon, Center Peek"))
    }

    /// What's New sits with the supporter row, above the fold, and opens the same card Settings
    /// always had — with Done, since nothing is being continued.
    func testWhatsNewRowUnderSupporter() {
        launch(["BB_START_TAB": "settings"])
        let supporter = expect(app.buttons.labeled("Baby Buddy App Supporter"))
        let whatsNew = expect(app.buttons.labeled("What's New"))
        XCTAssertGreaterThan(whatsNew.frame.minY, supporter.frame.minY, "What's New is under the supporter row")
        XCTAssertLessThan(whatsNew.frame.minY, app.staticTexts["SERVER"].frame.minY, "What's New is in Support the app")

        tap(whatsNew)
        expect(app.staticTexts["What's New"])
        tap(app.buttons["Done"])
        expectGone(app.staticTexts["Version 1.1.0"])
    }

    /// Settings ▸ Feedback: Send Feedback, the source code and the App Store review, in that order.
    /// Contact Support and Request a Feature moved onto the Send Feedback screen.
    func testFeedbackSection() {
        launch(["BB_START_TAB": "settings"])
        expect(app.staticTexts["FEEDBACK"])
        XCTAssertFalse(app.staticTexts["HELP"].exists)
        let rows = ["Send Feedback", "Source Code on GitHub", "Rate on the App Store"].map { element(labeled: $0) }
        for row in rows { expect(row) }
        XCTAssertLessThan(rows[0].frame.minY, rows[1].frame.minY)
        XCTAssertLessThan(rows[1].frame.minY, rows[2].frame.minY)
        XCTAssertFalse(app.buttons.labeled("Contact Support").exists)
        XCTAssertFalse(app.buttons.labeled("Request a Feature").exists)
    }

    /// The note says how posting works, and the hint promises only what Copy app details holds.
    func testSendFeedbackSignInLineAndHint() {
        launch(["BB_START_TAB": "settings"])
        openSendFeedback()
        expect(app.staticTexts["To post, vote or chat, you'll sign in with your email. No password needed."])
        XCTAssertTrue(app.staticTexts["Paste them into your message so I can see your version and device."].exists)
    }

    // MARK: Feedback sign-in
    //
    // The stub (`BB_FEEDBACK_STUB`) stands in for Quackback: any email gets a code except one
    // starting `busy@`, which hits the rate limit; the code `000000` and the password `wrong` are
    // refused; anything else signs in. Its widget is signed in when the web view holds the session
    // cookie the sign-in wrote, so these tests cover the hand-off too.

    /// Signed out, Get Help shows the sign-in in place of the chat, with Get Help's reason, and
    /// a code lands in the chat.
    func testGetHelpSignsInWithACodeAndOpensTheChat() {
        openGetHelpSignedOut()
        let sheet = app.navigationBars["Get Help"]
        expect(app.staticTexts["Sign in with your email so I can reply to you."])
        XCTAssertFalse(sheet.buttons["Sign In"].exists, "The sign-in is already on screen")
        XCTAssertFalse(app.buttons["Send Code"].isEnabled, "No email yet")

        signInWithCode()
        expect(app.webViews.staticTexts["Stub widget: chat"], timeout: 30)
        XCTAssertFalse(app.staticTexts["Sign in with your email so I can reply to you."].exists)
        tap(sheet.buttons["Close"])
        expectGone(sheet)
    }

    /// Signed in, Get Help opens straight to the chat: no sign-in, no Sign In. A device showed a
    /// signed-in user the sign-in when an anonymous identify made Quackback report a stale null user.
    func testGetHelpSignedInOpensTheChat() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-in"])
        openSendFeedback()
        tap(app.buttons.labeled("Get Help"))
        let sheet = expect(app.navigationBars["Get Help"])
        expect(app.webViews.staticTexts["Stub widget: chat"])
        XCTAssertFalse(app.staticTexts["Sign in with your email so I can reply to you."].exists)
        XCTAssertFalse(sheet.buttons["Sign In"].exists)
        tap(sheet.buttons["Close"])
        expectGone(sheet)
    }

    /// Request a Feature's Sign In pushes the sign-in with the board's reason, and a code lands
    /// back on the board, signed in.
    func testFeatureRequestSignsInWithACodeAndReturnsToTheBoard() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"])
        openSendFeedback()
        tap(app.buttons.labeled("Request a Feature"))
        let board = expect(app.navigationBars["Request a Feature"])
        expect(app.webViews.staticTexts["Stub widget: new-post"])
        tap(board.buttons["Sign In"])
        expect(app.staticTexts["Sign in with your email to post and vote."])

        signInWithCode()
        expect(app.webViews.staticTexts["Stub widget: new-post"], timeout: 30)
        XCTAssertFalse(app.staticTexts["Sign in with your email to post and vote."].exists, "Back on the board")
        XCTAssertFalse(board.buttons["Sign In"].exists, "Signed in now")
        tap(board.buttons["Close"])
        expectGone(board)
    }

    /// A wrong code shows its error under the field and stays on the code step, with Resend still
    /// counting down; "Use a different email" goes back to the email step.
    func testWrongCodeShowsTheErrorAndADifferentEmailGoesBack() {
        openGetHelpSignedOut()
        enterEmailAndSendCode()
        tap(app.textFields["Code"])
        app.textFields["Code"].typeText("000000")
        expect(app.staticTexts["That code didn't work. Check the latest email, or send a new code."])
        let resend = element(labeled: "Resend code in")
        XCTAssertTrue(resend.exists, "Resend waits 30 seconds after a send")
        XCTAssertFalse(resend.isEnabled)

        tap(app.buttons["Use a different email"])
        expect(app.buttons["Send Code"])
        XCTAssertFalse(app.staticTexts["That code didn't work. Check the latest email, or send a new code."].exists)
    }

    /// The server's rate limit shows its error and disables the buttons until its window ends.
    func testRateLimitDisablesTheButtons() {
        openGetHelpSignedOut()
        tap(app.textFields["Email"])
        app.textFields["Email"].typeText("busy@example.com")
        tap(app.buttons["Send Code"])
        expect(app.staticTexts["Too many tries. Wait a few minutes, then try again."])
        XCTAssertFalse(app.buttons["Send Code"].isEnabled)
        tap(app.buttons["Use a password instead"])
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("correct horse")
        XCTAssertFalse(app.buttons["Sign In"].isEnabled, "The wait covers the password too")
    }

    /// The widget's own sign-in link opens the native sign-in. A wrong password shows its error, "Use
    /// an email code instead" goes back, and the right one lands on the board signed in.
    func testPasswordSignIn() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"])
        openSendFeedback()
        tap(app.buttons.labeled("Request a Feature"))
        let board = expect(app.navigationBars["Request a Feature"])
        tap(app.webViews.links["Sign in to post"])
        tap(app.buttons["Use a password instead"])
        tap(app.textFields["Email"])
        app.textFields["Email"].typeText("parent@example.com")
        let password = app.secureTextFields["Password"]
        tap(password)
        password.typeText("wrong\n")
        expect(app.staticTexts["That email and password don't match."])
        XCTAssertTrue(app.buttons["Forgot password?"].exists)

        tap(app.buttons["Use an email code instead"])
        expect(app.buttons["Send Code"])
        XCTAssertFalse(app.secureTextFields["Password"].exists)

        tap(app.buttons["Use a password instead"])
        tap(password)
        password.typeText("correct horse\n")
        expect(app.webViews.staticTexts["Stub widget: new-post"], timeout: 30)
        XCTAssertFalse(board.buttons["Sign In"].exists, "Signed in now")
    }

    /// Sign Out of Feedback shows only while signed in, and the next sheet opens signed out.
    func testSignOutOfFeedback() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-in"])
        openSendFeedback()
        let signOut = element(labeled: "Sign Out of Feedback")
        tap(signOut)
        expect(app.staticTexts["Signed out of feedback"])
        expectGone(signOut)

        tap(app.buttons.labeled("Request a Feature"))
        let board = expect(app.navigationBars["Request a Feature"])
        expect(board.buttons["Sign In"])
        tap(board.buttons["Close"])
        expectGone(board)
        XCTAssertFalse(signOut.exists)
    }

    /// The session outlives a relaunch: straight after it, Send Feedback offers Sign Out and the
    /// board opens signed in. The app goes to the Home Screen before it's killed, as it does when
    /// someone quits it, since WebKit writes its cookies to disk only now and then.
    func testSignInSurvivesARelaunch() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"])
        openSendFeedback()
        XCTAssertFalse(element(labeled: "Sign Out of Feedback").exists)
        tap(app.buttons.labeled("Request a Feature"))
        let board = expect(app.navigationBars["Request a Feature"])
        tap(board.buttons["Sign In"])
        signInWithCode()
        expect(app.webViews.staticTexts["Stub widget: new-post"], timeout: 30)
        tap(board.buttons["Close"])

        pressHome()
        sleep(2)
        app.terminate()
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out", "BB_FEEDBACK_KEEP_SESSION": "1"])
        openSendFeedback()
        expect(element(labeled: "Sign Out of Feedback"))
        tap(app.buttons.labeled("Request a Feature"))
        expect(app.webViews.staticTexts["Stub widget: new-post"], timeout: 30)
        XCTAssertFalse(board.buttons["Sign In"].exists, "Still signed in")
    }

    private func openGetHelpSignedOut() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"])
        openSendFeedback()
        tap(app.buttons.labeled("Get Help"))
        expect(app.navigationBars["Get Help"])
    }

    private func enterEmailAndSendCode() {
        tap(app.textFields["Email"])
        app.textFields["Email"].typeText("parent@example.com")
        tap(app.buttons["Send Code"])
        expect(app.staticTexts["Enter the 6-digit code we sent to parent@example.com."])
    }

    /// Email, Send Code, then a code that the field submits on its sixth digit.
    private func signInWithCode() {
        enterEmailAndSendCode()
        tap(app.textFields["Code"])
        app.textFields["Code"].typeText("123456")
    }

    /// Send Feedback: the note and its four links, the supporter link opening its sheet, each way
    /// into the feedback widget opening and closing, and Copy app details confirming. The sheets
    /// load the stub widget, so this needs no network.
    func testSendFeedbackScreen() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"])
        openSendFeedback()

        expect(element(labeled: "Hi, I'm Kurtis."))
        XCTAssertFalse(element(labeled: "Sign Out of Feedback").exists, "Signed out: no sign-out row")
        XCTAssertTrue(element(labeled: "I do read everything").exists)
        XCTAssertTrue(element(labeled: "This app is an independent client").exists)
        for link in ["Kurtis", "open source on GitHub", "supporters like you", "their GitHub"] {
            XCTAssertTrue(app.links[link].exists, "\(link) should be a link")
        }

        tap(app.links["supporters like you"])
        tap(app.buttons["Maybe later"])
        expectGone(app.buttons["Maybe later"])

        for (button, title) in [("Request a Feature", "Request a Feature"), ("Get Help", "Get Help"),
                                ("See roadmap and updates", "Roadmap and Updates")] {
            tap(app.buttons.labeled(button))
            let sheet = expect(app.navigationBars[title])
            tap(sheet.buttons["Close"])
            expectGone(sheet)
        }

        tap(app.buttons["Copy app details"])
        expect(app.staticTexts["App details copied"])
        XCTAssertFalse(app.buttons["Undo"].exists, "A confirmation has nothing to undo")
        XCTAssertTrue(app.staticTexts.labeled("Paste them into your message").exists)
    }

    /// With the feedback server unreachable, Request a Feature offers email, and that leads to the
    /// mail flow (`DialogTests.testContactSupportAlertHasCancel` covers it from Get Help).
    func testFeatureRequestFallsBackToMail() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK": DialogTests.unreachableServer])
        openSendFeedback()
        tap(app.buttons.labeled("Request a Feature"))
        let sheet = expect(app.navigationBars["Request a Feature"])
        expect(app.staticTexts["Can't reach the feedback server"], timeout: 6)
        tap(app.buttons["Email Support"])
        expectGone(sheet)
        tap(app.alerts["Contact Support"].buttons["Don't Include"])
        tap(app.alerts["Set Up Mail"].buttons["OK"])
    }

    /// The footer credit for upstream Baby Buddy — a licence obligation, not decoration (#46).
    func testAcknowledgements() {
        launch(["BB_START_TAB": "settings"])
        tap(app.buttons["Acknowledgements"])
        let sheet = expect(app.navigationBars["Acknowledgements"])
        expect(app.staticTexts["Based on Baby Buddy"])
        expect(app.buttons.labeled("github.com/babybuddy/babybuddy"))
        tap(sheet.buttons["Done"])
        expectGone(sheet)
    }

    /// The Dashboard says how fresh its numbers are, and Settings decides when "fresh" runs out
    /// (#117). The demo pull stamps a sync, so the stamp is there from launch.
    func testFreshnessStampAndStaleAfter() {
        launch()
        expect(element(labeled: "Updated "))

        tap(app.tabBars.buttons["Settings"])
        expect(app.staticTexts["Stale after"])
        tap(app.buttons["30 min"]) // the row's menu, showing the default
        tap(app.buttons["15 min"])
        expect(app.buttons["15 min"])

        tap(app.buttons["15 min"])
        tap(app.buttons["Off"]) // never stale
        expect(app.buttons["Off"])

        tap(app.tabBars.buttons["Home"])
        expect(element(labeled: "Updated ")) // still stamped, just never stale
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

    // MARK: Helpers

    /// A tile in the icon grid. Each one is a button inside a button, so the query has to pick the
    /// outer one — and by index rather than with `firstMatch`, which caches the snapshot it
    /// resolved and would answer `isSelected` from before the grid drew.
    private func iconTile(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", name)).element(boundBy: 0)
    }
}
