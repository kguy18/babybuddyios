import XCTest

/// The App Store screenshots, run by ascelerate through the `BabyBuddyScreenshots` scheme (see the
/// store-screenshots skill). Every screen is its own fresh launch, set up with `BB_*` hooks, so
/// nothing here depends on the language on screen. Names are each screen's `source` in the skill's
/// config; `_outer` marks a capture on iPhone Duo's folded display.
final class ScreenshotTests: UITestCase {
    private struct Shot {
        let name: String
        var environment: [String: String] = [:]
        let waitFor: String
        var opensWhatsNext = false
    }

    private let shots = [
        Shot(name: "01_home", waitFor: "screen-home"),
        Shot(name: "02_sick", environment: ["BB_SEED_SICK": "1"], waitFor: "screen-home"),
        Shot(name: "03_timer", environment: ["BB_OPEN": "timer"], waitFor: "screen-start-timer"),
        Shot(name: "04_log", environment: ["BB_OPEN": "feeding"], waitFor: "screen-editor"),
        Shot(name: "05_timeline", environment: ["BB_START_TAB": "timeline"], waitFor: "screen-timeline"),
        Shot(name: "06_trends", environment: ["BB_START_TAB": "trends"], waitFor: "screen-trends"),
        Shot(name: "07_server", environment: ["BB_START_TAB": "settings"], waitFor: "screen-settings"),
        // Turns estimates on with a regular routine, then opens What's next below Today.
        Shot(name: "09_whats_next", environment: ["BB_SEED_FORECAST": "1"], waitFor: "whats-next-toggle",
             opensWhatsNext: true),
    ]

    /// How many screens also go on iPhone Duo's folded display.
    private let outerCount = 3

    override func setUp() {
        super.setUp()
        setupScreenshots(app)
        // The simulator takes a 24-hour clock from this Mac. NO leaves it to the locale.
        app.launchArguments += ["-AppleICUForce24HourTime", "NO"]
    }

    func testCaptureScreens() {
        // A prewarmed first launch comes up without the launch environment (`UITestCase.launch`).
        app.launch()
        app.terminate()

        let environment = ProcessInfo.processInfo.environment
        if environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4" {
            // Folded first: every boot starts closed. The skill's manual path opens the simulator
            // by hand and sets this to capture only the open display.
            if environment["STORE_SCREENSHOTS_UNFOLDED_ONLY"] != "1" {
                for shot in shots.prefix(outerCount) { capture(shot, suffix: "_outer") }
                setHinge(.open)
            }
            app.terminate()
        }
        for shot in shots { capture(shot) }
    }

    private func capture(_ shot: Shot, suffix: String = "") {
        app.terminate()
        launch(shot.environment.merging(pinnedClock()) { $1 }, language: nil)
        expect(app.descendants(matching: .any)[shot.waitFor].firstMatch, timeout: 30)
        dismissPermissionPrompt()
        if shot.opensWhatsNext { openWhatsNext() }
        screenshot(shot.name + suffix)
    }

    /// Opens What's next, then drags Home up until the open section clears the tab bar by 24
    /// points. A slow drag with a hold stops where it lets go, without a fling.
    private func openWhatsNext() {
        tap(app.buttons["whats-next-toggle"])
        expect(app.descendants(matching: .any)["forecast-change"]) // its last row
        let card = app.descendants(matching: .any)["whats-next"]
        let overlap = card.frame.maxY - (tab("Home").frame.minY - 24)
        guard overlap > 0 else { return }
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -overlap)),
                    withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    /// Sick mode can raise the notification prompt. Taps its second button, whatever its language.
    private func dismissPermissionPrompt() {
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) { alert.buttons.element(boundBy: 1).tap() }
    }

    /// The seed is relative to launch, so moving the app's time zone until now reads 09:41, the
    /// status bar's time, makes every clock time and "Today" total the same on every run.
    private func pinnedClock() -> [String: String] {
        let day = 1440
        let gmtNow = Int(Date().timeIntervalSince1970) / 60 % day
        var offset = (9 * 60 + 41 - gmtNow + day) % day
        if offset > day / 2 { offset -= day }
        let zone = String(format: "GMT%@%02d:%02d", offset < 0 ? "-" : "+", abs(offset) / 60, abs(offset) % 60)
        return ["TZ": zone, "BB_DEMO_DATE": "2026-03-17"]
    }
}
