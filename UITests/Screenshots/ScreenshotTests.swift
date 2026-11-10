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
    }

    private let shots = [
        Shot(name: "01_home", waitFor: "screen-home"),
        Shot(name: "02_sick", environment: ["BB_SEED_SICK": "1"], waitFor: "screen-home"),
        Shot(name: "03_timer", environment: ["BB_OPEN": "timer"], waitFor: "screen-start-timer"),
        Shot(name: "04_log", environment: ["BB_OPEN": "feeding"], waitFor: "screen-editor"),
        Shot(name: "05_timeline", environment: ["BB_START_TAB": "timeline"], waitFor: "screen-timeline"),
        Shot(name: "06_trends", environment: ["BB_START_TAB": "trends"], waitFor: "screen-trends"),
        Shot(name: "07_server", environment: ["BB_START_TAB": "settings"], waitFor: "screen-settings"),
        // Estimates are off by default; this hook turns them on and seeds a regular routine. The
        // other two open What's next and scroll Today to the top, so the tiles and every row show.
        Shot(name: "08_estimates", environment: [
            "BB_SEED_FORECAST": "1", "BB_FORECAST_OPEN": "1", "BB_HOME_SCROLL": "today",
        ], waitFor: "today-feeding"),
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
        screenshot(shot.name + suffix)
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
