import XCTest

/// Base for every UI test: a clean-install launch, iOS 26 only, and the few helpers tests share.
/// Query by what VoiceOver reads; wait for the screen you expect before every tap — XCTest's idle
/// wait does not cover SwiftUI transitions, and a sleep only hides the race.
///
/// `BB_UITEST=1` wipes the store, both defaults domains, the keychain and pending notifications
/// before anything reads them (`DemoData.resetForUITests`), so no test inherits another's records,
/// settings, support-nudge counters or sign-in. `BB_DEMO=1` then seeds the sample child and records
/// — relative to launch time, so assert before/after changes, never absolute times or "Today" totals.
@MainActor
class UITestCase: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        // The regressions these tests exist for — `confirmationDialog` losing its Cancel, overlays on
        // the tab bar ignoring taps — only reproduce on iOS 26; a skip would pass silently on 18.x.
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        XCTAssertGreaterThanOrEqual(major, 26, "UI tests need an iOS 26+ simulator; this one runs iOS \(major).")
        // A freshly erased simulator posts system banners over its first minute; XCTest's default
        // handler waits 15 s for each to expire. Swipe them away instead.
        addUIInterruptionMonitor(withDescription: "System banner") { element in
            guard element.identifier == "NotificationShortLookView" else { return false }
            element.swipeUp()
            return true
        }
    }

    /// A fresh install. `environment` adds any other `BB_*` hook (Docs/DEVELOPMENT.md); `demo: false`
    /// starts signed out, on onboarding.
    func launch(_ environment: [String: String] = [:], demo: Bool = true) {
        var env = ["BB_UITEST": "1"]
        if demo { env["BB_DEMO"] = "1" }
        app.launchEnvironment = env.merging(environment) { $1 }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"] // queries match English
        app.launch()
        // `launch()` returns while the generated launch screen — which has no text on it — is still
        // up, and the first launch of a run creates the store, wipes it and reseeds before the
        // first frame. Waiting here means a slow start reads as a slow start rather than as a
        // missing element.
        XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 60),
                      "The app never drew anything after launch")
        // iOS prewarms app processes, and a prewarmed one starts *without* the launch environment:
        // no `BB_DEMO`, so the app comes up signed out on onboarding, as if no hook had been
        // passed. It only ever hits the first launch of a run, and only on a simulator the app has
        // run on before, which is why an erased one never shows it. Replacing that instance costs
        // one relaunch.
        if demo, app.staticTexts["Connect to your self-hosted server"].waitForExistence(timeout: 3) {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 60),
                          "The app came up signed out even after a relaunch")
        }
    }

    /// Waits for the element (a navigation title, a row, a button) and fails with its query when it
    /// never comes. 10 s is generous on purpose: CI shares the Mac with other repos' runners.
    @discardableResult
    func expect(
        _ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        if !element.waitForExistence(timeout: timeout) {
            fail("Expected \(element)", file: file, line: line)
        }
        return element
    }

    func expectGone(
        _ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line
    ) {
        if !element.waitForNonExistence(timeout: timeout) {
            fail("Still on screen: \(element)", file: file, line: line)
        }
    }

    /// Waits for an element's value — a switch's "0"/"1", a field's text. A switch read straight
    /// after its own tap can still answer with the old value, especially on the first tap after the
    /// app comes back from the background.
    func expectValue(
        _ element: XCUIElement, _ value: String, timeout: TimeInterval = 5,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        expect(element, matching: NSPredicate(format: "value == %@", value), timeout: timeout,
               describedAs: "to read “\(value)”", file: file, line: line)
    }

    /// Taps a switch and waits for it to read `value`, tapping once more if the first tap changed
    /// nothing. XCUITest scrolls a switch below the fold into view and taps it straight away, and on
    /// a hosted runner that tap can land while the list is still moving. In the recording of a failed
    /// run the list has scrolled to the switch and the switch never flips. The second tap is
    /// only made when the value hasn't moved, so it can't undo a first one that worked; a first tap
    /// that landed later than five seconds would flip it back and fail below, not pass.
    func toggle(_ element: XCUIElement, to value: String, file: StaticString = #filePath, line: UInt = #line) {
        tap(element, file: file, line: line)
        let flipped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        if XCTWaiter().wait(for: [flipped], timeout: 5) != .completed { element.tap() }
        expectValue(element, value, file: file, line: line)
    }

    /// Waits for a predicate about an element — the general form behind ``expectValue``. Write it
    /// as a block (`NSPredicate { … }`) for anything but `value`: the format-string form reads
    /// attributes through KVC, and `"selected == true"` never became true even with the trait
    /// plainly in the tree.
    func expect(
        _ element: XCUIElement, matching predicate: NSPredicate, timeout: TimeInterval,
        describedAs expectation: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let outcome = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
        if outcome != .completed {
            fail("Expected \(element) \(expectation)", file: file, line: line)
        }
    }

    /// Fails with the app's element tree attached. XCTest attaches it by itself only when an
    /// interaction fails, and it's what a CI failure is diagnosed from.
    private func fail(_ message: String, file: StaticString, line: UInt) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Element tree"
        add(tree)
        XCTFail(message, file: file, line: line)
    }

    /// Waits for and taps.
    func tap(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        expect(element, timeout: timeout, file: file, line: line).tap()
    }

    /// Replaces a field's contents. Typing into a filled field inserts — or replaces a word —
    /// wherever the tap landed, which once turned "ci-E981C1CE" into "edited-E981C1CE".
    func replaceText(_ element: XCUIElement, with text: String) {
        tap(element)
        let current = element.value as? String ?? ""
        let existing = current == element.placeholderValue ? "" : current
        element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + text)
    }

    /// Home ▸ "+" ▸ More… ▸ `kind`. Not the quick-add rows: those log in one tap once #78 lands.
    func openEditor(_ kind: String) {
        tap(app.buttons["Add"])
        tap(app.buttons.labeled("More…"))
        expect(app.navigationBars["Add Activity"])
        tap(app.buttons[kind])
    }

    /// Any element whose label starts with `prefix` — rows and tiles carry live values in their
    /// labels ("Diapers, 2", "Feeding, Formula · Bottle · 20m, 9:14 AM").
    func element(labeled prefix: String) -> XCUIElement {
        app.descendants(matching: .any).labeled(prefix)
    }

    // MARK: Outside the app

    /// The system's own UI: notification banners, Notification Center, Live Activities and the
    /// permission prompts the app raises. None of them belong to the app's element tree.
    var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    /// Answers the notification permission prompt, when the app raises one: turning an alert on
    /// does, and so does sick mode with a fever, when its first temperature check is due.
    func allowNotificationsIfAsked() {
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    /// Sends the app to the background, the way someone leaving the app does.
    ///
    /// The press is repeated rather than simply waited on for longer. A home press issued while the
    /// system is still busy — moments after a launch, or with a Live Activity request in flight —
    /// is dropped rather than queued, and no amount of extra patience turns a press that never
    /// landed into a backgrounded app. Raising the single wait to 30 seconds on a hosted runner
    /// wasn't enough on its own, which is what pointed at the press rather than the waiting.
    func pressHome(file: StaticString = #filePath, line: UInt = #line) {
        for _ in 1...3 {
            XCUIDevice.shared.press(.home)
            if app.wait(for: .runningBackground, timeout: 10) { return }
        }
        XCTFail("The app stayed in the foreground", file: file, line: line)
    }

    /// Pulls Notification Center down over the Home Screen — where a banner that has already
    /// expired, and any Live Activity, can still be found. Dragging from the left of the notch:
    /// the right side is Control Center.
    func openNotificationCenter() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0))
            .press(forDuration: 0.1,
                   thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.7)))
    }

    /// Every element whose label matches a predicate, e.g. one kind's timeline rows:
    /// `elements("label BEGINSWITH 'Feeding, ' AND label CONTAINS 'waiting to sync'")`. A List only
    /// holds the rows on screen, so count rows near the top or narrow them with a search first.
    func elements(_ format: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: format))
    }
}

extension XCUIElementQuery {
    /// The first match whose label starts with `prefix`.
    func labeled(_ prefix: String) -> XCUIElement {
        matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// The first match whose *value* contains `text` — how to find a filled text field, which has no
    /// placeholder left to match on.
    func withValue(_ text: String) -> XCUIElement {
        matching(NSPredicate(format: "value CONTAINS %@", text)).firstMatch
    }
}
