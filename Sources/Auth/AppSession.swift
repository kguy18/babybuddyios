import Foundation
import Observation

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

    init() {
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

    func signOut() {
        KeychainStore.clear()
        client = nil
        state = .unauthenticated
    }
}
