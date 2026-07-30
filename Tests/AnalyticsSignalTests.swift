import XCTest
@testable import BabyBuddy

#if DEBUG
/// Captures what the typed ``Analytics`` helpers emit, via the DEBUG-only recorder seam.
///
/// Signals are fire-and-forget and normally no-ops in a test host (no App ID is configured), so
/// without this the whole vocabulary is unverifiable — and its correctness is not cosmetic: a
/// parameter that silently stops being attached, or carries the wrong value, produces a dashboard
/// that reads fine and means something else.
final class SignalRecorder {
    private(set) var signals: [(name: String, parameters: [String: String])] = []

    init() {
        Analytics.recorder = { [weak self] name, parameters in
            self?.signals.append((name, parameters))
        }
    }

    /// Detach the seam. Always `defer` this — a leaked recorder would capture another test's signals.
    func stop() { Analytics.recorder = nil }

    var names: [String] { signals.map(\.name) }

    /// The parameters of the one signal with this name, or `nil` if it wasn't emitted.
    func parameters(_ name: String) -> [String: String]? {
        signals.first { $0.name == name }?.parameters
    }
}

/// Pins the signal names and parameter dictionaries of the analytics vocabulary.
///
/// The privacy promise is enforced here as much as the funnel is: `PRIVACY.md` enumerates exactly
/// what leaves the device, so a parameter set that quietly grows is a documentation defect as well
/// as a behavioural one. Every assertion below is on the *whole* dictionary rather than on
/// individual keys, so an added parameter fails rather than passes unnoticed.
final class AnalyticsSignalTests: XCTestCase {
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

    // MARK: - Supporter funnel

    /// The sheet's own signal: the door someone came through, what the sheet had to show them, and
    /// the offering serving it. `state` is the reason this exists — a failed offering fetch is
    /// deliberately silent, so without it a build with nothing to sell is invisible in the field.
    func testSupporterSheetViewedCarriesSourceStateAndOffering() {
        Analytics.supporterSheetViewed(source: .nudgeMilestone, state: .ask, offering: "default")
        XCTAssertEqual(recorder.parameters("Supporter.sheetViewed"),
                       ["source": "nudgeMilestone", "state": "ask", "offering": "default"])
    }

    /// No offering loaded is the case the `unavailable` states exist to report, so the signal has to
    /// survive it — omitting the key rather than inventing a value for it.
    func testSupporterSheetViewedOmitsTheOfferingWhenNoneHasLoaded() {
        Analytics.supporterSheetViewed(source: .settings, state: .unavailableNoTips)
        XCTAssertEqual(recorder.parameters("Supporter.sheetViewed"),
                       ["source": "settings", "state": "unavailableNoTips"])
    }

    /// Every state the sheet can settle into must be reportable and distinct — the two `unavailable`
    /// cases especially, which mean very different things (a broken store vs. a build with no key).
    func testEverySheetStateIsDistinct() {
        let states: [Analytics.SupporterSheetState] =
            [.ask, .thankYou, .unavailableNoTips, .unavailableUnconfigured]
        XCTAssertEqual(Set(states.map(\.rawValue)).count, states.count)
    }

    /// Replaces the deleted `Supporter.ctaPressed`: a supporter reopening the amounts is its own
    /// interaction, whereas the old CTA signal fired on the same tap as the sheet view.
    func testTipAgainIsItsOwnParameterlessSignal() {
        Analytics.supporterTipAgainPressed()
        XCTAssertEqual(recorder.names, ["Supporter.tipAgainPressed"])
        XCTAssertEqual(recorder.parameters("Supporter.tipAgainPressed"), [:])
    }

    // MARK: - Core coverage

    /// `Activity.logged` gained `source`: the four paths are wildly different amounts of effort for
    /// the same record, and `LocalRepository.create` is the only place that distinction still exists.
    func testActivityLoggedCarriesKindAndSource() {
        Analytics.activityLogged(kind: "change", source: .intent)
        XCTAssertEqual(recorder.parameters("Activity.logged"),
                       ["kind": "change", "source": "intent"])
    }

    func testEveryActivitySourceIsDistinctAndSpelledAsExpected() {
        XCTAssertEqual(Analytics.ActivitySource.editor.rawValue, "editor")
        XCTAssertEqual(Analytics.ActivitySource.repeat.rawValue, "repeat")
        XCTAssertEqual(Analytics.ActivitySource.timerStop.rawValue, "timerStop")
        XCTAssertEqual(Analytics.ActivitySource.intent.rawValue, "intent")
    }

    /// The Trends tab is parameterized by exactly one thing, and the period must arrive as the plain
    /// day count the segmented control offers — not a localized label, which would be free text.
    func testInsightsViewedCarriesThePeriodAsADayCount() {
        for period in ChartPeriod.allCases {
            let recorder = SignalRecorder()
            defer { recorder.stop() }
            Analytics.insightsViewed(periodDays: period.days)
            XCTAssertEqual(recorder.parameters("Insights.viewed"), ["period": String(period.days)])
        }
        // …and those really are the three the app offers.
        XCTAssertEqual(ChartPeriod.allCases.map(\.days), [7, 14, 30])
    }

    /// Completes the loop with `Sync.conflictRaised`: how often conflicts happen, and whether the
    /// resolution screen is understood well enough that anyone reaches for Merge.
    func testConflictResolvedCarriesChoiceAndKind() {
        Analytics.syncConflictResolved(choice: .merge, kind: "feeding")
        XCTAssertEqual(recorder.parameters("Sync.conflictResolved"),
                       ["choice": "merge", "kind": "feeding"])

        let choices: [Analytics.ConflictChoice] = [.mine, .server, .merge]
        XCTAssertEqual(choices.map(\.rawValue), ["mine", "server", "merge"])
    }

    /// A name and a boolean, and nothing else — never the value the setting governs.
    func testSettingChangedCarriesOnlyTheNameAndTheBool() {
        Analytics.settingChanged("appLock", enabled: true)
        XCTAssertEqual(recorder.parameters("Settings.changed"),
                       ["setting": "appLock", "enabled": "true"])
    }

    // MARK: - Nudges

    /// The milestone parameter is a round threshold or nothing at all — it must never be able to
    /// carry the actual entry count, which is closer to being data about a specific baby.
    func testNudgeShownCarriesTheMilestoneOnlyWhenThereIsOne() {
        Analytics.nudgeShown(variant: .milestone, milestone: 250)
        XCTAssertEqual(recorder.parameters("Nudge.shown"),
                       ["variant": "milestone", "milestone": "250"])

        let plain = SignalRecorder()
        defer { plain.stop() }
        Analytics.nudgeShown(variant: .gentle)
        XCTAssertEqual(plain.parameters("Nudge.shown"), ["variant": "gentle"])
    }

    func testNudgeDismissedAndRetiredCarryTheTally() {
        Analytics.nudgeDismissed(variant: .banner, dismissCount: 2)
        Analytics.nudgeRetired()
        XCTAssertEqual(recorder.parameters("Nudge.dismissed"),
                       ["variant": "banner", "dismissCount": "2"])
        XCTAssertEqual(recorder.parameters("Nudge.retired"), [:])
    }

    /// Conversions are attributed through ``Analytics/SupporterSource``, deliberately without a
    /// `Nudge.converted` signal — TelemetryDeck is signal-based, so a cross-signal join would be the
    /// wrong shape. Each nudge variant therefore has to map onto its own supporter source.
    func testEveryNudgeVariantHasItsOwnSupporterSource() {
        let sources = [SupportNudge.gentleAsk, .milestone(50), .banner].compactMap(\.supporterSource)
        XCTAssertEqual(sources, [.nudgeGentle, .nudgeMilestone, .nudgeBanner])
        XCTAssertEqual(Set(sources.map(\.rawValue)).count, 3)
    }
}
#endif
