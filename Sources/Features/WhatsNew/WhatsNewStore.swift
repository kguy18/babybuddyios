import Foundation

/// Decides whether the What's New screen is due, and remembers that it has been shown.
///
/// The policy is a pure function so it can be tested against any install history without waiting
/// for a release, in the same shape as ``SupportNudgeManager``'s.
enum WhatsNewStore {
    /// The marketing version whose notes this device has already seen. App-only: the widget has no
    /// use for it, so it lives in `UserDefaults.standard` rather than the App Group suite.
    static let lastSeenVersionKey = "whatsNewLastSeenVersion"

    /// Whether to present `release` now.
    ///
    /// Three rules, and the middle one is the one that matters:
    ///
    /// - The notes must describe the version actually running. Copy for an unreleased version is
    ///   dormant, not early — which is why bumping `MARKETING_VERSION` is what lights this screen
    ///   up at release time.
    /// - **A fresh install never sees it.** Someone opening the app for the first time has no "new"
    ///   to be shown; `lastSeen == nil` stamps the current version silently instead. This is also
    ///   what keeps the sheet out of the way of every other UI test's first launch.
    /// - Otherwise, show it once per version.
    static func shouldShow(release: WhatsNewRelease, currentVersion: String, lastSeen: String?) -> Bool {
        guard release.version == currentVersion else { return false }
        guard let lastSeen else { return false }
        return lastSeen != currentVersion
    }

    /// The release to present right now, or `nil`. Stamps `currentVersion` as seen either way, so a
    /// fresh install is silently brought up to date and the screen appears on the *next* upgrade.
    ///
    /// `forced` is the `BB_WHATS_NEW=1` debug hook: it bypasses both the version match and the
    /// fresh-install rule so the screen can be driven in UI tests and looked at in demo mode, where
    /// the shipped copy describes a version the debug build isn't.
    static func pending(release: WhatsNewRelease?,
                        currentVersion: String,
                        defaults: UserDefaults = .standard,
                        forced: Bool = WhatsNewStore.isForced) -> WhatsNewRelease? {
        guard let release else { return nil }
        let lastSeen = defaults.string(forKey: lastSeenVersionKey)
        defer { defaults.set(currentVersion, forKey: lastSeenVersionKey) }
        guard forced || shouldShow(release: release, currentVersion: currentVersion, lastSeen: lastSeen)
        else { return nil }
        return release
    }

    /// The app's marketing version — the `1.1.0` the notes are matched against.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Whether the What's New screen has been shown since launch.
    ///
    /// Read by the Dashboard before it puts a support nudge up: the What's New sheet carries a
    /// "Support development" button of its own, and two asks in one launch is one too many. The
    /// nudge is held back rather than consumed, so it is still due on the next launch.
    @MainActor
    static var shownThisLaunch = false

    /// `BB_WHATS_NEW=1` — see `Docs/DEVELOPMENT.md`. DEBUG-only, like every other launch hook.
    static var isForced: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["BB_WHATS_NEW"] == "1"
        #else
        return false
        #endif
    }
}
