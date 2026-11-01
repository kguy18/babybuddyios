import XCTest

/// Send Feedback ▸ Feedback Account: the account screen, signing out, deleting the account and
/// a sign-in that survives a relaunch. Apart from FeedbackTests so each CI shard stays short
/// enough for the iPhone Duo lane's 30 minutes.
final class FeedbackAccountTests: UITestCase {
    /// Send Feedback's Feedback Account row, signed in, pushes the account screen: who is signed
    /// in, Sign Out, the note, and Delete Feedback Account. Back returns to Send Feedback.
    func testFeedbackAccountScreen() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-in"])
        openSendFeedback()
        expect(app.buttons.labeled("Feedback Account"))
        XCTAssertFalse(app.buttons["Sign Out of Feedback"].exists, "Sign Out lives on the account screen")
        XCTAssertFalse(app.buttons["Delete Feedback Account"].exists)

        openFeedbackAccount()
        XCTAssertTrue(element(labeled: "Signed in to feedback as parent@example.com").exists)
        XCTAssertTrue(app.buttons["Sign Out of Feedback"].exists)
        XCTAssertTrue(app.buttons["Delete Feedback Account"].exists)
        XCTAssertTrue(app.staticTexts["Your Baby Buddy data isn't affected. This account is only for posting, voting and chatting with me."].exists)

        tap(app.navigationBars["Feedback Account"].buttons.firstMatch)
        expect(app.navigationBars["Send Feedback"])
    }

    /// Sign Out of Feedback asks first, goes back to Send Feedback without the account row, and
    /// the next sheet opens signed out.
    func testSignOutOfFeedback() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-in"])
        openSendFeedback()
        openFeedbackAccount()
        let signOut = app.buttons["Sign Out of Feedback"]

        // Cancel keeps the session.
        tap(signOut)
        let alert = expect(app.alerts["Sign out of feedback?"])
        XCTAssertTrue(alert.staticTexts["You'll need your email to post, vote or chat again. Your Baby Buddy data isn't affected."].exists)
        tap(alert.buttons["Cancel"])
        expectGone(alert)
        XCTAssertTrue(signOut.exists)

        tap(signOut)
        tap(app.alerts["Sign out of feedback?"].buttons["Sign Out"])
        expect(app.navigationBars["Send Feedback"])
        expectGone(app.navigationBars["Feedback Account"])
        expectGone(app.buttons.labeled("Feedback Account"))

        tap(app.buttons.labeled("Request a Feature"))
        let board = expect(app.navigationBars["Request a Feature"])
        expect(board.buttons["Sign In"])
        tap(board.buttons["Close"])
        expectGone(board)
        XCTAssertFalse(app.buttons.labeled("Feedback Account").exists)
    }

    /// Delete Feedback Account asks first, and Cancel sends nothing.
    func testDeleteFeedbackAccountCancel() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-in", "BB_FEEDBACK_DELETION_MAIL": "sent"])
        openSendFeedback()
        openFeedbackAccount()
        tap(app.buttons["Delete Feedback Account"])
        let alert = expect(app.alerts["Delete your feedback account?"])
        XCTAssertTrue(alert.staticTexts.element(matching: NSPredicate(
            format: "label BEGINSWITH %@", "I'll remove your feedback account within 7 days.")).exists)
        XCTAssertTrue(alert.buttons["Request Deletion"].exists)
        tap(alert.buttons["Cancel"])
        expectGone(alert)
        XCTAssertTrue(app.navigationBars["Feedback Account"].exists, "Still on the account screen")
        XCTAssertTrue(element(labeled: "Signed in to feedback as").exists)
    }

    /// A sent request goes back to Send Feedback and leaves the user signed in, so they can still
    /// read replies. The stub stands in for Mail's "sent".
    func testDeleteFeedbackAccountRequested() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-in", "BB_FEEDBACK_DELETION_MAIL": "sent"])
        openSendFeedback()
        openFeedbackAccount()
        tap(app.buttons["Delete Feedback Account"])
        tap(app.alerts["Delete your feedback account?"].buttons["Request Deletion"])
        expect(app.navigationBars["Send Feedback"])
        expectGone(app.navigationBars["Feedback Account"])
        XCTAssertTrue(app.buttons.labeled("Feedback Account").exists, "Still signed in")
    }

    /// The test simulator has no Mail account, so the request can't go out: the screen says where
    /// to write, and Try Again tries again.
    func testDeleteFeedbackAccountFailure() {
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-in"])
        openSendFeedback()
        openFeedbackAccount()
        tap(app.buttons["Delete Feedback Account"])
        tap(app.alerts["Delete your feedback account?"].buttons["Request Deletion"])
        let failure = expect(app.staticTexts["Couldn't send your request. Try again, or email hello@babybuddy.app."])
        tap(app.buttons["Try Again"])
        XCTAssertTrue(failure.exists)
        XCTAssertFalse(element(labeled: "Deletion requested").exists)
    }

    /// The session outlives a relaunch: straight after it, Send Feedback shows the Feedback
    /// Account row and the board opens signed in. The app goes to the Home Screen before it's
    /// killed, as it does when someone quits it, since WebKit writes its cookies to disk only now
    /// and then.
    func testSignInSurvivesARelaunch() throws {
        try skipIfAppCantBeLeft()
        launch(["BB_START_TAB": "settings", "BB_FEEDBACK_STUB": "signed-out"])
        openSendFeedback()
        XCTAssertFalse(app.buttons.labeled("Feedback Account").exists)
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
        expect(app.buttons.labeled("Feedback Account"))
        tap(app.buttons.labeled("Request a Feature"))
        expect(app.webViews.staticTexts["Stub widget: new-post"], timeout: 30)
        XCTAssertFalse(board.buttons["Sign In"].exists, "Still signed in")
    }
}
