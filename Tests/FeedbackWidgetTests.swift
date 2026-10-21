import XCTest
@testable import BabyBuddy

/// The feedback widget's sign-in stays in the sheet and comes back to the widget afterwards.
final class FeedbackWidgetTests: XCTestCase {
    private func inSheet(_ string: String) -> String {
        FeedbackWidget.inSheetURL(for: URL(string: string)!).absoluteString
    }

    func testSignInGetsACallbackToTheWidget() {
        XCTAssertEqual(inSheet("https://feedback.babybuddy.app/auth/login"),
                       "https://feedback.babybuddy.app/auth/login?callbackUrl=/widget")
        XCTAssertEqual(inSheet("https://feedback.babybuddy.app/?auth=signin"),
                       "https://feedback.babybuddy.app/?auth=signin&callbackUrl=/widget")
    }

    func testOtherPagesAndExistingCallbacksAreLeftAlone() {
        for url in ["https://feedback.babybuddy.app/auth/login?callbackUrl=/b/features",
                    "https://feedback.babybuddy.app/b/features/posts/1",
                    "https://feedback.babybuddy.app/"] {
            XCTAssertEqual(inSheet(url), url)
        }
    }
}
