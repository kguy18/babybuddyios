import XCTest
@testable import BabyBuddy

/// When Home splits at iPhone Duo's fold, and where the panes go (#215).
final class FoldLayoutTests: XCTestCase {
    /// The open display's reported fold, 40 pt at x 455 to 495 of a 951 pt wide window.
    private let duoFold = CGRect(x: 455, y: 0, width: 40, height: 669)

    func testOpenDisplaySplitsEitherSideOfTheReportedFold() {
        XCTAssertEqual(FoldLayout.panes(width: 951, fold: duoFold),
                       FoldLayout.Panes(side: 455, fold: 40, main: 456))
    }

    func testPhoneWidthsStayOnePane() {
        for width: CGFloat in [320, 393, 440, 466] {
            XCTAssertNil(FoldLayout.panes(width: width, fold: nil), "\(width) pt split")
        }
    }

    func testWithoutAReportedFoldItIsAssumedCentred() {
        XCTAssertEqual(FoldLayout.panes(width: 951, fold: nil),
                       FoldLayout.Panes(side: 455.5, fold: 40, main: 455.5))
    }

    func testAPaneTooNarrowForAPhoneLayoutDoesNotSplit() {
        // A fold well off centre leaves the right pane 300 pt wide.
        XCTAssertNil(FoldLayout.panes(width: 951, fold: CGRect(x: 611, y: 0, width: 40, height: 669)))
        // A wide enough window, but only just short of two phone layouts.
        XCTAssertNil(FoldLayout.panes(width: 2 * FoldLayout.minPane + FoldLayout.assumedFold - 1, fold: nil))
    }

    func testAFoldReachingPastTheWindowIsClipped() {
        XCTAssertEqual(FoldLayout.panes(width: 800, fold: CGRect(x: 380, y: -20, width: 40, height: 900)),
                       FoldLayout.Panes(side: 380, fold: 40, main: 380))
    }
}
