import Foundation
import TelemetryDeck

/// Thin wrapper around the TelemetryDeck SDK.
///
/// Analytics only run when a TelemetryDeck App ID is configured. The ID is
/// injected at build time from `Config/Secrets.xcconfig` (gitignored) into the
/// `TelemetryDeckAppID` Info.plist key. The public repository ships without an
/// App ID, so open-source and forked builds send no data. The App Store build
/// supplies the ID locally / via CI.
enum Analytics {
    /// The App ID injected into Info.plist, or `nil` if none was configured.
    private static var appID: String? {
        infoValue(forKey: "TelemetryDeckAppID")
    }

    /// Optional hashing salt injected into Info.plist, or `nil` if none was configured. When present
    /// it salts the anonymous per-device user hash so it can't be reversed from a device identifier.
    private static var salt: String? {
        infoValue(forKey: "TelemetryDeckSalt")
    }

    /// A non-empty, trimmed Info.plist string value, or `nil`.
    private static func infoValue(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `true` once `start()` has initialized the SDK.
    private(set) static var isEnabled = false

    /// Initializes TelemetryDeck if an App ID is configured and we're not in
    /// demo mode. Safe to call once at launch; a no-op otherwise.
    static func start() {
        guard !isEnabled else { return }
        // Demo mode runs offline with seeded data — never report it.
        guard ProcessInfo.processInfo.environment["BB_DEMO"] != "1" else { return }
        guard let appID else { return }

        let config = TelemetryDeck.Config(appID: appID, salt: salt)
        TelemetryDeck.initialize(config: config)
        isEnabled = true
    }

    /// TelemetryDeck identity for correlating RevenueCat's server-side webhook events with our
    /// signals: the App ID plus the anonymous, salted per-device user hash TelemetryDeck stamps on
    /// every signal. `nil` unless analytics are enabled. The hash matches the signal `clientUser`
    /// because we never set a custom default user (iOS defaults it to `identifierForVendor`).
    /// See ``PurchaseManager`` for where these are handed to RevenueCat.
    @MainActor
    static var telemetryDeckIdentity: (appID: String, hashedUser: String)? {
        guard isEnabled, let appID else { return nil }
        return (appID, TelemetryManager.shared.hashedDefaultUser)
    }

    /// Sends a signal if analytics are enabled; a no-op otherwise.
    static func signal(_ name: String, parameters: [String: String] = [:]) {
        #if DEBUG
        if let recorder { recorder(name, parameters); return }
        #endif
        guard isEnabled else { return }
        TelemetryDeck.signal(name, parameters: parameters)
    }

    #if DEBUG
    /// Test seam: while set, signals are handed here instead of TelemetryDeck — regardless of
    /// whether analytics are configured, so a test host with no App ID still sees them.
    ///
    /// This is how the typed helpers below are covered: the funnel's whole value rests on the right
    /// dimensions reaching the right signal (a tip attributed to the wrong entry point is worse than
    /// no attribution), and the flows that emit them run through `Purchases.shared` and can't be
    /// exercised without live StoreKit. Compiled out of release entirely.
    static var recorder: ((_ name: String, _ parameters: [String: String]) -> Void)?
    #endif
}

// MARK: - Events
//
// Typed signal helpers so the analytics vocabulary lives in one place. Each is a
// no-op unless analytics are enabled (see `signal`). Parameters carry only coarse,
// non-identifying enums — never user, child, or tracking data.
extension Analytics {
    enum AuthResult: String { case success, failure }

    /// An app-lock unlock attempt, plus which biometry the device offers, so we can
    /// see whether Face ID / Touch ID is actually being used.
    static func appLockUnlock(result: AuthResult, biometry: String) {
        signal("AppLock.unlocked", parameters: ["result": result.rawValue, "biometry": biometry])
    }

    enum SearchActivity: String {
        case started, completed
        case noResults = "no-results"
    }

    /// Timeline search usage: `started` when a query begins, then `completed` or
    /// `no-results` once typing settles.
    static func search(_ activity: SearchActivity) {
        signal("Search", parameters: ["activity": activity.rawValue])
    }

    enum SignInMethod: String { case qr, manual }

    /// A successful first sign-in, and how the credentials were supplied.
    static func onboardingCompleted(method: SignInMethod) {
        signal("Onboarding.completed", parameters: ["method": method.rawValue])
    }

    /// Where a timer action originated.
    enum TimerSource: String { case app, widget }

    /// A timer was started. `activity` is feeding/sleep/tummyTime/pumping, or "other" for an
    /// uncategorized custom timer.
    static func timerStarted(activity: String, source: TimerSource) {
        signal("Timer.started", parameters: ["activity": activity, "source": source.rawValue])
    }

    /// A running timer was stopped and logged as a completed activity.
    static func timerStopped(activity: String, source: TimerSource) {
        signal("Timer.stopped", parameters: ["activity": activity, "source": source.rawValue])
    }

    /// Which path created an activity record.
    enum ActivitySource: String {
        /// The add/edit sheet — someone filled in a form and saved it.
        case editor
        /// "Repeat" on an existing record in the timeline.
        case `repeat`
        /// A running timer being stopped and logged, from anywhere (dashboard, editor, widget).
        case timerStop
        /// An App Intent — a Quick Log widget tile or Siri.
        case intent
    }

    /// A completed activity record was logged (created), of any kind — e.g. a diaper change,
    /// feeding, note, or measurement. Fires for manual entries, "repeat", and timer
    /// conversions alike (a converted timer also emits `Timer.stopped`).
    ///
    /// `source` is which path created it, so the split between typing a record out, repeating one,
    /// stopping a timer, and tapping a widget is visible — the four are very different amounts of
    /// work for the same result. Coarse and closed: never what was logged, only how.
    static func activityLogged(kind: String, source: ActivitySource) {
        signal("Activity.logged", parameters: ["kind": kind, "source": source.rawValue])
    }

    /// The Trends tab was opened, or its window changed. `period` is the rolling window in days
    /// ("7" / "14" / "30") — the only thing the screen is parameterized by.
    static func insightsViewed(periodDays: Int) {
        signal("Insights.viewed", parameters: ["period": String(periodDays)])
    }

    /// A widget/App Intent was performed (e.g. from a Home Screen widget button or Siri).
    static func widgetIntent(_ intent: String) {
        signal("Widget.intentInvoked", parameters: ["intent": intent])
    }

    /// A sync finished successfully (queue drained + pull merged).
    static func syncCompleted() {
        signal("Sync.completed")
    }

    /// A push raised a conflict that needs user resolution.
    static func syncConflictRaised(kind: String, op: String) {
        signal("Sync.conflictRaised", parameters: ["kind": kind, "op": op])
    }

    /// How a conflict was settled.
    enum ConflictChoice: String {
        /// Keep the local version, overwriting the server.
        case mine
        /// Discard the local change and adopt the server's version.
        case server
        /// Keep a field-by-field merge of the two.
        case merge
    }

    /// A raised conflict was resolved, and how — the other half of ``syncConflictRaised(kind:op:)``.
    /// Together they show both how often conflicts happen and whether the resolution screen is
    /// understood (a merge is the considered choice; all-server suggests people are giving up).
    /// Carries the choice and the record kind only, never either version's contents.
    static func syncConflictResolved(choice: ConflictChoice, kind: String) {
        signal("Sync.conflictResolved", parameters: ["choice": choice.rawValue, "kind": kind])
    }

    /// A network/connectivity error with a short, non-identifying reason.
    static func error(network reason: String) {
        signal("Error.network", parameters: ["reason": reason])
    }

    /// A named setting was switched on or off. Carries the setting's name and the new boolean only
    /// — never the value of anything the setting controls.
    static func settingChanged(_ setting: String, enabled: Bool) {
        signal("Settings.changed", parameters: ["setting": setting, "enabled": String(enabled)])
    }

    // MARK: In-app purchases & supporter status
    //
    // Tip funnel. Every feature is free; these track the optional supporter tips. Like every event
    // here they carry only coarse, non-identifying values — a tip tier or an error code — never
    // customer, receipt, or price data.

    /// Which door someone came through to reach the supporter sheet.
    ///
    /// Threaded through every signal from there on, so a tip is attributable to the entry point that
    /// produced it from a single signal. TelemetryDeck is signal-based, so this is deliberately a
    /// parameter on the existing events rather than a separate "converted" signal to join against.
    enum SupporterSource: String {
        /// Settings ▸ Baby Buddy App Supporter.
        case settings
        /// The `babybuddy://supporter` deep link.
        case deeplink
        /// The one-time gentle ask (nudge variant A).
        case nudgeGentle
        /// A milestone celebration (nudge variant B).
        case nudgeMilestone
        /// The quiet inline Dashboard banner (nudge variant D).
        case nudgeBanner
    }

    /// What the supporter sheet actually had to show when it opened.
    ///
    /// The point of recording it is the two `unavailable` cases. ``PurchaseManager/refresh()``
    /// swallows a failed offering fetch deliberately (nobody asked for that work, and the sheet
    /// already says so in plain language) — which means a shipped build whose sheet has nothing to
    /// sell looks, in the funnel, exactly like one nobody chose to tip from. This tells them apart.
    enum SupporterSheetState: String {
        /// The amounts are on screen — the ask, as intended.
        case ask
        /// The thank-you: this customer has already tipped.
        case thankYou
        /// Configured to sell, but the offering yielded no tips — a failed fetch, or a dashboard
        /// offering carrying no products. The one to alert on.
        case unavailableNoTips
        /// No RevenueCat key in this build (open source, a fork, or demo mode). Expected, and
        /// unreachable in the App Store build.
        case unavailableUnconfigured
    }

    /// The supporter sheet was shown: which entry point opened it, what it had to offer, and the
    /// identifier of the offering serving it (absent when none has loaded).
    ///
    /// `offering` is the RevenueCat offering's own name — a dashboard-side label, not customer data
    /// — so funnels can be sliced by it once Experiments serves variant offerings.
    static func supporterSheetViewed(source: SupporterSource,
                                     state: SupporterSheetState,
                                     offering: String? = nil) {
        var parameters = ["source": source.rawValue, "state": state.rawValue]
        if let offering { parameters["offering"] = offering }
        signal("Supporter.sheetViewed", parameters: parameters)
    }

    /// A supporter reopened the amounts from the thank-you state ("Tip again"). Distinct from
    /// ``supporterSheetViewed(source:state:offering:)``, which fires for merely arriving: this is
    /// someone who has already paid choosing to look at the amounts a second time.
    static func supporterTipAgainPressed() {
        signal("Supporter.tipAgainPressed")
    }

    /// A tip purchase began (the StoreKit sheet was requested). `tier` is the coarse tip size
    /// ("small" / "medium" / "large"), or "unknown" for a package that matches no tier; `source` is
    /// the entry point that led here.
    static func tipPurchaseStarted(tier: String, source: SupporterSource) {
        signal("Tip.purchaseStarted", parameters: ["tier": tier, "source": source.rawValue])
    }

    /// A tip purchase completed successfully. Tips are consumable and repeatable, so this can fire
    /// more than once for the same customer. `offering` is the serving offering's identifier, so a
    /// conversion is attributable to the offering (and so the Experiments variant) that produced it.
    ///
    /// Deliberately no amount: revenue reaches TelemetryDeck server-side through RevenueCat's
    /// integration, and the tier band is the only purchase dimension the client reports.
    static func tipPurchased(tier: String, source: SupporterSource, offering: String? = nil) {
        var parameters = ["tier": tier, "source": source.rawValue]
        if let offering { parameters["offering"] = offering }
        signal("Tip.purchased", parameters: parameters)
    }

    /// A tip purchase failed. `reason` is a coarse code (e.g. a RevenueCat error code), never a
    /// message.
    static func purchaseFailed(reason: String, source: SupporterSource) {
        signal("Purchase.failed", parameters: ["reason": reason, "source": source.rawValue])
    }

    /// The customer cancelled the StoreKit purchase sheet — the expected "started but didn't buy"
    /// terminal, distinct from ``purchaseFailed(reason:source:)``. Lets the funnel measure sheet
    /// abandonment per entry point.
    static func purchaseCancelled(source: SupporterSource) {
        signal("Purchase.cancelled", parameters: ["source": source.rawValue])
    }

    /// The outcome of a "Restore Purchases" attempt.
    enum RestoreResult: String {
        /// Restore found a past purchase and supporter status is now active.
        case activated
        /// Restore succeeded but found nothing to restore (a common support case).
        case nothing
        /// Restore errored.
        case failed
    }

    /// A "Restore Purchases" attempt finished. `result` distinguishes activated / nothing-found /
    /// errored so restore-found-nothing is visible rather than looking like a silent success.
    static func restorePurchases(result: RestoreResult) {
        signal("Purchase.restored", parameters: ["result": result.rawValue])
    }

    /// Supporter status transitioned to active (via a tip or a restore).
    static func supporterActivated() {
        signal("Supporter.activated")
    }

    // MARK: Support nudges
    //
    // The respectful ask (see ``SupportNudgeManager``). There is deliberately no "converted" signal:
    // a nudge that leads to a tip shows up as a `Supporter.sheetViewed` / `Tip.*` carrying the
    // matching ``SupporterSource``, so conversion is a single-signal query per entry point.

    /// Which support-nudge surface an event is about.
    enum NudgeVariant: String {
        /// Variant A — the one-time centered gentle ask.
        case gentle
        /// Variant B — a milestone celebration.
        case milestone
        /// Variant D — the quiet inline Dashboard banner.
        case banner
    }

    /// A support nudge reached the screen. `milestone` carries the round entry-count threshold that
    /// triggered a ``NudgeVariant/milestone`` nudge (50 / 100 / 250 / 500 / 1000) and is absent for
    /// the other variants — never what was logged, only how many.
    static func nudgeShown(variant: NudgeVariant, milestone: Int? = nil) {
        var parameters = ["variant": variant.rawValue]
        if let milestone { parameters["milestone"] = String(milestone) }
        signal("Nudge.shown", parameters: parameters)
    }

    /// A support nudge was explicitly turned down. `dismissCount` is the running tally afterward —
    /// the thing that eventually retires the popups — so the drop-off is visible per step.
    static func nudgeDismissed(variant: NudgeVariant, dismissCount: Int) {
        signal("Nudge.dismissed",
               parameters: ["variant": variant.rawValue, "dismissCount": String(dismissCount)])
    }

    /// The popups retired permanently: enough dismissals that only the quiet banner remains. Fires
    /// once, on the dismissal that crosses the line.
    static func nudgeRetired() {
        signal("Nudge.retired")
    }

    /// Coarse error reporting from API failures — category + a short, non-identifying reason.
    /// Never carries the server's message text (which could include user data).
    static func report(_ error: APIError) {
        switch error {
        case .offline:
            signal("Error.network", parameters: ["reason": "offline"])
        case .server(let status):
            signal("Error.network", parameters: ["reason": "server-\(status)"])
        case .unauthorized:
            signal("Error.serverRejected", parameters: ["reason": "unauthorized"])
        case .forbidden:
            signal("Error.serverRejected", parameters: ["reason": "forbidden"])
        case .notFound:
            signal("Error.serverRejected", parameters: ["reason": "notFound"])
        case .conflict:
            signal("Error.serverRejected", parameters: ["reason": "conflict"])
        case .badRequest(let status, _):
            signal("Error.serverRejected", parameters: ["reason": "badRequest-\(status)"])
        case .decoding:
            signal("Error.serverRejected", parameters: ["reason": "decoding"])
        case .invalidURL:
            signal("Error.serverRejected", parameters: ["reason": "invalidURL"])
        }
    }
}
