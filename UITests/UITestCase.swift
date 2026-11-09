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
    /// starts signed out, on onboarding; `largestText` runs at the largest accessibility text size.
    ///
    /// The feedback sheet points at a port nothing listens on unless a test says otherwise, so no
    /// UI test reaches the live feedback server; `BB_FEEDBACK_STUB` stands in for it.
    ///
    /// `OS_ACTIVITY_DT_MODE` is off because xcodebuild turns it on, which copies every log line to
    /// stderr. XCTest evaluates queries on the app's main thread and logs each element it reads, so
    /// on a small CI runner that write blocks the main thread: in a spindump of a test that hit the
    /// time allowance, 81% of the main thread's samples were in it.
    func launch(_ environment: [String: String] = [:], demo: Bool = true,
                language: String? = "en", locale: String = "en_US", largestText: Bool = false) {
        var env = ["BB_UITEST": "1", "BB_FEEDBACK": "https://127.0.0.1:2", "OS_ACTIVITY_DT_MODE": "NO"]
        if demo { env["BB_DEMO"] = "1" }
        app.launchEnvironment = env.merging(environment) { $1 }
        // `nil` keeps the language the screenshot helper already put in the launch arguments.
        if let language { app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale] }
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
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
        guard let language else { return }
        let onboardingTitle = language.hasPrefix("de") ? "Mit deinem eigenen Server verbinden"
            : language.hasPrefix("pt") ? "Conecte ao seu servidor próprio" : "Connect to your self-hosted server"
        if demo, app.staticTexts[onboardingTitle].waitForExistence(timeout: 3) {
            app.terminate()
            app.launch()
            XCTAssertTrue(tab("Home").waitForExistence(timeout: 60),
                          "The app came up signed out even after a relaunch")
        }
    }

    // MARK: iPhone Duo's rail

    /// Whether the tabs and the main screen's bar buttons sit in iPhone Duo's trailing rail rather
    /// than a tab bar and navigation bars. Its displays are wide for their height (466 × 678 pt in
    /// front, 951 × 669 pt open); every other iPhone is less than half as wide as it is tall.
    /// Sheets keep a navigation bar for Cancel, Close and Save. Read from SpringBoard, so it
    /// answers before the app has launched.
    var hasRail: Bool {
        let frame = springboard.frame
        return frame.width > frame.height * 0.6
    }

    /// Skips a test that leaves the app, on iPhone Duo. Its simulator ignores the Home button and
    /// reports the app in the foreground whatever is on screen (Xcode 27.1 and 27.2), so neither
    /// leaving nor coming back can be done or checked there.
    func skipIfAppCantBeLeft() throws {
        try XCTSkipIf(hasRail, "iPhone Duo's simulator ignores the Home button")
    }

    /// Brings back the navigation bar of the sheet titled `title` when it has scrolled away. On
    /// iPhone Duo (iOS 27.1) a sheet's bar scrolls off with the field the keyboard scrolled to, and
    /// comes back once the sheet is scrolled to the top: a slow drag down, held before release so
    /// it can't fling the sheet closed.
    func revealSheetBar(_ title: String) {
        let bar = expect(app.navigationBars[title])
        guard hasRail, !bar.buttons.firstMatch.waitForExistence(timeout: 2) else { return }
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.6)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// A button in the toolbar of the sheet titled `title`. On iPhone Duo a sheet keeps Cancel,
    /// Close and Save in its navigation bar but puts its other actions in a rail of its own.
    func sheetButton(_ name: String, in title: String) -> XCUIElement {
        hasRail ? app.toolbars.buttons[name] : app.navigationBars[title].buttons[name]
    }

    /// A tab's button: in the tab bar, or in iPhone Duo's rail.
    func tab(_ name: String) -> XCUIElement {
        (hasRail ? app.toolbars : app.tabBars).buttons[name]
    }

    /// Goes back from the pushed screen titled `title`: the first button in its navigation bar, or
    /// on iPhone Duo the rail's back button, which has no label.
    func back(from title: String, file: StaticString = #filePath, line: UInt = #line) {
        let bar = expect(app.navigationBars[title], file: file, line: line)
        tap(hasRail ? app.toolbars.buttons["BackButton"] : bar.buttons.firstMatch, file: file, line: line)
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

    /// Sets the editor's Start time (its first date picker) to `date`'s hour and minute. Only the
    /// time wheels move, so `date` must fall on the picker's current day.
    func setStartTime(_ date: Date) {
        // Start is the first picker; its buttons are the pair, the date, then the time.
        tap(app.datePickers.element(boundBy: 0).buttons.element(boundBy: 2))
        let wheels = app.pickerWheels
        expect(wheels.element(boundBy: 1))
        let format = DateFormatter()
        let patterns: [String] = wheels.count == 3 ? ["h", "mm", "a"] : ["HH", "mm"]
        for (index, pattern) in patterns.enumerated() {
            format.dateFormat = pattern
            wheels.element(boundBy: index).adjust(toPickerWheelValue: format.string(from: date))
        }
        tap(app.buttons["PopoverDismissRegion"])
    }

    /// Home ▸ "+" ▸ More… ▸ `kind`. Not the quick-add rows: those log in one tap once #78 lands.
    func openEditor(_ kind: String) {
        tap(app.buttons["Add"])
        tap(app.buttons.labeled("More…"))
        expect(app.navigationBars["Add Activity"])
        // On iPhone Duo's short front display the sheet opens at half height, and the grid hasn't
        // drawn the tiles below it yet. A swipe up on the grid draws them.
        if !app.buttons[kind].waitForExistence(timeout: 2) { app.buttons["Feeding"].swipeUp() }
        tap(app.buttons[kind])
    }

    /// Fails unless Home's scrolling content stops above the floating "+", which used to cover a
    /// row's time and a running timer's Stop button. The pane is the tallest scroll view the "+"
    /// sits under: on iPhone Duo's open display the timeline left of the fold is another.
    func expectContentClearsAddButton(file: StaticString = #filePath, line: UInt = #line) {
        let add = expect(app.buttons["Add"], file: file, line: line)
        let pane = app.scrollViews.allElementsBoundByIndex
            .filter { $0.frame.minX <= add.frame.midX && add.frame.midX <= $0.frame.maxX }
            .max { $0.frame.height < $1.frame.height }
        guard let pane else { return XCTFail("No scroll view above the + button", file: file, line: line) }
        XCTAssertLessThanOrEqual(pane.frame.maxY, add.frame.minY + 1,
                                 "Home's content should stop above the + button", file: file, line: line)
    }

    /// Drags the open sheet's grabber to the top, for a sheet that opens at half height. A swipe on
    /// its content scrolls the content instead.
    func expandSheet() {
        let grabber = expect(app.buttons["Sheet Grabber"])
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        expectValue(grabber, "Expanded")
    }

    /// Settings ▸ Feedback ▸ Send Feedback.
    func openSendFeedback() {
        tap(app.buttons.labeled("Send Feedback"))
        expect(app.navigationBars["Send Feedback"])
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
    ///
    /// Not on iPhone Duo: see ``skipIfAppCantBeLeft()``.
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
