import XCTest
@testable import BabyBuddy

/// The feedback widget's sign-in stays in the sheet and comes back to the widget afterwards.
final class FeedbackWidgetTests: XCTestCase {
    private let server = "https://feedback.babybuddy.app"

    private func url(_ path: String) -> URL { URL(string: server + path)! }

    private func inSheet(_ path: String) -> String {
        FeedbackWidget.inSheetURL(for: url(path)).absoluteString
    }

    func testSignInGetsACallbackToTheWidget() {
        XCTAssertEqual(inSheet("/auth/login"), server + "/auth/login?callbackUrl=/widget")
        XCTAssertEqual(inSheet("/?auth=signin"), server + "/?auth=signin&callbackUrl=/widget")
    }

    func testOtherPagesAndExistingCallbacksAreLeftAlone() {
        for path in ["/auth/login?callbackUrl=/b/features", "/b/features/posts/1", "/"] {
            XCTAssertEqual(inSheet(path), server + path)
        }
    }

    /// Wherever the portal lands, after a sign-in or not, the sheet reloads the
    /// widget. A bare `/widget` counts too: it lacks the app's `source=native`.
    func testAnyPortalLandingFinishesSignIn() {
        for path in ["/", "/?board=feature-requests", "/b/feature-requests", "/roadmap",
                     "/widget", "/widget?board=feature-requests", "/settings/profile"] {
            XCTAssertTrue(FeedbackWidget.isPortalPage(url(path)), path)
        }
    }

    func testSignInPagesAndTheAppsOwnWidgetDoNot() {
        for path in ["/auth/login", "/auth/login?callbackUrl=/widget", "/auth/auth-complete",
                     "/?auth=signin&callbackUrl=%2Fwidget", "/?auth=signup",
                     "/widget?source=native&platform=ios"] {
            XCTAssertFalse(FeedbackWidget.isPortalPage(url(path)), path)
        }
        XCTAssertFalse(FeedbackWidget.isPortalPage(URL(string: "https://github.com/")!),
                       "Another site is not the portal")
    }
}
