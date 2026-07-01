import Foundation
import PostHog

/// Thin wrapper around the PostHog SDK.
///
/// Analytics only run when a PostHog project API key is configured. The key is
/// injected at build time from `Config/Secrets.xcconfig` (gitignored) into the
/// `PostHogAPIKey` Info.plist key. The public repository ships without a key, so
/// open-source and forked builds send no data. The App Store build supplies the
/// key locally / via CI.
///
/// It's configured to stay lean and privacy-respecting: screen autocapture and
/// session replay are off, we never call `identify(...)`, so events are attributed
/// only to an anonymous, device-scoped identifier — no personal or baby data.
enum Analytics {
    /// The PostHog project API key from Info.plist, or `nil` if none was configured.
    private static var apiKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The PostHog ingestion host. Defaults to US Cloud; set `PostHogHost` in Info.plist
    /// (via `project.yml`) for the EU region or a self-hosted instance.
    private static var host: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "PostHogHost") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false ? value : nil) ?? "https://us.i.posthog.com"
    }

    /// `true` once `start()` has initialized the SDK.
    private(set) static var isEnabled = false

    /// Initializes PostHog if an API key is configured and we're not in demo mode.
    /// Safe to call once at launch; a no-op otherwise.
    static func start() {
        guard !isEnabled else { return }
        // Demo mode runs offline with seeded data — never report it.
        guard ProcessInfo.processInfo.environment["BB_DEMO"] != "1" else { return }
        guard let apiKey else { return }

        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureScreenViews = false               // no UIKit screen autocapture
        config.sessionReplay = false                    // never record the screen
        config.preloadFeatureFlags = false              // we don't use feature flags
        config.captureApplicationLifecycleEvents = true // app opened / installed / updated
        PostHogSDK.shared.setup(config)
        isEnabled = true
    }

    /// Sends an event if analytics are enabled; a no-op otherwise.
    static func signal(_ name: String, parameters: [String: String] = [:]) {
        guard isEnabled else { return }
        PostHogSDK.shared.capture(name, properties: parameters)
    }

    /// Flush queued events immediately. PostHog batches by default, so short-lived
    /// widget/App Intent processes call this after signaling to push before suspension.
    static func flush() {
        guard isEnabled else { return }
        PostHogSDK.shared.flush()
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
