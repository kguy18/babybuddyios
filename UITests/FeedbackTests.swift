import XCTest

/// Settings ▸ Send Feedback and signing in to the feedback site. A class apart from SettingsTests
/// so each CI shard stays short enough for the iPhone Duo lane's 30 minutes.
///
/// The stub (`BB_FEEDBACK_STUB`) stands in for Quackback: any email gets a code except one
/// starting `busy@`, which hits the rate limit; the code `000000` and the password `wrong` are
/// refused; anything else signs in. Its widget is signed in when the web view holds the session
/// cookie the sign-in wrote, so these tests cover the hand-off too.
final class FeedbackTests: UITestCase {
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
        expect(app.buttons.labeled("Feedback Account"))
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




    /// Send Feedback: the note and its four links, the supporter link opening its sheet, and each
    /// way into the feedback widget opening and closing. Signed out, there's no Feedback Account
    /// row. The sheets load the stub widget, so this needs no network.
    func testSendFeedbackScreen() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"])
        openSendFeedback()

        expect(element(labeled: "Hi, I'm Kurtis."))
        XCTAssertTrue(element(labeled: "I do read everything").exists)
        XCTAssertTrue(app.staticTexts.element(matching: NSPredicate(format: "label == %@",
            "To post, vote, or chat, you'll sign in with your email - this account is only on the feedback system and not related to your own hosted Baby Buddy instance. No password needed. Sign in with a code.")).exists)
        XCTAssertTrue(element(labeled: "This app is an independent client").exists)
        for link in ["Kurtis", "open source on GitHub", "supporters like you", "their GitHub"] {
            XCTAssertTrue(app.links[link].exists, "\(link) should be a link")
        }

        tap(app.links["supporters like you"])
        tap(app.buttons["Maybe later"])
        expectGone(app.buttons["Maybe later"])
        XCTAssertFalse(app.buttons.labeled("Feedback Account").exists, "Signed out: no account row")
        XCTAssertFalse(app.buttons["Copy app details"].exists, "Moved to Get Help")
        XCTAssertFalse(app.buttons.labeled("See roadmap and updates").exists, "Now a row")

        for title in ["Request a Feature", "Get Help", "Roadmap and Updates"] {
            tap(app.buttons.labeled(title))
            let sheet = expect(app.navigationBars[title])
            tap(sheet.buttons["Close"])
            expectGone(sheet)
        }
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
}

/// Ways into the feedback sheets that FeedbackTests and FeedbackAccountTests share.
extension UITestCase {
    func openGetHelpSignedOut() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"])
        openSendFeedback()
        tap(app.buttons.labeled("Get Help"))
        expect(app.navigationBars["Get Help"])
    }

    func enterEmailAndSendCode() {
        tap(app.textFields["Email"])
        app.textFields["Email"].typeText("parent@example.com")
        tap(app.buttons["Send Code"])
        expect(app.staticTexts["Enter the 6-digit code we sent to parent@example.com."])
    }

    /// Email, Send Code, then a code that the field submits on its sixth digit.
    func signInWithCode() {
        enterEmailAndSendCode()
        tap(app.textFields["Code"])
        app.textFields["Code"].typeText("123456")
    }

    /// Send Feedback ▸ Feedback Account, from its row. The row waits on WebKit's cookie store,
    /// which took from 8 to over 40 seconds after launch in a full local run.
    func openFeedbackAccount() {
        tap(app.buttons.labeled("Feedback Account"), timeout: 60)
        expect(app.navigationBars["Feedback Account"])
    }
}
