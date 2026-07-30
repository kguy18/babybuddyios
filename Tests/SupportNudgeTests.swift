import XCTest
@testable import BabyBuddy

/// One test per rule in the support-nudge policy. The policy is pure and takes both its calendar and
/// its `now`, so every rule below is exercised at a fixed instant rather than by waiting three weeks.
final class SupportNudgeTests: XCTestCase {
    /// A UTC calendar so day boundaries are deterministic regardless of the test machine's zone.
    private let manager = SupportNudgeManager(calendar: {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }())

    /// Fixed "now": 2026-06-15T12:00Z.
    private let now = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!

    /// `days` before ``now``, at noon — so a whole-calendar-day count isn't sensitive to the hour.
    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// State that satisfies every gate: past day 7, well past 10 entries, nothing shown yet.
    private func eligible(
        firstLaunch: Int = 30,
        lastNudge: Int? = nil,
        loggedEntries: Int = 20,
        lastMilestone: Int = 0,
        dismissCount: Int = 0,
        remindersEnabled: Bool = true
    ) -> SupportNudgeState {
        SupportNudgeState(
            firstLaunch: daysAgo(firstLaunch),
            loggedEntries: loggedEntries,
            lastNudge: lastNudge.map(daysAgo),
            lastMilestone: lastMilestone,
            dismissCount: dismissCount,
            remindersEnabled: remindersEnabled)
    }

    private func nudge(_ state: SupportNudgeState, isSupporter: Bool = false) -> SupportNudge {
        manager.nudge(now: now, state: state, isSupporter: isSupporter)
    }

    // MARK: The day-7 gate

    func testNothingBeforeTheSeventhDay() {
        XCTAssertEqual(nudge(eligible(firstLaunch: 0)), .none)
        XCTAssertEqual(nudge(eligible(firstLaunch: 6)), .none)
        XCTAssertEqual(nudge(eligible(firstLaunch: 7)), .gentleAsk, "day 7 is the threshold, inclusive")
    }

    /// No first launch recorded yet — every time-based rule must fail closed rather than fire.
    func testNothingWithoutARecordedFirstLaunch() {
        var state = eligible()
        state.firstLaunch = nil
        XCTAssertEqual(nudge(state), .none)
    }

    // MARK: The entry-count gate

    func testNothingBeforeTenLoggedEntries() {
        XCTAssertEqual(nudge(eligible(loggedEntries: 0)), .none)
        XCTAssertEqual(nudge(eligible(loggedEntries: 9)), .none)
        XCTAssertEqual(nudge(eligible(loggedEntries: 10)), .gentleAsk)
    }

    /// Both gates, not either: a long-installed app that was never used is as unqualified as a
    /// heavily-used one on its first day.
    func testBothGatesAreRequired() {
        XCTAssertEqual(nudge(eligible(firstLaunch: 400, loggedEntries: 3)), .none)
        XCTAssertEqual(nudge(eligible(firstLaunch: 1, loggedEntries: 900)), .none)
    }

    // MARK: The gentle ask

    func testGentleAskIsTheFirstNudgeAndOnlyShownOnce() {
        XCTAssertEqual(nudge(eligible()), .gentleAsk)
        // Shown 40 days ago, no milestone crossed since: the cap has expired, but the ask doesn't
        // repeat — after the opener, only a milestone earns an interruption.
        XCTAssertEqual(nudge(eligible(lastNudge: 40, loggedEntries: 20)), .none)
    }

    /// A milestone already crossed cannot pre-empt the opener.
    func testGentleAskComesBeforeAnyMilestone() {
        XCTAssertEqual(nudge(eligible(loggedEntries: 600)), .gentleAsk)
    }

    // MARK: Milestones

    func testMilestoneFiresAtEachThreshold() {
        for (index, milestone) in SupportNudgeManager.milestones.enumerated() {
            let previous = index == 0 ? 0 : SupportNudgeManager.milestones[index - 1]
            let state = eligible(lastNudge: 30, loggedEntries: milestone, lastMilestone: previous)
            XCTAssertEqual(nudge(state), .milestone(milestone))
        }
    }

    func testMilestoneWaitsForTheThreshold() {
        XCTAssertEqual(nudge(eligible(lastNudge: 30, loggedEntries: 49)), .none)
        XCTAssertEqual(nudge(eligible(lastNudge: 30, loggedEntries: 50)), .milestone(50))
    }

    func testEachMilestoneCelebratesOnlyOnce() {
        let state = eligible(lastNudge: 30, loggedEntries: 60, lastMilestone: 50)
        XCTAssertEqual(nudge(state), .none)
    }

    /// Someone who logged from 40 to 260 while the cap held a nudge back is congratulated on 250 —
    /// not walked up through a backlog of thresholds they left behind weeks ago.
    func testMilestonePicksTheHighestCrossedThreshold() {
        XCTAssertEqual(nudge(eligible(lastNudge: 30, loggedEntries: 260)), .milestone(250))
    }

    func testMilestoneStopsAfterTheLastThreshold() {
        let state = eligible(lastNudge: 30, loggedEntries: 5_000, lastMilestone: 1_000)
        XCTAssertEqual(nudge(state), .none)
    }

    // MARK: The 21-day global cap

    func testNoTwoNudgesInsideTwentyOneDays() {
        // A milestone is sitting there waiting, but the cap outranks it.
        for days in [0, 1, 20] {
            XCTAssertEqual(nudge(eligible(lastNudge: days, loggedEntries: 500)), .none,
                           "a nudge \(days) days ago must still be holding the cap")
        }
        XCTAssertEqual(nudge(eligible(lastNudge: 21, loggedEntries: 500)), .milestone(500))
    }

    /// Showing a nudge restarts the cap — and marks a milestone celebrated in the same move.
    func testShowingANudgeRestartsTheCapAndRetiresItsMilestone() {
        let before = eligible(lastNudge: 30, loggedEntries: 500)
        let after = manager.state(showing: .milestone(500), at: now, from: before)
        XCTAssertEqual(after.lastNudge, now)
        XCTAssertEqual(after.lastMilestone, 500)
        XCTAssertEqual(manager.nudge(now: now, state: after, isSupporter: false), .none)
    }

    // MARK: Dismiss = snooze

    func testDismissSnoozesForAtLeastTwentyOneDays() {
        // Shown, then turned down: the tally goes up and the snooze is the shown-at cap.
        var state = eligible(loggedEntries: 500)
        state = manager.state(showing: .gentleAsk, at: now, from: state)
        state = manager.state(afterDismissal: state)
        XCTAssertEqual(state.dismissCount, 1)

        let twentyDaysLater = now.addingTimeInterval(20 * 86_400)
        XCTAssertEqual(manager.nudge(now: twentyDaysLater, state: state, isSupporter: false), .none)

        let threeWeeksLater = now.addingTimeInterval(21 * 86_400)
        XCTAssertEqual(manager.nudge(now: threeWeeksLater, state: state, isSupporter: false),
                       .milestone(500))
    }

    // MARK: Retirement after three dismissals

    func testPopupsRetireAfterThreeDismissals() {
        XCTAssertFalse(manager.isRetired(eligible(dismissCount: 2)))
        XCTAssertTrue(manager.isRetired(eligible(dismissCount: 3)))

        // Two dismissals still leave the milestone popup available…
        XCTAssertEqual(nudge(eligible(lastNudge: 30, loggedEntries: 500, dismissCount: 2)),
                       .milestone(500))
        // …three retire it permanently, leaving only the quiet banner.
        XCTAssertEqual(nudge(eligible(lastNudge: 40, loggedEntries: 500, dismissCount: 3)), .banner)
        // Even with every milestone still unclaimed and years having passed.
        XCTAssertEqual(nudge(eligible(firstLaunch: 900, lastNudge: 900,
                                      loggedEntries: 9_000, dismissCount: 9)), .banner)
    }

    // MARK: The banner's monthly cap

    func testBannerIsCappedToOnceAMonth() {
        for days in [0, 21, 29] {
            XCTAssertEqual(nudge(eligible(lastNudge: days, loggedEntries: 500, dismissCount: 3)), .none,
                           "a banner \(days) days ago is inside the 30-day window")
        }
        XCTAssertEqual(nudge(eligible(lastNudge: 30, loggedEntries: 500, dismissCount: 3)), .banner)
    }

    // MARK: Reminders off

    func testRemindersOffSilencesEverySurface() {
        XCTAssertEqual(nudge(eligible(remindersEnabled: false)), .none)
        XCTAssertEqual(nudge(eligible(lastNudge: 40, loggedEntries: 500, remindersEnabled: false)),
                       .none)
        XCTAssertEqual(nudge(eligible(lastNudge: 40, loggedEntries: 500, dismissCount: 3,
                                      remindersEnabled: false)), .none)
    }

    // MARK: Supporters

    func testSupporterSeesNothingEver() {
        XCTAssertEqual(nudge(eligible(), isSupporter: true), .none)
        XCTAssertEqual(nudge(eligible(lastNudge: 40, loggedEntries: 500), isSupporter: true), .none)
        // Including the banner, which outlives every popup.
        XCTAssertEqual(nudge(eligible(lastNudge: 40, loggedEntries: 500, dismissCount: 3),
                             isSupporter: true), .none)
    }

    /// Tipping from a nudge silences the rest: `isSupporter` is the only thing that changes, and it
    /// is enough on its own — there is no separate "converted" flag to set.
    func testTippingFromANudgeEndsAllNudges() {
        var state = eligible(loggedEntries: 500)
        state = manager.state(showing: .gentleAsk, at: now, from: state)
        let laterStill = now.addingTimeInterval(365 * 86_400)
        XCTAssertEqual(manager.nudge(now: laterStill, state: state, isSupporter: false),
                       .milestone(500), "control: without the tip, the ask would come back")
        XCTAssertEqual(manager.nudge(now: laterStill, state: state, isSupporter: true), .none)
    }

    // MARK: Remote configuration

    /// The acceptance criterion for making the policy tunable: with no offering metadata, the
    /// configured manager and the untouched one must agree on **every** decision, not merely on the
    /// headline ones. Swept across the whole state space the policy actually branches on.
    func testCompiledDefaultsAreIndistinguishableFromTheUntunedPolicy() {
        var configured = manager
        configured.config = SupporterRemoteConfig(metadata: nil)

        for firstLaunch in [0, 3, 6, 7, 8, 30, 900] {
            for lastNudge in [nil, 0, 6, 7, 13, 20, 21, 29, 30, 40] as [Int?] {
                for entries in [0, 9, 10, 49, 50, 100, 250, 500, 1000, 9_000] {
                    for lastMilestone in [0, 50, 500] {
                        for dismissals in [0, 1, 2, 3, 9] {
                            for supporter in [false, true] {
                                let state = eligible(
                                    firstLaunch: firstLaunch, lastNudge: lastNudge,
                                    loggedEntries: entries, lastMilestone: lastMilestone,
                                    dismissCount: dismissals)
                                XCTAssertEqual(
                                    configured.nudge(now: now, state: state, isSupporter: supporter),
                                    manager.nudge(now: now, state: state, isSupporter: supporter),
                                    """
                                    diverged at firstLaunch=\(firstLaunch) \
                                    lastNudge=\(String(describing: lastNudge)) entries=\(entries) \
                                    lastMilestone=\(lastMilestone) dismissals=\(dismissals) \
                                    supporter=\(supporter)
                                    """)
                            }
                        }
                    }
                }
            }
        }
    }

    /// A tuned manager, so the knobs are demonstrably wired to the rules they name rather than
    /// merely parsed. Each assertion pairs with the default-behaviour test above it in this file.
    private func tuned(_ body: [String: Any]) -> SupportNudgeManager {
        var tuned = manager
        tuned.config = SupporterRemoteConfig(
            metadata: [SupporterRemoteConfig.metadataKey: body])
        return tuned
    }

    func testRemoteKillSwitchSilencesEverySurface() {
        let off = tuned(["nudgesEnabled": false])
        // The three states that would otherwise each produce a different surface.
        XCTAssertEqual(off.nudge(now: now, state: eligible(), isSupporter: false), .none)
        XCTAssertEqual(off.nudge(now: now, state: eligible(lastNudge: 40, loggedEntries: 500),
                                 isSupporter: false), .none)
        XCTAssertEqual(off.nudge(now: now, state: eligible(lastNudge: 40, loggedEntries: 500,
                                                          dismissCount: 3), isSupporter: false), .none)
    }

    func testRemoteGatesMoveTheFirstAsk() {
        let later = tuned(["firstAskDay": 14, "minLoggedEntries": 40])
        XCTAssertEqual(later.nudge(now: now, state: eligible(firstLaunch: 13, loggedEntries: 100),
                                   isSupporter: false), .none, "day 13 is inside a 14-day gate")
        XCTAssertEqual(later.nudge(now: now, state: eligible(firstLaunch: 14, loggedEntries: 39),
                                   isSupporter: false), .none, "39 entries is under a 40 gate")
        XCTAssertEqual(later.nudge(now: now, state: eligible(firstLaunch: 14, loggedEntries: 40),
                                   isSupporter: false), .gentleAsk)
    }

    func testRemoteCapAndBannerWindowMoveTheirIntervals() {
        let longer = tuned(["capDays": 60, "bannerCapDays": 90])
        XCTAssertEqual(longer.nudge(now: now, state: eligible(lastNudge: 40, loggedEntries: 500),
                                    isSupporter: false), .none, "40 days is inside a 60-day cap")
        XCTAssertEqual(longer.nudge(now: now, state: eligible(lastNudge: 60, loggedEntries: 500),
                                    isSupporter: false), .milestone(500))
        XCTAssertEqual(longer.nudge(now: now, state: eligible(lastNudge: 60, loggedEntries: 500,
                                                             dismissCount: 3),
                                    isSupporter: false), .none, "the retired banner waits 90 days")
        XCTAssertEqual(longer.nudge(now: now, state: eligible(lastNudge: 90, loggedEntries: 500,
                                                             dismissCount: 3),
                                    isSupporter: false), .banner)
    }

    /// The snooze applies only once someone has actually refused, and only ever lengthens the gap —
    /// it is combined with the cap by `max`, so a shorter snooze can't undercut the routine spacing.
    func testSnoozeOnlyLengthensAndOnlyAfterARefusal() {
        let snoozed = tuned(["capDays": 21, "snoozeDays": 60])
        XCTAssertEqual(snoozed.nudge(now: now, state: eligible(lastNudge: 21, loggedEntries: 500),
                                     isSupporter: false), .milestone(500),
                       "nobody has refused, so the routine cap applies")
        XCTAssertEqual(snoozed.nudge(now: now, state: eligible(lastNudge: 21, loggedEntries: 500,
                                                              dismissCount: 1),
                                     isSupporter: false), .none, "a refusal buys the longer window")
        XCTAssertEqual(snoozed.nudge(now: now, state: eligible(lastNudge: 60, loggedEntries: 500,
                                                              dismissCount: 1),
                                     isSupporter: false), .milestone(500))

        let shortSnooze = tuned(["capDays": 30, "snoozeDays": 7])
        XCTAssertEqual(shortSnooze.nudge(now: now, state: eligible(lastNudge: 21, loggedEntries: 500,
                                                                   dismissCount: 1),
                                         isSupporter: false), .none,
                       "a snooze shorter than the cap must not shorten the gap")
    }

    func testRemoteMilestonesAndDismissalLimitApply() {
        let tuned = tuned(["milestones": [200], "maxDismissals": 1])
        XCTAssertEqual(tuned.nudge(now: now, state: eligible(lastNudge: 40, loggedEntries: 100),
                                   isSupporter: false), .none, "100 is no longer a milestone")
        XCTAssertEqual(tuned.nudge(now: now, state: eligible(lastNudge: 40, loggedEntries: 200),
                                   isSupporter: false), .milestone(200))
        XCTAssertTrue(tuned.isRetired(eligible(dismissCount: 1)))
        XCTAssertEqual(tuned.nudge(now: now, state: eligible(lastNudge: 40, loggedEntries: 200,
                                                             dismissCount: 1),
                                   isSupporter: false), .banner, "one refusal now retires the popups")
    }

    /// A dashboard typo can shorten the respectful spacing but never abolish it: the floors are
    /// enforced at parse time, so the policy can't be driven below them from outside.
    func testFloorsHoldWhenTheDashboardAsksForNothing() {
        let absurd = tuned(["firstAskDay": 0, "capDays": 0, "snoozeDays": 0, "bannerCapDays": 0])
        XCTAssertEqual(absurd.nudge(now: now, state: eligible(firstLaunch: 2, loggedEntries: 100),
                                    isSupporter: false), .none, "never on day 2, whatever is set")
        XCTAssertEqual(absurd.nudge(now: now, state: eligible(lastNudge: 6, loggedEntries: 500),
                                    isSupporter: false), .none, "never twice inside a week")
        XCTAssertEqual(absurd.nudge(now: now, state: eligible(lastNudge: 13, loggedEntries: 500,
                                                              dismissCount: 3),
                                    isSupporter: false), .none, "the banner keeps its fortnight")
    }

    // MARK: Surface metadata

    /// Each surface has to carry its own analytics variant and supporter-sheet source, since that
    /// source is the entire conversion signal.
    func testEachSurfaceCarriesItsVariantAndSource() {
        XCTAssertNil(SupportNudge.none.variant)
        XCTAssertNil(SupportNudge.none.supporterSource)
        XCTAssertEqual(SupportNudge.gentleAsk.variant, .gentle)
        XCTAssertEqual(SupportNudge.gentleAsk.supporterSource, .nudgeGentle)
        XCTAssertEqual(SupportNudge.milestone(50).variant, .milestone)
        XCTAssertEqual(SupportNudge.milestone(50).supporterSource, .nudgeMilestone)
        XCTAssertEqual(SupportNudge.milestone(50).milestoneCount, 50)
        XCTAssertEqual(SupportNudge.banner.variant, .banner)
        XCTAssertEqual(SupportNudge.banner.supporterSource, .nudgeBanner)
        XCTAssertNil(SupportNudge.banner.milestoneCount)
    }
}

// MARK: - Persistence

/// The store's own behavior: the namespaced keys, the defaults absent keys read as, and the
/// counters the policy is fed from.
@MainActor
final class SupportNudgeStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: SupportNudgeStore!
    private let suiteName = "SupportNudgeStoreTests"

    override func setUp() async throws {
        // A scratch suite, so a test run can never disturb the simulator's real counters.
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
        store = SupportNudgeStore(defaults: defaults)
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    func testFreshStoreHasRemindersOnAndNothingElse() {
        let state = store.state
        XCTAssertNil(state.firstLaunch)
        XCTAssertEqual(state.loggedEntries, 0)
        XCTAssertNil(state.lastNudge)
        XCTAssertEqual(state.lastMilestone, 0)
        XCTAssertEqual(state.dismissCount, 0)
        XCTAssertTrue(state.remindersEnabled, "the ask is opt-out, so an unset key means on")
    }

    /// "Deliberately off" has to survive a read — the bug this guards against silences the nudges
    /// for everyone by treating an absent key and `false` alike.
    func testRemindersOffIsDistinguishableFromUnset() {
        defaults.set(false, forKey: SupportNudgeStore.remindersEnabledKey)
        XCTAssertFalse(store.state.remindersEnabled)
    }

    func testFirstLaunchIsStampedExactlyOnce() {
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        store.registerFirstLaunch(now: first)
        store.registerFirstLaunch(now: first.addingTimeInterval(86_400))
        XCTAssertEqual(store.state.firstLaunch, first)
    }

    func testLoggedEntriesAccumulate() {
        for _ in 0..<12 { store.recordLoggedEntry() }
        XCTAssertEqual(store.state.loggedEntries, 12)
    }

    func testMarkShownPersistsTheCapAndTheMilestone() {
        let shownAt = Date(timeIntervalSince1970: 1_700_000_000)
        store.markShown(.milestone(250), now: shownAt)
        XCTAssertEqual(store.state.lastNudge, shownAt)
        XCTAssertEqual(store.state.lastMilestone, 250)

        // A later banner restarts the cap without disturbing the milestone tally.
        let later = shownAt.addingTimeInterval(40 * 86_400)
        store.markShown(.banner, now: later)
        XCTAssertEqual(store.state.lastNudge, later)
        XCTAssertEqual(store.state.lastMilestone, 250)
    }

    /// What reveals the Settings opt-out: nothing until an ask has actually been met, then always.
    func testHasShownANudgeOnlyAfterOneReachesTheScreen() {
        XCTAssertFalse(store.hasShownANudge, "a switch offered before the first ask asks about nothing")
        store.markShown(.gentleAsk, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(store.hasShownANudge)
        // Turning the reminders off must not hide the switch that turned them off.
        defaults.set(false, forKey: SupportNudgeStore.remindersEnabledKey)
        XCTAssertTrue(store.hasShownANudge)
    }

    func testMarkShownIgnoresNone() {
        store.markShown(.none, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(store.state.lastNudge)
    }

    func testDismissalsAccumulateToRetirement() {
        for expected in 1...3 {
            store.markDismissed(.gentle)
            XCTAssertEqual(store.state.dismissCount, expected)
        }
        XCTAssertTrue(store.manager.isRetired(store.state))
    }

    #if DEBUG
    // The debug affordances are how the day-7 and milestone gates get checked by hand — a real
    // purchase pins `isSupporter` on, and nobody can age an install seven days to order — so they
    // are worth pinning themselves.

    /// Arming an untouched install must produce the *opener*, decided by the real policy.
    func testDebugArmOffersTheGentleAskOnAFreshInstall() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.debugArm(now: now)
        XCTAssertEqual(store.pending(now: now, isSupporter: false), .gentleAsk)
    }

    /// …and arming an install that has already seen the opener must produce its next milestone,
    /// not the opener again. Arming clears the snooze; it must not erase the history.
    func testDebugArmOffersTheNextMilestoneOnceTheOpenerIsSpent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.markShown(.gentleAsk, now: now)
        for _ in 0..<60 { store.recordLoggedEntry() }
        store.debugArm(now: now)
        XCTAssertEqual(store.pending(now: now, isSupporter: false), .milestone(50))
    }

    /// A supporter stays silent even when armed — the affordance loosens the gates, not the rules.
    func testDebugArmStillRespectsSupporterSilence() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.debugArm(now: now)
        XCTAssertEqual(store.pending(now: now, isSupporter: true), .none)
    }

    func testDebugResetReturnsToAFreshInstall() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.registerFirstLaunch(now: now)
        store.recordLoggedEntry()
        store.markShown(.milestone(50), now: now)
        store.markDismissed(.milestone)

        store.debugReset()
        XCTAssertEqual(store.state, SupportNudgeState())
        XCTAssertEqual(store.pending(now: now, isSupporter: false), .none)
    }
    #endif

    /// The store's counters must reach the policy — the whole point of the persistence layer.
    func testPendingReflectsThePersistedCounters() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store = SupportNudgeStore(defaults: defaults,
                                  manager: SupportNudgeManager(calendar: calendar))

        store.registerFirstLaunch(now: now.addingTimeInterval(-30 * 86_400))
        XCTAssertEqual(store.pending(now: now, isSupporter: false), .none, "no entries logged yet")

        for _ in 0..<SupportNudgeManager.firstAskEntries { store.recordLoggedEntry() }
        XCTAssertEqual(store.pending(now: now, isSupporter: false), .gentleAsk)
        XCTAssertEqual(store.pending(now: now, isSupporter: true), .none)
    }
}
