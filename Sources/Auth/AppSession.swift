import Foundation
import Observation
import SwiftData
import WidgetKit

/// App-wide authentication state. Owns the active ``ServerConfig`` and the ``APIClient``
/// built from it. Persists credentials in the Keychain.
@MainActor
@Observable
final class AppSession {
    enum State: Equatable {
        case unauthenticated
        case authenticated(ServerConfig)
    }

    private(set) var state: State
    private(set) var client: APIClient?

    /// Set when a request fails validation during onboarding, for inline display.
    var lastError: String?

    /// When true (DEBUG launch with `BB_DEMO=1`), the app runs against seeded local data
    /// and skips all network access.
    let isDemo: Bool

    /// Main-actor handle on the local cache, so leaving a server can clear it. `nil` in tests,
    /// which construct a session without a store.
    private let context: ModelContext?

    /// Which server the cache currently belongs to (see ``serverKey(for:)``). Deliberately in
    /// `UserDefaults` rather than the Keychain: it has to outlive ``signOut``, which clears the
    /// credentials, so a later sign-in can still tell "same server" from "different server".
    private static let cachedServerKey = "cachedServerURL"

    init(context: ModelContext? = nil) {
        self.context = context
        #if DEBUG
        isDemo = ProcessInfo.processInfo.environment["BB_DEMO"] == "1"
        #else
        isDemo = false
        #endif
        if isDemo {
            state = .authenticated(ServerConfig(baseURL: URL(string: "https://demo.local")!, token: "demo"))
            return
        }
        if let config = KeychainStore.load() {
            state = .authenticated(config)
            client = APIClient(config: config)
        } else {
            state = .unauthenticated
        }
    }

    var isAuthenticated: Bool {
        if case .authenticated = state { return true }
        return false
    }

    /// The active server connection, if authenticated.
    var config: ServerConfig? {
        if case .authenticated(let config) = state { return config }
        return nil
    }

    /// Identity of a server for cache-ownership purposes: the normalized URL, lowercased and
    /// without a trailing slash, so `https://Baby.example.com/` and `https://baby.example.com`
    /// are the same server and don't trigger a needless wipe of unsynced work.
    static func serverKey(for url: URL) -> String {
        var key = url.absoluteString.lowercased()
        while key.hasSuffix("/") { key.removeLast() }
        return key
    }

    /// Normalize a user- or QR-supplied server address into an `https` URL string.
    ///
    /// Plain `http://` is upgraded to `https://`: iOS App Transport Security blocks cleartext,
    /// so HTTP can never connect anyway, and Baby Buddy servers behind a TLS-terminating proxy
    /// emit `http://` in their `/user/add-device/` QR even though they're only reachable over
    /// https (Django sees the proxied request as http). A bare host gets an `https://` prefix.
    static func normalizedServerURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("https://") { return trimmed }
        if lower.hasPrefix("http://") { return "https://" + trimmed.dropFirst("http://".count) }
        return "https://" + trimmed
    }

    /// Validate a URL + token against the server and, on success, persist and activate it.
    func signIn(serverURL: String, token: String) async -> Bool {
        lastError = nil
        let normalized = Self.normalizedServerURLString(serverURL)
        guard let url = URL(string: normalized), url.host != nil else {
            lastError = "That doesn't look like a valid server address."
            return false
        }
        let config = ServerConfig(
            baseURL: url, token: token.trimmingCharacters(in: .whitespaces))
        let probe = APIClient(config: config)
        do {
            try await probe.validateToken()
            // A different server than the cache was pulled from: drop it before its records can
            // mix with the new server's. Covers the path where the token was rejected mid-sync
            // (which signs out without clearing) and the customer then moves to another server.
            let key = Self.serverKey(for: url)
            if UserDefaults.standard.string(forKey: Self.cachedServerKey) != key { clearLocalData() }
            UserDefaults.standard.set(key, forKey: Self.cachedServerKey)
            KeychainStore.save(config: config)
            state = .authenticated(config)
            client = probe
            return true
        } catch let error as APIError {
            lastError = error.userMessage
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Return to the signed-out state.
    ///
    /// - Parameter clearLocalData: whether to erase the cached records too. `true` for a
    ///   deliberate sign-out — the cache belongs to the server being left, and the next server
    ///   must not inherit it. `false` when the server rejects our token mid-sync: that customer
    ///   almost always signs back in to the *same* server, and anything still queued has to
    ///   survive that. Moving to a different server clears the cache at sign-in instead.
    func signOut(clearLocalData shouldClear: Bool = true) {
        KeychainStore.clear()
        client = nil
        state = .unauthenticated
        if shouldClear {
            UserDefaults.standard.removeObject(forKey: Self.cachedServerKey)
            clearLocalData()
        }
    }

    /// Erase the cached server data and refresh the widgets, which read the same store.
    private func clearLocalData() {
        guard let context else { return }
        LocalStore.wipe(in: context)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
