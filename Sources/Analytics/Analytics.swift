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
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String else {
            return nil
        }
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

        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        isEnabled = true
    }

    /// Sends a signal if analytics are enabled; a no-op otherwise.
    static func signal(_ name: String, parameters: [String: String] = [:]) {
        guard isEnabled else { return }
        TelemetryDeck.signal(name, parameters: parameters)
    }
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

    /// A completed activity record was logged (created), of any kind — e.g. a diaper change,
    /// feeding, note, or measurement. Fires for manual entries, "repeat", and timer
    /// conversions alike (a converted timer also emits `Timer.stopped`).
    static func activityLogged(kind: String) {
        signal("Activity.logged", parameters: ["kind": kind])
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

    /// A network/connectivity error with a short, non-identifying reason.
    static func error(network reason: String) {
        signal("Error.network", parameters: ["reason": reason])
    }

    // MARK: In-app purchases & premium
    //
    // Purchase/premium funnel. Like every event here these carry only coarse, non-identifying
    // values — a feature key or an error code — never customer, receipt, or price data.

    /// The upgrade paywall was shown.
    static func paywallViewed() {
        signal("Paywall.viewed")
    }

    /// An "Upgrade" call-to-action was tapped (which opens the paywall).
    static func upgradePressed() {
        signal("Paywall.upgradePressed")
    }

    /// A purchase flow began (the StoreKit sheet was requested).
    static func purchaseStarted() {
        signal("Purchase.started")
    }

    /// A purchase completed successfully.
    static func purchaseCompleted() {
        signal("Purchase.completed")
    }

    /// A purchase failed. `reason` is a coarse code (e.g. a RevenueCat error code), never a message.
    static func purchaseFailed(reason: String) {
        signal("Purchase.failed", parameters: ["reason": reason])
    }

    /// The customer cancelled the StoreKit purchase sheet — the expected "started but didn't buy"
    /// terminal, distinct from ``purchaseFailed(reason:)``. Lets the funnel measure sheet abandonment.
    static func purchaseCancelled() {
        signal("Purchase.cancelled")
    }

    /// The outcome of a "Restore Purchases" attempt.
    enum RestoreResult: String {
        /// Restore found an entitlement and premium is now active.
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

    /// The premium entitlement transitioned to active (via a purchase or restore).
    static func premiumActivated() {
        signal("Premium.activated")
    }

    /// The free-trial offer modal was shown in its offerable state (trial not yet started). The
    /// denominator for trial-offer conversion against ``trialStarted()``.
    static func trialOfferViewed() {
        signal("Trial.offerViewed")
    }

    /// The customer explicitly declined the trial offer (e.g. tapped "Not Now") — distinct from
    /// silently abandoning the modal.
    static func trialDeclined() {
        signal("Trial.declined")
    }

    /// The local free trial was started by an explicit user action.
    static func trialStarted() {
        signal("Trial.started")
    }

    /// The local free trial elapsed (reported once, when first observed as expired).
    static func trialEnded() {
        signal("Trial.ended")
    }

    /// A locked premium feature's lock/paywall was viewed. `feature` is the coarse feature key
    /// (a ``PremiumFeature`` raw value) — the "Feature Name" — never any user data.
    static func lockedFeatureViewed(feature: String) {
        signal("Feature.locked", parameters: ["feature": feature])
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
