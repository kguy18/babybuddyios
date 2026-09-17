import XCTest
import UIKit
@testable import BabyBuddy

/// The copy the app actually ships, parsed as shipped.
///
/// `Docs/whats-new.md` is a build resource rather than Swift, which buys the person writing it a
/// file they can edit without touching code — and costs the compiler's opinion on whether it is
/// well-formed. This is what buys that back: a malformed row, an unknown tint, or an SF Symbol
/// typo fails CI here instead of reaching a customer as a screen that never appears.
final class WhatsNewParsingTests: XCTestCase {
    /// The file as built into the test bundle — the same bytes the app target gets.
    private func shippedMarkdown() throws -> String {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: WhatsNewRelease.resourceName, withExtension: "md"),
            "Docs/whats-new.md is not in the test bundle — check its `buildPhase: resources` entry in project.yml")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testShippedCopyParses() throws {
        let release = try XCTUnwrap(WhatsNewRelease.parse(shippedMarkdown()),
                                    "The shipped What's New copy is malformed, so no screen would be shown")
        XCTAssertFalse(release.version.isEmpty)
        XCTAssertFalse(release.title.isEmpty)
    }

    /// Three to five rows is the design's own constraint: the sheet is sized to its content, and
    /// past five it stops being a sheet. Held here because nothing else would notice.
    func testShippedCopyHasThreeToFiveEntries() throws {
        let release = try XCTUnwrap(WhatsNewRelease.parse(shippedMarkdown()))
        XCTAssertTrue((3...5).contains(release.entries.count),
                      "Expected 3–5 rows, found \(release.entries.count)")
    }

    /// Every row is complete, and its glyph exists. An unknown SF Symbol renders as nothing at all
    /// — a silent blank square in the finished screen — so a typo has to fail here.
    func testShippedEntriesAreCompleteAndGlyphsResolve() throws {
        let release = try XCTUnwrap(WhatsNewRelease.parse(shippedMarkdown()))
        for entry in release.entries {
            XCTAssertFalse(entry.title.isEmpty)
            XCTAssertFalse(entry.blurb.isEmpty, "\(entry.title) has no blurb")
            XCTAssertNotNil(UIImage(systemName: entry.symbol),
                            "\(entry.title): \"\(entry.symbol)\" is not an SF Symbol")
        }
    }

    // MARK: Format

    private let wellFormed = """
    ---
    version: 9.9.9
    title: What's New
    ---

    # Notes for whoever edits this

    Prose up here is ignored, including a line with a colon: like this one, and a list:

    - Icon: not a field, because it is inside prose above the first heading.

    ## First change

    Icon: pills.fill
    Tint: danger

    A sentence that wraps
    across two lines.

    ## Second change

    Icon: timer
    Tint: tummy

    Another sentence.
    """

    func testParsesFrontMatterHeadingsAndFields() throws {
        let release = try XCTUnwrap(WhatsNewRelease.parse(wellFormed))
        XCTAssertEqual(release.version, "9.9.9")
        XCTAssertEqual(release.title, "What's New")
        XCTAssertEqual(release.entries.map(\.title), ["First change", "Second change"])
        XCTAssertEqual(release.entries.first?.symbol, "pills.fill")
        XCTAssertEqual(release.entries.first?.tint, .danger)
        XCTAssertEqual(release.entries.last?.tint, .tummy)
    }

    /// Wrapped prose is one sentence to the reader, so it has to be one string — otherwise a line
    /// break in the source becomes a line break with no space in the screen.
    func testWrappedBlurbIsJoinedWithASpace() throws {
        let release = try XCTUnwrap(WhatsNewRelease.parse(wellFormed))
        XCTAssertEqual(release.entries.first?.blurb, "A sentence that wraps across two lines.")
    }

    /// The whole point of the preamble: a human writes freely above the first `##` and none of it
    /// can become a row or a field.
    func testProseAboveTheFirstHeadingIsIgnored() throws {
        let release = try XCTUnwrap(WhatsNewRelease.parse(wellFormed))
        XCTAssertEqual(release.entries.count, 2)
        XCTAssertFalse(release.entries.contains { $0.title.contains("Notes for") })
    }

    // MARK: Fail-closed

    /// Each of these must produce *no* screen rather than a partial one. Half a What's New screen
    /// — a row with no blurb, a glyph with no tint — is worse than none, and unlike none it is
    /// invisible until a customer sees it.
    func testMalformedCopyProducesNoRelease() {
        let cases: [(String, String)] = [
            ("no front matter", "## A change\nIcon: timer\nTint: brand\n\nText."),
            ("no version", "---\ntitle: What's New\n---\n\n## A\nIcon: timer\nTint: brand\n\nText."),
            ("no title", "---\nversion: 1.1.0\n---\n\n## A\nIcon: timer\nTint: brand\n\nText."),
            ("unterminated front matter", "---\nversion: 1.1.0\ntitle: T\n\n## A\nIcon: timer\nTint: brand\n\nText."),
            ("no entries", "---\nversion: 1.1.0\ntitle: T\n---\n\nJust prose, no headings."),
            ("entry with no icon", "---\nversion: 1.1.0\ntitle: T\n---\n\n## A\nTint: brand\n\nText."),
            ("entry with no tint", "---\nversion: 1.1.0\ntitle: T\n---\n\n## A\nIcon: timer\n\nText."),
            ("entry with no blurb", "---\nversion: 1.1.0\ntitle: T\n---\n\n## A\nIcon: timer\nTint: brand\n"),
            ("unknown tint", "---\nversion: 1.1.0\ntitle: T\n---\n\n## A\nIcon: timer\nTint: chartreuse\n\nText."),
        ]
        for (name, markdown) in cases {
            XCTAssertNil(WhatsNewRelease.parse(markdown), "\(name) should have produced no release")
        }
    }

    /// One bad row takes the whole screen with it — a release is all-or-nothing, so a customer
    /// never sees four of five changes and no sign that a fifth was meant to be there.
    func testOneMalformedRowRejectsTheWholeRelease() {
        let markdown = """
        ---
        version: 1.1.0
        title: T
        ---

        ## Good

        Icon: timer
        Tint: brand

        Text.

        ## Bad

        Tint: brand

        Text with no icon.
        """
        XCTAssertNil(WhatsNewRelease.parse(markdown))
    }
}

/// When the screen is due. The rules are a pure function precisely so an install history can be
/// pinned here rather than acted out across two releases.
final class WhatsNewPolicyTests: XCTestCase {
    private let release = WhatsNewRelease(
        version: "1.1.0", title: "What's New",
        entries: [WhatsNewEntry(title: "A", blurb: "B", symbol: "timer", tint: .brand)])

    private func shouldShow(currentVersion: String = "1.1.0", lastSeen: String?) -> Bool {
        WhatsNewStore.shouldShow(release: release, currentVersion: currentVersion, lastSeen: lastSeen)
    }

    /// The case the screen exists for.
    func testShownOnceAfterAnUpgrade() {
        XCTAssertTrue(shouldShow(lastSeen: "1.0.3"))
    }

    func testNotShownAgainOnTheSameVersion() {
        XCTAssertFalse(shouldShow(lastSeen: "1.1.0"))
    }

    /// A first-ever launch has no "new" to show — and this is also what keeps the sheet out of the
    /// way of every other UI test, each of which starts from a clean install.
    func testNeverShownOnAFreshInstall() {
        XCTAssertFalse(shouldShow(lastSeen: nil))
    }

    /// Copy for an unreleased version is dormant, not early: bumping `MARKETING_VERSION` is what
    /// lights the screen up at release time.
    func testNotShownWhenTheCopyDescribesAnotherVersion() {
        XCTAssertFalse(shouldShow(currentVersion: "1.0.3", lastSeen: "1.0.2"))
    }

    // MARK: Stamping

    private func defaults(lastSeen: String?) -> UserDefaults {
        let suite = UserDefaults(suiteName: "WhatsNewPolicyTests.\(UUID().uuidString)")!
        if let lastSeen { suite.set(lastSeen, forKey: WhatsNewStore.lastSeenVersionKey) }
        return suite
    }

    /// A fresh install is brought silently up to date, so the screen appears on the *next* upgrade
    /// rather than never or immediately.
    func testFreshInstallIsStampedWithoutShowingAnything() {
        let store = defaults(lastSeen: nil)
        XCTAssertNil(WhatsNewStore.pending(release: release, currentVersion: "1.1.0",
                                           defaults: store, forced: false))
        XCTAssertEqual(store.string(forKey: WhatsNewStore.lastSeenVersionKey), "1.1.0")
    }

    func testShowingStampsSoItDoesNotReturnOnTheNextLaunch() {
        let store = defaults(lastSeen: "1.0.3")
        XCTAssertEqual(WhatsNewStore.pending(release: release, currentVersion: "1.1.0",
                                             defaults: store, forced: false), release)
        XCTAssertNil(WhatsNewStore.pending(release: release, currentVersion: "1.1.0",
                                           defaults: store, forced: false))
    }

    /// `BB_WHATS_NEW=1` — how the UI test and a demo build see a screen the version match would
    /// otherwise keep dormant.
    func testForcedIgnoresBothTheVersionMatchAndTheFreshInstallRule() {
        XCTAssertEqual(WhatsNewStore.pending(release: release, currentVersion: "1.0.3",
                                             defaults: defaults(lastSeen: nil), forced: true),
                       release)
    }

    /// Nothing to show when the copy failed to parse — the fail-closed path reaching the presenter.
    func testNoReleaseMeansNoScreen() {
        XCTAssertNil(WhatsNewStore.pending(release: nil, currentVersion: "1.1.0",
                                           defaults: defaults(lastSeen: "1.0.3"), forced: true))
    }
}

#if DEBUG
/// The screen's signals. Asserted on the whole parameter dictionary, like the rest of the
/// analytics vocabulary, so a parameter that quietly appears fails rather than passes unnoticed.
final class WhatsNewAnalyticsTests: XCTestCase {
    private var recorder: SignalRecorder!

    override func setUp() {
        super.setUp()
        recorder = SignalRecorder()
    }

    override func tearDown() {
        recorder.stop()
        recorder = nil
        super.tearDown()
    }

    func testShownCarriesVersionAndRowCount() {
        Analytics.whatsNewShown(version: "1.1.0", entries: 5)
        XCTAssertEqual(recorder.parameters("WhatsNew.shown"), ["version": "1.1.0", "entries": "5"])
    }

    /// The three outcomes are one signal with an `action` dimension, so the funnel is a single
    /// query — and so "continued" and "swiped away" are never conflated into one dismissal.
    func testEachOutcomeIsDistinguishable() {
        for action in [Analytics.WhatsNewAction.continued, .support, .swiped] {
            let recorder = SignalRecorder()
            defer { recorder.stop() }
            Analytics.whatsNewDismissed(version: "1.1.0", action: action)
            XCTAssertEqual(recorder.parameters("WhatsNew.dismissed"),
                           ["version": "1.1.0", "action": action.rawValue])
        }
    }

    func testOutcomeRawValues() {
        XCTAssertEqual(Analytics.WhatsNewAction.continued.rawValue, "continued")
        XCTAssertEqual(Analytics.WhatsNewAction.support.rawValue, "support")
        XCTAssertEqual(Analytics.WhatsNewAction.swiped.rawValue, "swiped")
    }

    /// The attribution the owner asked for: a tip that starts on the What's New screen is
    /// separable from one that followed a nudge or came in from the deep link.
    func testSupporterSheetFromWhatsNewIsAttributedToIt() {
        Analytics.supporterSheetViewed(source: .whatsNew, state: .ask, offering: "default")
        XCTAssertEqual(recorder.parameters("Supporter.sheetViewed"),
                       ["source": "whatsNew", "state": "ask", "offering": "default"])
    }

    /// …and stays attributed all the way through the purchase, which is where it has to be right.
    func testTipFromWhatsNewKeepsTheAttribution() {
        Analytics.tipPurchaseStarted(tier: "medium", source: .whatsNew)
        Analytics.tipPurchased(tier: "medium", source: .whatsNew, offering: "default")
        XCTAssertEqual(recorder.parameters("Tip.purchaseStarted"),
                       ["tier": "medium", "source": "whatsNew"])
        XCTAssertEqual(recorder.parameters("Tip.purchased"),
                       ["tier": "medium", "source": "whatsNew", "offering": "default"])
    }
}
#endif
