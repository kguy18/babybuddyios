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
}
