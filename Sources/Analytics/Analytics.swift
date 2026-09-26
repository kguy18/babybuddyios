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
    /// demo mode or a UI test. Safe to call once at launch; a no-op otherwise.
    static func start() {
        guard !isEnabled else { return }
        // Demo mode runs offline with seeded data, and UI tests (`BB_UITEST`) drive the app from a
        // script — never report either.
        let environment = ProcessInfo.processInfo.environment
        guard environment["BB_DEMO"] != "1", environment["BB_UITEST"] != "1" else { return }
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

    /// Test seam: forgets which endpoints have already been reported missing. The dedupe in
    /// ``serverEndpointMissing(_:)`` is per *launch*, which in a test host means per whole suite —
    /// so without this a sync test that trips it would silently change what a later analytics test
    /// sees.
    static func resetEndpointMissingDedupe() { reportedMissingEndpoints = [] }
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

    /// A successful first sign-in, how the credentials were supplied, and how many custom headers
    /// it sent. The count only: header names and values never leave the device.
    static func onboardingCompleted(method: SignInMethod, customHeaders: Int) {
        signal("Onboarding.completed", parameters: ["method": method.rawValue,
                                                    "customHeaders": String(customHeaders)])
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
        /// The editor opened from sick mode: the sick card's "Log temperature", or a medicine
        /// card's button for the next dose.
        case sickMode
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

    // MARK: Sick mode
    //
    // How sick mode is used: which way people turn it on, whether the fever banner and the end
    // prompt work, and which way it ends. Like everything here the signals describe the feature,
    // never the child: no readings, doses, medicine names, or how long sick mode stayed on.

    /// Which way sick mode was turned on.
    enum SickModeStart: String, CaseIterable {
        /// "Start sick mode" on the Home banner that follows a reading over the fever line.
        case banner
        /// The "Start sick mode" row under "+" ▸ More….
        case addSheet
        /// Start in Settings ▸ Sick mode.
        case settings
    }

    /// Which way sick mode was turned off.
    enum SickModeEnd: String, CaseIterable {
        /// "End sick mode" on the prompt that follows a day with no fever and no dose.
        case endPrompt
        /// The "End sick mode" button at the bottom of the sick Home.
        case home
        /// End in Settings ▸ Sick mode.
        case settings
    }

    /// Sick mode was turned on. Undoing an end isn't a start; it sends ``sickModeEndUndone()``.
    static func sickModeStarted(source: SickModeStart) {
        signal("SickMode.started", parameters: ["source": source.rawValue])
    }

    /// The fever banner reached Home, counted once per reading. Against `SickMode.started` with
    /// `source: banner`, it says how often the banner is taken up.
    static func sickModeBannerShown() {
        signal("SickMode.bannerShown")
    }

    /// The banner was closed, or "Not now" tapped: turned down for that reading.
    static func sickModeBannerDismissed() {
        signal("SickMode.bannerDismissed")
    }

    /// The end prompt reached Home, counted once each time it appears rather than per redraw.
    static func sickModeEndPromptShown() {
        signal("SickMode.endPromptShown")
    }

    /// "Keep it on" on the end prompt. Many of these against `SickMode.ended` with
    /// `source: endPrompt` would mean the prompt asks too early.
    static func sickModeKeptOn() {
        signal("SickMode.keptOn")
    }

    /// Sick mode was turned off.
    static func sickModeEnded(source: SickModeEnd) {
        signal("SickMode.ended", parameters: ["source": source.rawValue])
    }

    /// Undo on the "Sick mode ended" toast: an end that was probably a mistake.
    static func sickModeEndUndone() {
        signal("SickMode.endUndone")
    }

    /// Whether the temperature card had a spell to draw, which decides where the card belongs.
    enum TemperatureChart: String {
        /// Readings in the window, so the fever chart is on the card.
        case drawn
        /// None, so the card reads "No temperatures logged".
        case empty
    }

    /// The Trends tab was opened, or its window changed. `period` is the rolling window in days
    /// ("7" / "14" / "30"), and `temperature` whether the fever chart had anything to draw over it.
    /// Neither says anything about the readings themselves, only whether any fell in the window.
    static func insightsViewed(periodDays: Int, temperature: TemperatureChart) {
        signal("Insights.viewed",
               parameters: ["period": String(periodDays), "temperature": temperature.rawValue])
    }

    /// A widget/App Intent was performed (e.g. from a Home Screen widget button or Siri).
    static func widgetIntent(_ intent: String) {
        signal("Widget.intentInvoked", parameters: ["intent": intent])
    }

    /// A sync finished successfully (queue drained + pull merged).
    static func syncCompleted() {
        signal("Sync.completed")
    }

    /// How a sync ended, as a closed vocabulary. ``syncCompleted()`` says only that something
    /// moved, which a permanently parked queue row can coexist with on every sync forever — these
    /// four tell those cases apart.
    enum SyncOutcome: String {
        /// Everything queued went out; nothing is left waiting.
        case drained
        /// Rows are parked (see ``QueueDisposition``) and will not be retried without the user.
        case partialBlocked
        /// A queue stopped early on a retryable failure (offline / 5xx); the rest was untried.
        case transientFailure
        /// No blocked rows, but work is still queued and eligible — an image whose record isn't
        /// synced yet, or a create the widget extension had claimed.
        case changedWithPendingWork
    }

    /// The outcome of one sync run, alongside the unchanged ``syncCompleted()``.
    ///
    /// Emitted once per sync that did work or found work waiting; a pure no-op sync stays silent,
    /// like `Sync.completed`. Everything here is a closed category or a count of queue rows —
    /// never a record kind list, an identifier, or anything from a payload or response.
    ///
    /// `blockedNew` counts rows this sync *parked* (the same transition ``report(_:context:attempt:)``
    /// fires on); `blockedTotal` is the standing backlog afterwards, and `queued` the rows still
    /// eligible for a later automatic attempt.
    static func syncFinished(outcome: SyncOutcome, delivered: Int, uploaded: Int,
                             blockedNew: Int, blockedTotal: Int, queued: Int) {
        signal("Sync.finished", parameters: [
            "outcome": outcome.rawValue,
            "delivered": String(delivered),
            "uploaded": String(uploaded),
            "blockedNew": String(blockedNew),
            "blockedTotal": String(blockedTotal),
            "queued": String(queued),
        ])
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

    /// Endpoints already reported missing this launch — see ``serverEndpointMissing(_:)``.
    private static var reportedMissingEndpoints: Set<String> = []

    /// An endpoint this server version doesn't have. Baby Buddy grew `pumping`, `tags` and others
    /// over its releases, and a self-hosted server is whatever version its owner last pulled — so
    /// which endpoints are missing in the field is the closest thing we have to a version census,
    /// and it explains the `notFound` rejections a push of that same kind produces.
    ///
    /// Reported once per launch per endpoint: a missing endpoint is a fact about the server, not
    /// about this sync, and every sync would otherwise re-report it forever.
    static func serverEndpointMissing(_ endpoint: String) {
        guard reportedMissingEndpoints.insert(endpoint).inserted else { return }
        signal("Server.endpointMissing", parameters: ["endpoint": endpoint])
    }

    /// A named setting was switched on or off. Carries the setting's name and the new boolean only
    /// — never the value of anything the setting controls.
    static func settingChanged(_ setting: String, enabled: Bool) {
        signal("Settings.changed", parameters: ["setting": setting, "enabled": String(enabled)])
    }

    /// The home-screen icon was switched. Carries the chosen design's stable name (an
    /// ``AppIconOption`` raw value) — which of six shipped artworks someone prefers, and nothing
    /// about them. Worth its own signal rather than a ``settingChanged(_:enabled:)`` boolean, since
    /// the interesting question is *which* icon wins, not that the screen was used.
    static func appIconChanged(_ icon: String) {
        signal("Settings.appIconChanged", parameters: ["icon": icon])
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
    enum SupporterSource: String, CaseIterable {
        /// Settings ▸ Baby Buddy App Supporter.
        case settings
        /// The `babybuddy://supporter` deep link.
        case deeplink
        /// "Support development" on the What's New card — wherever that card was opened from.
        /// `WhatsNew.supporterTapped` splits launch from Settings on the card's own side, so this
        /// stays one source: the question it answers is which *surface* earned the tip.
        case whatsNew
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

    // MARK: What's New
    //
    // The release card (see ``WhatsNewView``). Four signals covering the whole of it: it appeared,
    // and then exactly one of the three ways out. Nothing about the release's contents is carried —
    // the version is already a TelemetryDeck default parameter on every signal, so repeating it
    // here would only double it up.
    //
    // As with the nudges there is no "converted" signal: tapping through to the tip sheet shows up
    // as a `Supporter.sheetViewed` / `Tip.*` carrying the matching ``SupporterSource``.

    /// Where a What's New card was opened from.
    enum WhatsNewSource: String, CaseIterable {
        /// Shown automatically on the first launch after an update.
        case launch
        /// Opened on purpose from Settings.
        case settings
    }

    /// The card reached the screen.
    static func whatsNewShown(source: WhatsNewSource) {
        signal("WhatsNew.shown", parameters: ["source": source.rawValue])
    }

    /// Continue (or Done, from Settings) was tapped — the card was read and closed.
    static func whatsNewContinued(source: WhatsNewSource) {
        signal("WhatsNew.continued", parameters: ["source": source.rawValue])
    }

    /// "Support development" was tapped. Whether that became a tip is answered by the
    /// ``SupporterSource`` on the sheet's own signals, not here.
    static func whatsNewSupporterTapped(source: WhatsNewSource) {
        signal("WhatsNew.supporterTapped", parameters: ["source": source.rawValue])
    }

    /// The card was closed without tapping Continue — swiped away from the Settings sheet. The
    /// launch card is a full-screen cover with no swipe, so this is rare there by construction.
    static func whatsNewDismissed(source: WhatsNewSource) {
        signal("WhatsNew.dismissed", parameters: ["source": source.rawValue])
    }

    /// Why ``APIClient/splitPage(_:allowsUnpaginatedArray:)`` couldn't read a list body, as a closed
    /// vocabulary of category names. Only rejected shapes are listed — the two it accepts are not
    /// reported, because a sync that works is not an error.
    ///
    /// A `decoding` failure on a list pull says only that the body wasn't understood, which isn't
    /// enough to tell an older server shape worth supporting from a proxy page that isn't the API
    /// at all. These names carry that distinction and nothing else — never the body, the URL, the
    /// server, or any record's contents. `report` accepts a shape only by round-tripping it back
    /// through this enum, so an arbitrary decoder message can never be reported as one.
    enum ListShape: String {
        /// A JSON object with no `results` array — an error envelope, or a shape we don't know.
        case objectMissingResults
        /// The body isn't JSON at all — an HTML login or proxy page is the usual cause.
        case nonJSON
        /// Valid JSON of a type that can't be a list of records: a scalar, an array where one
        /// isn't accepted, or a list with a non-object row.
        case unexpectedJSONType
    }

    /// Coarse error reporting from API failures — category + a short, non-identifying reason.
    /// Never carries the server's message text (which could include user data).
    ///
    /// `context` is *where* it happened (`push-create-pumping`, `upload-note`) and `attempt` how
    /// many times that same queued item has already failed. Both exist because one un-deliverable
    /// record otherwise looks like a flood of unrelated rejections. A terminal failure now blocks
    /// the queue row (see ``QueueDisposition``) and is reported once, on that transition, rather
    /// than on every sync — so a climbing `attempt` means real repeated failures, not a spin. For
    /// a validation error `fields` names the keys the server complained about — never their values;
    /// for a list decode failure `shape` names the top-level response shape, from the closed
    /// ``ListShape`` vocabulary.
    static func report(_ error: APIError, context: String? = nil, attempt: Int? = nil) {
        var parameters: [String: String] = [:]
        if let context { parameters["context"] = context }
        if let attempt { parameters["attempt"] = String(attempt) }

        let name: String
        switch error {
        case .offline(let transport):
            name = "Error.network"; parameters["reason"] = transport.rawValue
        case .server(let status):
            name = "Error.network"; parameters["reason"] = "server-\(status)"
        case .unauthorized:
            name = "Error.serverRejected"; parameters["reason"] = "unauthorized"
        case .forbidden:
            name = "Error.serverRejected"; parameters["reason"] = "forbidden"
        case .notFound:
            name = "Error.serverRejected"; parameters["reason"] = "notFound"
        case .conflict:
            name = "Error.serverRejected"; parameters["reason"] = "conflict"
        case .badRequest(let status, _, let fields):
            name = "Error.serverRejected"; parameters["reason"] = "badRequest-\(status)"
            if !fields.isEmpty { parameters["fields"] = fields.joined(separator: ",") }
        case .decoding(let detail):
            name = "Error.serverRejected"; parameters["reason"] = "decoding"
            // `detail` is free text for most decode failures (a `DecodingError` description, which
            // can quote decoded values), so it is reported only when it is exactly one of the
            // closed ``ListShape`` names. Anything else is dropped rather than sent.
            if let shape = ListShape(rawValue: detail) { parameters["shape"] = shape.rawValue }
        case .invalidURL:
            name = "Error.serverRejected"; parameters["reason"] = "invalidURL"
        case .accessGate(let gate):
            name = "Error.serverRejected"; parameters["reason"] = "accessGate"; parameters["gate"] = gate.rawValue
        }
        signal(name, parameters: parameters)
    }
}
