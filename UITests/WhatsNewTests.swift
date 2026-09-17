import XCTest

/// The once-per-version release-notes sheet, and the three ways out of it.
///
/// Everything asserted here is structure, never copy: `Docs/whats-new.md` is meant to be rewritten
/// between releases, so the rows are counted by identifier and the chip matched by its prefix. A
/// test that had to be edited alongside the copy would just be edited to pass.
///
/// `BB_WHATS_NEW=1` is what puts the sheet on screen at all — every launch here is a clean install,
/// and a fresh install deliberately never sees it (``WhatsNewStore``).
final class WhatsNewTests: UITestCase {
    private var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "whatsNewRow")
    }

    /// The screen itself: a heading, the version chip, and a row per change.
    func testShowsTheReleaseNotes() {
        launch(["BB_WHATS_NEW": "1"])

        expect(app.buttons["Continue"])
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(rows.count, 3, "Expected at least three changes on the sheet")
        XCTAssertLessThanOrEqual(rows.count, 5, "More than five rows and it stops being a sheet")

        // The chip, matched on its shape rather than the version it happens to carry.
        let chip = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Version '")).firstMatch
        XCTAssertTrue(chip.exists, "The version chip should name the release")
    }

    /// The primary way out. The Dashboard has to be usable the moment it closes — a sheet that
    /// lingers over the tab bar is the failure this guards.
    func testContinueDismissesIt() {
        launch(["BB_WHATS_NEW": "1"])
        let continueButton = expect(app.buttons["Continue"])

        continueButton.tap()

        expectGone(continueButton)
        expectGone(rows.element(boundBy: 0))
        // Back on the Dashboard, with its own controls reachable.
        expect(app.buttons["Add"])
    }

    /// Swiping the sheet down is a first-class outcome, not a no-op: the presenter reports it as
    /// `swiped`, which is the whole reason the telemetry distinguishes it from Continue.
    func testSwipingItDownDismissesIt() {
        launch(["BB_WHATS_NEW": "1"])
        let continueButton = expect(app.buttons["Continue"])

        // Dragged from a row rather than a button, so the gesture can't land as a tap instead.
        let row = expect(rows.element(boundBy: 0))
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 700)))

        expectGone(continueButton)
        expect(app.buttons["Add"])
    }

    /// "Support development" lands on the supporter screen — the one with the tip amounts and a way
    /// back — and never starts a purchase by itself. Under `BB_UITEST` the purchase SDK is
    /// deliberately never configured, so the sheet shows its unavailable notice in place of the
    /// amounts; what matters, and what is asserted, is that this is the supporter sheet and not a
    /// StoreKit payment sheet.
    func testSupportOpensTheSupporterScreenWithoutStartingAPurchase() {
        launch(["BB_WHATS_NEW": "1"])
        expect(app.buttons["Continue"])

        tap(app.buttons.labeled("Support development"))

        // The What's New sheet gives way rather than stacking underneath.
        expectGone(app.buttons["Continue"])
        // The supporter sheet's own furniture: the ask, the quiet way out, and Restore.
        expect(app.staticTexts["Support Baby Buddy Companion"])
        XCTAssertTrue(app.buttons.labeled("Maybe later").exists)
        XCTAssertTrue(app.buttons.labeled("Restore Purchases").exists)
        // Nothing has been bought and nothing is asking to be: no system payment sheet.
        XCTAssertFalse(app.staticTexts["Confirm Your In-App Purchase"].exists)

        // And it is dismissible, back to a usable Dashboard.
        tap(app.buttons.labeled("Maybe later"))
        expect(app.buttons["Add"])
    }
}
