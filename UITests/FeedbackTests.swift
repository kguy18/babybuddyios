import XCTest

/// Settings ▸ Send Feedback and signing in to the feedback site. A class apart from SettingsTests
/// so each CI shard stays short enough for the iPhone Duo lane's 30 minutes.
///
/// The stub (`BB_FEEDBACK_STUB`) stands in for Quackback: any email gets a code except one
/// starting `busy@`, which hits the rate limit; the code `000000` and the password `wrong` are
/// refused; anything else signs in. Its widget is signed in when the app holds the session the
/// sign-in wrote, so these tests cover the hand-off too. The stub keeps that session in memory;
/// `FeedbackAccountTests.testSignInSurvivesARelaunchThroughWebKitsCookieStore` is the one test on
/// WebKit's cookie store.
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

    func testGetHelpSendCodeStaysAboveTheKeyboardAtLargestText() {
        openGetHelpSignedOut(largestText: true)
        let email = expect(app.textFields["Email"], timeout: widgetTimeout)
        tap(email)
        email.typeText("parent@example.com")
        let keyboard = expect(app.keyboards.firstMatch)
        let sendCode = expect(app.buttons["Send Code"])
        expect(sendCode, matching: NSPredicate { _, _ in
            sendCode.isHittable && sendCode.frame.maxY <= keyboard.frame.minY + 1
        }, timeout: 10, describedAs: "to be visible above the keyboard")
        attachScreen("feedback-get-help")
        tap(sendCode)
        expect(app.staticTexts["Check your email"])
    }

    func testOfflineGetHelpWrapsAndOffersEmailAtLargestText() {
        launch(["BB_START_TAB": "settings"], largestText: true)
        openSendFeedback()
        tap(app.buttons.labeled("Get Help"))
        let title = expect(app.staticTexts["Can't reach the feedback server"], timeout: 30)
        let details = expect(app.staticTexts["Check your connection, or email us and we'll reply there."])
        let email = expect(app.buttons["Email Support"])
        let scroll = expect(app.scrollViews.containing(.button, identifier: "Email Support").firstMatch)
        XCTAssertGreaterThan(title.frame.height, 70, "The title should wrap")
        XCTAssertGreaterThan(details.frame.height, 70, "The instructions should wrap")
        attachScreen("feedback-get-help-offline")
        reveal(email, in: scroll)
        tap(email)
        expectGone(app.navigationBars["Get Help"])
        let alert = expect(app.alerts["Contact Support"])
        let cancel = alert.buttons["Cancel"]
        // At the largest text, iOS scrolls the alert's buttons. Tapping Cancel offscreen
        // makes XCTest treat the alert as an interruption and try the same tap again.
        if !cancel.isHittable {
            let actions = expect(alert.scrollViews.containing(.button, identifier: "Cancel").firstMatch)
            reveal(cancel, in: actions)
        }
        tap(cancel)
        expectGone(alert)
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

    /// Typing in the chat leaves the page at its size. WebKit zoomed in on the composer's small
    /// text when it took focus, and the zoomed page ran past the sheet's edge, Send included.
    func testGetHelpDoesNotZoomWhenTyping() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-in"])
        openSendFeedback()
        tap(app.buttons.labeled("Get Help"))
        let label = expect(app.webViews.staticTexts["Stub widget: chat"], timeout: 30)
        let before = label.frame
        tap(app.webViews.textViews["Message"])
        app.typeText("The layout needs fixing")
        expect(app.keyboards.firstMatch)
        // WebKit animates the zoom; give it time to land before measuring.
        _ = app.webViews.staticTexts["never"].waitForExistence(timeout: 2)
        XCTAssertEqual(label.frame.width, before.width, accuracy: 1, "The page zoomed in on the message box")
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
        // The stub page can take a while to render on CI's iPhone Duo: once it failed twice in a row
        // with the sheet's spinner still up after the default 10 s.
        expect(app.webViews.staticTexts["Stub widget: new-post"], timeout: 30)
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


    func testFeedbackActionsPrecedeTheNoteAtLargestText() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"], largestText: true)
        openSendFeedback()
        let request = expect(app.buttons.labeled("Request a Feature"))
        let note = element(labeled: "Hi, I'm Kurtis.")
        let requestFrame = request.frame
        let noteFrame = note.frame
        let requestIsVisible = request.isHittable && app.windows.firstMatch.frame.contains(requestFrame)
        captureFeedbackInventory()
        XCTAssertTrue(requestIsVisible, "Request a Feature should be visible before scrolling")
        XCTAssertLessThan(requestFrame.maxY, noteFrame.minY, "Feedback actions should precede the long note")

        tap(app.buttons.labeled("Get Help"))
        let help = expect(app.navigationBars["Get Help"])
        expect(app.buttons["Send Code"])
        revealSheetBar("Get Help")
        tap(help.buttons["Close"])
        expectGone(help)
        tap(app.buttons.labeled("Roadmap and Updates"))
        let roadmap = expect(app.navigationBars["Roadmap and Updates"])
        expect(app.webViews.staticTexts["Stub widget: home"], timeout: 30)
        revealSheetBar("Roadmap and Updates")
        tap(roadmap.buttons["Close"])
        expectGone(roadmap)
    }

    func testCustomHeadersCanAddAndRemoveAtLargestText() {
        launch(["BB_START_TAB": "settings"], largestText: true)
        tap(app.buttons.labeled("Custom headers"))
        expect(app.navigationBars["Custom headers"])
        attachScreen("settings-custom-headers")
        let add = expect(app.buttons["Add header"])
        XCTAssertTrue(add.isHittable)
        tap(add)
        expect(app.textFields["Header name"])
        let value = expect(app.secureTextFields["Header value"])
        let paste = expect(app.buttons.labeled("Paste"))
        XCTAssertGreaterThanOrEqual(paste.frame.minY, value.frame.maxY, "Paste should leave the value the full line")
        XCTAssertGreaterThan(paste.frame.height, 32, "Paste should grow with the text")
        attachScreen("settings-custom-headers-add")
        tap(app.buttons["Remove header"])
        expectGone(app.textFields["Header name"])
        XCTAssertTrue(add.isHittable, "The empty state should return after removal")
    }

    /// With the feedback server unreachable, Request a Feature offers email, and that leads to the
    /// mail flow (`DialogTests.testContactSupportAlertHasCancel` covers it from Get Help).
    func testFeatureRequestFallsBackToMail() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK": DialogTests.unreachableServer])
        openSendFeedback()
        tap(app.buttons.labeled("Request a Feature"))
        let sheet = expect(app.navigationBars["Request a Feature"])
        // The sheet gives up on the server after FeedbackWebView.readyTimeout, 8 seconds, when
        // WebKit hasn't reported the failed load sooner, as on a cold iPhone Duo simulator.
        expect(app.staticTexts["Can't reach the feedback server"], timeout: 30)
        tap(app.buttons["Email Support"])
        expectGone(sheet)
        tap(app.alerts["Contact Support"].buttons["Don't Include"])
        tap(app.alerts["Set Up Mail"].buttons["OK"])
    }
}

/// Ways into the feedback sheets that FeedbackTests and FeedbackAccountTests share.
extension UITestCase {
    func captureFeedbackInventory() {
        attachScreen("settings-send-feedback")
        // Scroll the note pane on the open display and the single column on a folded phone.
        let scroll = app.scrollViews.containing(.staticText, identifier: "I do read everything and try to reply to everyone.").firstMatch
        expect(scroll).swipeUp()
        attachScreen("settings-send-feedback-scrolled")
        scroll.swipeDown()
    }

    func openGetHelpSignedOut(largestText: Bool = false) {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"], largestText: largestText)
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

    /// How long the Feedback Account row can take to show when the stub keeps its session in
    /// WebKit's cookie store (`BB_FEEDBACK_COOKIE_STORE=1`): the store's first read after launch
    /// took from 8 to over 40 seconds in a full local run, and over a minute on a cold iPhone Duo
    /// simulator in CI. Every other stubbed launch keeps the session in memory, and the row shows
    /// at once.
    var cookieStoreTimeout: TimeInterval { 120 }

    /// How long a feedback sheet's first page can take to show under the stub. Nothing waits on a
    /// server, but WebKit starts its first page of the launch then, which took 5 seconds on a cold
    /// iPhone Duo simulator locally and over 8 in CI.
    var widgetTimeout: TimeInterval { 30 }

    /// Send Feedback ▸ Feedback Account, from its row.
    func openFeedbackAccount() {
        tap(app.buttons.labeled("Feedback Account"))
        expect(app.navigationBars["Feedback Account"])
    }
}
