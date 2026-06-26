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
