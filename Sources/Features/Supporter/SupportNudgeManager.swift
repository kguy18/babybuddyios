import Foundation

/// Which support surface — if any — the Dashboard should offer right now.
///
/// The three asks de-escalate: one calm card the first time, celebratory milestone sheets after
/// that, and — once someone has said no often enough — nothing louder than an inline banner ever
/// again. ``SupportNudgeManager`` decides which of them is due.
enum SupportNudge: Equatable {
    /// Nothing to show.
    case none
    /// Variant A — the one-time centered "Enjoying Baby Buddy Companion?" card.
    case gentleAsk
    /// Variant B — the celebratory bottom sheet for a crossed logging milestone.
    case milestone(Int)
    /// Variant D — the quiet, dismissible inline banner.
    case banner

    /// The analytics variant this surface reports as, or `nil` for ``none``.
    var variant: Analytics.NudgeVariant? {
        switch self {
        case .none: return nil
        case .gentleAsk: return .gentle
        case .milestone: return .milestone
        case .banner: return .banner
        }
    }

    /// The supporter-sheet entry point this surface counts as, or `nil` for ``none``. A tip is
    /// attributed back to the nudge through this, so it has to travel with the surface.
    var supporterSource: Analytics.SupporterSource? {
        switch self {
        case .none: return nil
        case .gentleAsk: return .nudgeGentle
        case .milestone: return .nudgeMilestone
        case .banner: return .nudgeBanner
        }
    }

    /// The threshold a milestone nudge is celebrating, or `nil` for every other case.
    var milestoneCount: Int? {
        if case .milestone(let count) = self { return count }
        return nil
    }
}

/// Everything the nudge decision depends on, in one value — so the policy can stay a pure
/// function and a test can pin any history it likes without waiting three weeks for it.
struct SupportNudgeState: Equatable {
    /// When the app first ran on this device. `nil` until the first launch has been recorded, which
    /// makes every time-based rule fail closed.
    var firstLaunch: Date?

    /// How many activity records have been logged **from this device**.
    ///
    /// Deliberately not the size of the synced cache: a fresh install pointed at a year-old server
    /// would otherwise sail past the 1000-entry milestone before the app had done anything for
    /// anyone. Records logged from the widget's App Intents aren't counted either — the extension
    /// is a separate process with its own `UserDefaults` and no reach into these counters.
    var loggedEntries = 0

    /// When the most recent nudge of any variant was shown, or `nil` if none ever has been. Doubles
    /// as the "has the gentle ask happened?" signal, since it is always the first nudge shown.
    var lastNudge: Date?

    /// The highest milestone already asked at, so each threshold celebrates exactly once. `0` = none.
    var lastMilestone = 0

    /// How many nudges have been explicitly turned down. At
    /// ``SupportNudgeManager/retirementDismissals`` the popups retire for good.
    var dismissCount = 0

    /// The Settings ▸ "Support reminders" switch. Off silences every surface.
    var remindersEnabled = true
}

/// Decides which support nudge is due, and what the stored counters become once one is shown or
/// turned down.
///
/// Pure and injectable, in the shape of ``ChartAggregator``: `calendar` is a property and `now` is
/// a parameter, so every rule below is unit-testable. Persistence lives in ``SupportNudgeStore``
/// and the presenting lives in `DashboardView`; nothing here touches either.
///
/// The policy, in priority order:
/// - Supporters — and anyone who turned the reminders off — see nothing, permanently.
/// - Nothing at all before day ``firstAskDays`` **and** ``firstAskEntries`` logged records.
/// - The first ask is always the gentle card (A), and it is shown exactly once.
/// - After that, only a crossed milestone (B) earns an interruption.
/// - Never two nudges closer together than ``minimumIntervalDays``.
/// - After ``retirementDismissals`` dismissals the popups stop for good, leaving only the quiet
///   banner (D) at most once per ``bannerIntervalDays``.
struct SupportNudgeManager {
    /// Injectable so tests can pin a fixed time zone. Every window below is counted in whole
    /// calendar days, so a boundary doesn't shift with the hour of day someone opened the app.
    var calendar: Calendar = .current

    /// Days after the first launch before anything may be shown. The first week is pure product.
    static let firstAskDays = 7
    /// Records logged on this device before anything may be shown.
    static let firstAskEntries = 10
    /// Entry counts that earn a celebratory milestone ask, ascending.
    static let milestones = [50, 100, 250, 500, 1000]
    /// The global hard cap: no two nudges of any variant closer together than this.
    static let minimumIntervalDays = 21
    /// Dismissals after which the popups retire permanently.
    static let retirementDismissals = 3
    /// The quiet banner's own, longer window.
    static let bannerIntervalDays = 30

    // MARK: - Decision

    /// The surface due right now, or ``SupportNudge/none``.
    func nudge(now: Date, state: SupportNudgeState, isSupporter: Bool) -> SupportNudge {
        // A supporter has already done the thing we would be asking for, and someone who turned the
        // reminders off has said so in as many words. Both silence everything, for good.
        guard !isSupporter, state.remindersEnabled else { return .none }

        // No ask until the app has had a week to prove itself *and* has actually been used for
        // something. Either alone is too weak a signal to interrupt a new parent over.
        guard let firstLaunch = state.firstLaunch,
              days(from: firstLaunch, to: now) >= Self.firstAskDays,
              state.loggedEntries >= Self.firstAskEntries
        else { return .none }

        // Retired: the popups are done for good, and the banner is all that's left.
        if isRetired(state) {
            return isDue(state.lastNudge, after: Self.bannerIntervalDays, now: now) ? .banner : .none
        }

        // Everything below interrupts, so it waits out the global cap first.
        guard isDue(state.lastNudge, after: Self.minimumIntervalDays, now: now) else { return .none }

        // The gentle ask opens, once. After that only a milestone is worth a modal.
        guard state.lastNudge != nil else { return .gentleAsk }
        return milestone(for: state).map(SupportNudge.milestone) ?? .none
    }

    /// Whether the popups have retired — the point at which only the banner may still appear.
    func isRetired(_ state: SupportNudgeState) -> Bool {
        state.dismissCount >= Self.retirementDismissals
    }

    /// The highest crossed-but-uncelebrated milestone, or `nil` if there isn't one.
    ///
    /// Highest rather than lowest on purpose: someone who logged their way from 40 records to 260
    /// while the cap held a nudge back should be congratulated on 250, not walked up through a
    /// backlog of thresholds they left behind weeks ago.
    private func milestone(for state: SupportNudgeState) -> Int? {
        Self.milestones.last { $0 <= state.loggedEntries && $0 > state.lastMilestone }
    }

    // MARK: - Transitions

    /// The counters after `nudge` has reached the screen: the cap restarts, and a milestone is
    /// marked celebrated so that threshold can't come round again.
    func state(showing nudge: SupportNudge, at now: Date, from state: SupportNudgeState) -> SupportNudgeState {
        guard nudge != .none else { return state }
        var next = state
        next.lastNudge = now
        if let count = nudge.milestoneCount { next.lastMilestone = max(next.lastMilestone, count) }
        return next
    }

    /// The counters after a nudge has been turned down: one more on the tally, which is what
    /// eventually retires the popups.
    ///
    /// Only an explicit "no" gets here. Tapping through to the supporter sheet and closing it
    /// without tipping is an ask that landed, not one that was refused — the snooze from
    /// ``state(showing:at:from:)`` already keeps that from repeating for three weeks.
    func state(afterDismissal state: SupportNudgeState) -> SupportNudgeState {
        var next = state
        next.dismissCount += 1
        return next
    }

    // MARK: - Day arithmetic

    /// Whether `date` is at least `days` whole calendar days behind `now`. A `nil` date — nothing
    /// has happened yet — is always due.
    private func isDue(_ date: Date?, after days: Int, now: Date) -> Bool {
        guard let date else { return true }
        return self.days(from: date, to: now) >= days
    }

    /// Whole calendar days between two instants; negative if `to` precedes `from`.
    private func days(from: Date, to: Date) -> Int {
        calendar.dateComponents([.day],
                                from: calendar.startOfDay(for: from),
                                to: calendar.startOfDay(for: to)).day ?? 0
    }
}

// MARK: - Persistence

/// Stores the nudge counters and wraps ``SupportNudgeManager`` in the operations the UI actually
/// performs — "what's due?", "this one is on screen", "this one was turned down".
///
/// The counters live in the app's own `UserDefaults`, not the App Group suite: nothing outside the
/// app process asks whether a nudge is due, and a widget has no business being able to snooze one.
/// Every key is namespaced under `supportNudge.` so the group is obvious in a defaults dump.
@MainActor
final class SupportNudgeStore {
    /// The store the app runs on. Tests build their own against a scratch suite.
    static let shared = SupportNudgeStore()

    private enum Key {
        static let prefix = "supportNudge."
        static let firstLaunch = prefix + "firstLaunchDate"
        static let loggedEntries = prefix + "loggedEntryCount"
        static let lastNudge = prefix + "lastNudgeDate"
        static let lastMilestone = prefix + "lastMilestone"
        static let dismissCount = prefix + "dismissCount"
        static let remindersEnabled = prefix + "remindersEnabled"
    }

    /// The "Support reminders" key, exposed so the `@AppStorage` binding in Settings can't drift
    /// from the one the policy reads.
    static let remindersEnabledKey = Key.remindersEnabled

    private let defaults: UserDefaults
    let manager: SupportNudgeManager

    init(defaults: UserDefaults = .standard, manager: SupportNudgeManager = SupportNudgeManager()) {
        self.defaults = defaults
        self.manager = manager
    }

    // MARK: Reading

    /// The persisted counters. Absent keys read as the documented defaults — notably
    /// ``SupportNudgeState/remindersEnabled``, which is on until someone turns it off.
    var state: SupportNudgeState {
        SupportNudgeState(
            firstLaunch: defaults.object(forKey: Key.firstLaunch) as? Date,
            loggedEntries: defaults.integer(forKey: Key.loggedEntries),
            lastNudge: defaults.object(forKey: Key.lastNudge) as? Date,
            lastMilestone: defaults.integer(forKey: Key.lastMilestone),
            dismissCount: defaults.integer(forKey: Key.dismissCount),
            // `object(forKey:)` tells "never set" apart from "deliberately off"; `bool(forKey:)`
            // would collapse both to false and silence the nudges for everyone.
            remindersEnabled: defaults.object(forKey: Key.remindersEnabled) as? Bool ?? true)
    }

    /// Whether any nudge has ever been shown.
    ///
    /// The Settings opt-out hangs off this: someone should meet one ask before being handed the
    /// switch that turns them off, or the switch is asking them to decide about something they have
    /// no experience of. Safe for the gentle ask's own "Reminders can be turned off in Settings"
    /// fineprint, because ``markShown(_:now:)`` runs before the surface reaches the screen — by the
    /// time that line can be read, the switch it points at is there.
    var hasShownANudge: Bool {
        state.lastNudge != nil
    }

    /// The surface due right now, or ``SupportNudge/none``.
    func pending(now: Date = .now, isSupporter: Bool) -> SupportNudge {
        let state = self.state
        #if DEBUG
        if let forced = Self.debugForcedNudge(loggedEntries: state.loggedEntries) { return forced }
        #endif
        return manager.nudge(now: now, state: state, isSupporter: isSupporter)
    }

    // MARK: Writing

    /// Stamp this device's first launch, once. Every time-based rule hangs off it, so it is
    /// recorded at launch — before any Dashboard can ask the policy anything.
    func registerFirstLaunch(now: Date = .now) {
        guard defaults.object(forKey: Key.firstLaunch) == nil else { return }
        defaults.set(now, forKey: Key.firstLaunch)
    }

    /// Count one activity record logged on this device. Called from ``LocalRepository`` via the
    /// hook it installs at launch, which is the single place a record is created.
    func recordLoggedEntry() {
        defaults.set(defaults.integer(forKey: Key.loggedEntries) + 1, forKey: Key.loggedEntries)
    }

    /// Note that `nudge` reached the screen: restart the cap, retire its milestone, report it.
    func markShown(_ nudge: SupportNudge, now: Date = .now) {
        guard let variant = nudge.variant else { return }
        let next = manager.state(showing: nudge, at: now, from: state)
        defaults.set(next.lastNudge, forKey: Key.lastNudge)
        defaults.set(next.lastMilestone, forKey: Key.lastMilestone)
        Analytics.nudgeShown(variant: variant, milestone: nudge.milestoneCount)
    }

    /// Note that a nudge was turned down: count it, and report the retirement on the dismissal
    /// that crosses the line — exactly once, since the tally only ever goes up.
    func markDismissed(_ variant: Analytics.NudgeVariant) {
        let before = state
        let next = manager.state(afterDismissal: before)
        defaults.set(next.dismissCount, forKey: Key.dismissCount)
        Analytics.nudgeDismissed(variant: variant, dismissCount: next.dismissCount)
        if manager.isRetired(next), !manager.isRetired(before) { Analytics.nudgeRetired() }
    }

    #if DEBUG
    /// `BB_NUDGE=gentle|milestone|banner` puts a surface on screen regardless of the policy, so
    /// each one can be checked in the simulator without aging an install seven days. Follows the
    /// existing `BB_DEMO` / `BB_SEED_CONFLICT` launch-flag pattern and is compiled out of release.
    ///
    /// The forced milestone is the highest one actually crossed, falling back to 500 so a fresh
    /// demo install still shows a celebration that looks like the real thing.
    static func debugForcedNudge(loggedEntries: Int) -> SupportNudge? {
        switch ProcessInfo.processInfo.environment["BB_NUDGE"] {
        case "gentle": return .gentleAsk
        case "milestone":
            return .milestone(SupportNudgeManager.milestones.last { $0 <= loggedEntries } ?? 500)
        case "banner": return .banner
        default: return nil
        }
    }

    /// Debug-only: back to a fresh install — no first launch, no counters, no history. Use it to
    /// check that a new customer is left alone.
    func debugReset() {
        for key in [Key.firstLaunch, Key.loggedEntries, Key.lastNudge,
                    Key.lastMilestone, Key.dismissCount] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Debug-only: age this install past every gate and clear the snooze, so the **real** policy —
    /// not the `BB_NUDGE` force — offers whatever is genuinely next on the following Dashboard visit.
    ///
    /// Deliberately does not erase the history that decides *which* surface that is: a `nil`
    /// `lastNudge` still means the gentle ask hasn't happened, so an untouched install arms the
    /// opener while one that has seen it arms its next unclaimed milestone.
    func debugArm(now: Date = .now) {
        let calendar = manager.calendar
        let state = self.state

        defaults.set(calendar.date(byAdding: .day, value: -(SupportNudgeManager.firstAskDays + 1), to: now),
                     forKey: Key.firstLaunch)
        if state.loggedEntries < SupportNudgeManager.firstAskEntries {
            defaults.set(SupportNudgeManager.firstAskEntries, forKey: Key.loggedEntries)
        }
        // Far enough back to clear the banner's 30-day window as well as the 21-day cap.
        if state.lastNudge != nil {
            defaults.set(calendar.date(byAdding: .day,
                                       value: -(SupportNudgeManager.bannerIntervalDays + 1), to: now),
                         forKey: Key.lastNudge)
        }
    }
    #endif
}
