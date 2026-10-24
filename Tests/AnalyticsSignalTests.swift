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
        Analytics.resetLaunchDedupe() // the once-per-launch dedupe outlives any one test
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
        XCTAssertEqual(Analytics.ActivitySource.sickMode.rawValue, "sickMode")
    }

    /// The period must arrive as the plain day count the segmented control offers, not a localized
    /// label, which would be free text. The fever chart rides along as one of two words: whether it
    /// had readings to draw, never what they were.
    func testInsightsViewedCarriesThePeriodAsADayCount() {
        for period in ChartPeriod.allCases {
            for chart in [Analytics.TemperatureChart.drawn, .empty] {
                let recorder = SignalRecorder()
                defer { recorder.stop() }
                Analytics.insightsViewed(periodDays: period.days, temperature: chart)
                XCTAssertEqual(recorder.parameters("Insights.viewed"),
                               ["period": String(period.days), "temperature": chart.rawValue])
            }
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

    // MARK: - Sync outcomes

    /// `Sync.finished` carries the closed outcome plus the queue census, so a drained sync is
    /// distinguishable from a partial one. Counts of rows only, never which records they were.
    func testSyncFinishedCarriesTheOutcomeAndTheQueueCensus() {
        Analytics.syncFinished(outcome: .partialBlocked, delivered: 2, uploaded: 1,
                               blockedNew: 1, blockedTotal: 3, queued: 0)
        XCTAssertEqual(recorder.parameters("Sync.finished"),
                       ["outcome": "partialBlocked", "delivered": "2", "uploaded": "1",
                        "blockedNew": "1", "blockedTotal": "3", "queued": "0"])
    }

    /// Each outcome is a dashboard series, so they must stay distinct, stably spelled, and carry
    /// the same six keys — a key missing on one branch reads as absent data rather than as a bug.
    func testEverySyncOutcomeIsDistinctAndCarriesTheSameKeys() {
        let outcomes: [Analytics.SyncOutcome] =
            [.drained, .partialBlocked, .transientFailure, .changedWithPendingWork]
        XCTAssertEqual(outcomes.map(\.rawValue),
                       ["drained", "partialBlocked", "transientFailure", "changedWithPendingWork"])
        XCTAssertEqual(Set(outcomes.map(\.rawValue)).count, outcomes.count)

        for outcome in outcomes {
            let recorder = SignalRecorder()
            defer { recorder.stop() }
            Analytics.syncFinished(outcome: outcome, delivered: 0, uploaded: 0,
                                   blockedNew: 0, blockedTotal: 0, queued: 0)
            XCTAssertEqual(recorder.parameters("Sync.finished"),
                           ["outcome": outcome.rawValue, "delivered": "0", "uploaded": "0",
                            "blockedNew": "0", "blockedTotal": "0", "queued": "0"])
        }
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

    /// The What's New card carries its entry point and nothing else — in particular not the release
    /// it described, which TelemetryDeck already attaches to every signal as a default parameter.
    func testWhatsNewSignalsCarryOnlyTheSource() {
        Analytics.whatsNewShown(source: .launch)
        Analytics.whatsNewContinued(source: .launch)
        Analytics.whatsNewSupporterTapped(source: .settings)
        Analytics.whatsNewDismissed(source: .settings)

        XCTAssertEqual(recorder.parameters("WhatsNew.shown"), ["source": "launch"])
        XCTAssertEqual(recorder.parameters("WhatsNew.continued"), ["source": "launch"])
        XCTAssertEqual(recorder.parameters("WhatsNew.supporterTapped"), ["source": "settings"])
        XCTAssertEqual(recorder.parameters("WhatsNew.dismissed"), ["source": "settings"])
    }

    /// Shown is one event and the ways out are mutually exclusive, so a funnel can be read as
    /// `shown` minus the three exits without any of them double-counting.
    func testWhatsNewHasOneShownAndThreeDistinctExits() {
        let names = ["WhatsNew.shown", "WhatsNew.continued",
                     "WhatsNew.supporterTapped", "WhatsNew.dismissed"]
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(Set(Analytics.WhatsNewSource.allCases.map(\.rawValue)),
                       ["launch", "settings"])
    }

    /// Pins the whole supporter-source vocabulary. Each support surface has to keep its own value
    /// or a tip lands in a shared bucket and the question "which screen earned this?" stops having
    /// an answer — which is the entire reason `source` is threaded through the purchase at all.
    func testEverySupportSurfaceHasItsOwnSource() {
        XCTAssertEqual(
            Analytics.SupporterSource.allCases.map(\.rawValue).sorted(),
            ["deeplink", "feedback", "nudgeBanner", "nudgeGentle", "nudgeMilestone", "settings", "whatsNew"])
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

    // MARK: - Errors

    /// `Error.serverRejected` covers six different failures at once, so the dimensions are the whole
    /// value of the signal: without them a rejection is unactionable, and a single un-deliverable
    /// queue entry retrying on every sync is indistinguishable from many users hitting one bug.
    func testServerRejectedCarriesWhereItHappenedAndWhichFields() {
        Analytics.report(.badRequest(status: 400, message: "amount: this field is required",
                                     fields: ["amount", "child"]),
                         context: "push-create-pumping", attempt: 3)
        XCTAssertEqual(recorder.parameters("Error.serverRejected"),
                       ["reason": "badRequest-400", "fields": "amount,child",
                        "context": "push-create-pumping", "attempt": "3"])
    }

    /// The server's message never leaves the device, only the keys it named — the values are
    /// whatever the user typed.
    func testServerRejectedNeverCarriesTheServersMessage() {
        Analytics.report(.badRequest(status: 400, message: "notes: 'Ollie fed at Grandma's'",
                                     fields: ["notes"]))
        let parameters = recorder.parameters("Error.serverRejected") ?? [:]
        XCTAssertEqual(parameters, ["reason": "badRequest-400", "fields": "notes"])
        XCTAssertFalse(parameters.values.contains { $0.contains("Ollie") })
    }

    /// A record-level rejection names which Baby Buddy rule it was, never the message.
    func testServerRejectedCarriesTheRuleNotTheMessage() {
        Analytics.report(.badRequest(status: 400,
                                     message: "Another entry intersects the specified time period. Conflicting entry: Feeding (1:09 a.m. - 1:24 a.m.)",
                                     fields: ["non_field_errors"]))
        XCTAssertEqual(recorder.parameters("Error.serverRejected"),
                       ["reason": "badRequest-400", "fields": "non_field_errors", "rule": "overlap"])
    }

    /// A tag pull that can't read the response is the failure this dimension exists for: `decoding`
    /// alone can't separate a server shape worth supporting from a proxy page, and the answer to
    /// those two is completely different.
    func testDecodingCarriesTheListShapeWhenSplitPageNamedOne() {
        Analytics.report(.decoding(Analytics.ListShape.objectMissingResults.rawValue),
                         context: "pull-tags")
        XCTAssertEqual(recorder.parameters("Error.serverRejected"),
                       ["reason": "decoding", "shape": "objectMissingResults",
                        "context": "pull-tags"])
    }

    /// The privacy guarantee of `shape`: it is reported only when it round-trips through the closed
    /// vocabulary. Every other decode failure carries a `DecodingError` description, which can
    /// quote the value it choked on — so an unrecognized detail must be dropped, not sent.
    func testDecodingNeverCarriesAFreeTextDetailAsAShape() {
        Analytics.report(.decoding("No value associated with key notes (\"Ollie fed at Grandma's\")"))
        let parameters = recorder.parameters("Error.serverRejected") ?? [:]
        XCTAssertEqual(parameters, ["reason": "decoding"])
        XCTAssertFalse(parameters.values.contains { $0.contains("Ollie") })
    }

    /// The shape names are a dashboard's x-axis, so they must stay distinct and stably spelled.
    func testEveryListShapeIsDistinctAndSpelledAsExpected() {
        let shapes: [Analytics.ListShape] = [.objectMissingResults, .nonJSON, .unexpectedJSONType]
        XCTAssertEqual(shapes.map(\.rawValue),
                       ["objectMissingResults", "nonJSON", "unexpectedJSONType"])
        XCTAssertEqual(Set(shapes.map(\.rawValue)).count, shapes.count)
    }

    /// Connectivity stays on `Error.network`; only the server's own refusals are "rejected".
    func testTransportFailuresAreNotServerRejections() {
        Analytics.report(.offline())
        Analytics.report(.server(status: 502))
        XCTAssertEqual(recorder.names, ["Error.network", "Error.network"])
        XCTAssertEqual(recorder.signals.map { $0.parameters["reason"] }, ["offline", "server-502"])
    }

    /// "Can't connect" is the support burden of a self-hosted app, and the four causes need four
    /// different answers from us — so they must not arrive as one undifferentiated `offline`.
    func testTransportFailuresKeepTheirCause() {
        let codes: [URLError.Code] = [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
                                      .serverCertificateUntrusted, .timedOut, .badServerResponse]
        XCTAssertEqual(codes.map { APIError.TransportFailure($0).rawValue },
                       ["offline", "dns", "cannotConnect", "tls", "timeout", "other"])

        Analytics.report(.offline(reason: .tls), context: "signIn")
        XCTAssertEqual(recorder.parameters("Error.network"),
                       ["reason": "tls", "context": "signIn"])
    }

    /// A missing endpoint is a fact about the server, not about this sync — the second report of
    /// the same one is pure billing.
    func testEndpointMissingIsReportedOncePerEndpoint() {
        Analytics.serverEndpointMissing("pumping")
        Analytics.serverEndpointMissing("pumping")
        Analytics.serverEndpointMissing("tags")
        XCTAssertEqual(recorder.names, ["Server.endpointMissing", "Server.endpointMissing"])
        XCTAssertEqual(recorder.signals.map { $0.parameters["endpoint"] }, ["pumping", "tags"])
    }

    /// An offline phone or a broken pull fails the same way on every sync, so each reason and
    /// context is reported once per launch. A different reason or context still gets through.
    func testNetworkErrorsAndPullFailuresAreReportedOncePerLaunch() {
        for attempt in 1...3 {
            Analytics.report(.offline(), context: "push-create-feeding", attempt: attempt)
            Analytics.report(.decoding("nonJSON"), context: "pull-tags")
            Analytics.error(network: "pull-unknown")
        }
        Analytics.report(.offline(), context: "pull-tags")
        Analytics.report(.server(status: 502), context: "push-create-feeding")
        XCTAssertEqual(recorder.names, ["Error.network", "Error.serverRejected", "Error.network",
                                        "Error.network", "Error.network"])
        XCTAssertEqual(recorder.parameters("Error.network"),
                       ["reason": "offline", "context": "push-create-feeding", "attempt": "1"])
    }

    /// A push or upload rejection already fires once, when its row is parked, so every one is sent.
    func testPushRejectionsAreNotDeduplicated() {
        Analytics.report(.notFound, context: "push-create-pumping", attempt: 1)
        Analytics.report(.notFound, context: "push-create-pumping", attempt: 1)
        XCTAssertEqual(recorder.names, ["Error.serverRejected", "Error.serverRejected"])
    }

    // MARK: - Sick mode

    /// Only which way it was turned on or off: nothing about the child, the readings, or how long.
    func testSickModeStartAndEndCarryOnlyTheirSource() {
        Analytics.sickModeStarted(source: .addSheet)
        Analytics.sickModeEnded(source: .endPrompt)
        XCTAssertEqual(recorder.parameters("SickMode.started"), ["source": "addSheet"])
        XCTAssertEqual(recorder.parameters("SickMode.ended"), ["source": "endPrompt"])
    }

    func testEverySickModeSourceIsSpelledAsExpected() {
        XCTAssertEqual(Analytics.SickModeStart.allCases.map(\.rawValue), ["banner", "addSheet", "settings"])
        XCTAssertEqual(Analytics.SickModeEnd.allCases.map(\.rawValue), ["endPrompt", "home", "settings"])
    }

    /// The banner and prompt signals are counts, so they carry nothing at all.
    func testSickModeBannerAndPromptSignalsCarryNothing() {
        Analytics.sickModeBannerShown()
        Analytics.sickModeBannerDismissed()
        Analytics.sickModeEndPromptShown()
        Analytics.sickModeKeptOn()
        Analytics.sickModeEndUndone()
        XCTAssertEqual(recorder.names, ["SickMode.bannerShown", "SickMode.bannerDismissed",
                                        "SickMode.endPromptShown", "SickMode.keptOn", "SickMode.endUndone"])
        XCTAssertTrue(recorder.signals.allSatisfy { $0.parameters.isEmpty })
    }

    /// Home redraws, tab switches and relaunches all bring the banner back on screen; only a new
    /// reading is a new banner.
    @MainActor
    func testBannerIsCountedOncePerReading() {
        let defaults = UserDefaults(suiteName: "AnalyticsSickMode-\(UUID())")!
        let store = SickModeStore(defaults: defaults)
        let first = UUID(), second = UUID()
        store.countBanner(1, reading: first)
        store.countBanner(1, reading: first)
        store.countBanner(1, reading: second)
        SickModeStore(defaults: defaults).countBanner(1, reading: second) // after a relaunch
        XCTAssertEqual(recorder.names, ["SickMode.bannerShown", "SickMode.bannerShown"])
    }

    /// The prompt appears once after the start and again after each "Keep it on" runs out.
    @MainActor
    func testEndPromptIsCountedOncePerAppearance() {
        let store = SickModeStore(defaults: UserDefaults(suiteName: "AnalyticsSickMode-\(UUID())")!)
        store.start(1, at: .now.addingTimeInterval(-3 * 86_400))
        store.countEndPrompt(1)
        store.countEndPrompt(1)
        store.keepOn(1, until: .now.addingTimeInterval(-60))
        store.countEndPrompt(1)
        XCTAssertEqual(recorder.names, ["SickMode.endPromptShown", "SickMode.endPromptShown"])
    }

    /// Undo on "Sick mode ended" restores the same start, and counts as an undo, not a new start.
    @MainActor
    func testUndoingAnEndIsNotAStart() throws {
        let store = SickModeStore(defaults: UserDefaults(suiteName: "AnalyticsSickMode-\(UUID())")!)
        let container = LocalStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let startedAt = Date.now.addingTimeInterval(-3600)
        store.turnOn(1, at: startedAt, source: .settings)
        store.turnOff(1, source: .home, in: context)
        UndoToastCenter.shared.undo(in: context)
        XCTAssertEqual(store[1].startedAt, startedAt)
        XCTAssertEqual(recorder.names, ["SickMode.started", "SickMode.ended", "SickMode.endUndone"])
        XCTAssertEqual(recorder.parameters("SickMode.started"), ["source": "settings"])
        XCTAssertEqual(recorder.parameters("SickMode.ended"), ["source": "home"])
    }

    // MARK: - Feedback

    func testFeedbackSignalsCarryOnlyTheirEnum() {
        Analytics.feedbackOpened(signedIn: true)
        Analytics.feedbackWidgetOpened(view: .help)
        Analytics.feedbackLinkTapped(.serverGitHub)
        Analytics.feedbackSignInStarted(from: .feature)
        Analytics.feedbackSignInCompleted(method: .password)
        Analytics.feedbackSignInFailed(reason: .rateLimited)
        Analytics.feedbackDeletionRequested(result: .cancelled)
        XCTAssertEqual(recorder.parameters("Feedback.opened"), ["signedIn": "true"])
        XCTAssertEqual(recorder.parameters("Feedback.widgetOpened"), ["view": "help"])
        XCTAssertEqual(recorder.parameters("Feedback.linkTapped"), ["link": "serverGitHub"])
        XCTAssertEqual(recorder.parameters("Feedback.signInStarted"), ["from": "feature"])
        XCTAssertEqual(recorder.parameters("Feedback.signInCompleted"), ["method": "password"])
        XCTAssertEqual(recorder.parameters("Feedback.signInFailed"), ["reason": "rateLimited"])
        XCTAssertEqual(recorder.parameters("Feedback.deletionRequested"), ["result": "cancelled"])
    }

    func testFeedbackCountsCarryNothing() {
        Analytics.feedbackSignedOut()
        Analytics.feedbackAppDetailsCopied()
        Analytics.feedbackOffline()
        XCTAssertEqual(recorder.names, ["Feedback.signedOut", "Feedback.appDetailsCopied", "Feedback.offline"])
        XCTAssertTrue(recorder.signals.allSatisfy { $0.parameters.isEmpty })
    }

    func testEveryFeedbackValueIsSpelledAsExpected() {
        XCTAssertEqual(Analytics.FeedbackView.allCases.map(\.rawValue), ["feature", "help", "roadmap"])
        XCTAssertEqual(Analytics.FeedbackLink.allCases.map(\.rawValue),
                       ["kurtis", "openSource", "serverGitHub", "sourceCode", "rate"])
        XCTAssertEqual(Analytics.FeedbackSignInMethod.allCases.map(\.rawValue), ["code", "password"])
        XCTAssertEqual(Analytics.FeedbackSignInFailure.allCases.map(\.rawValue),
                       ["wrongCode", "wrongPassword", "rateLimited", "network", "other"])
        XCTAssertEqual(Analytics.FeedbackDeletionResult.allCases.map(\.rawValue), ["sent", "failed", "cancelled"])
        XCTAssertEqual([FeedbackWidget.board, .help, .roadmap].map(\.analyticsView), [.feature, .help, .roadmap])
    }
}
#endif
