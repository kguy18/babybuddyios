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

    /// Send Feedback: the note and its four links, the supporter link opening its sheet, each way
    /// into the feedback widget opening and closing, and Copy app details confirming. Whether the
    /// server answers doesn't matter: each sheet's own navigation bar is there either way, and
    /// nothing here reads what the server sends.
    func testSendFeedbackScreen() {
        launch(["BB_START_TAB": "settings"])
        openSendFeedback()

        expect(element(labeled: "Hi, I'm Kurtis."))
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
