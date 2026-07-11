import Foundation

/// Typed errors surfaced by ``APIClient``. The sync engine and UI branch on these
/// to decide whether to retry, queue, raise a conflict, or prompt re-authentication.
enum APIError: Error, Equatable {
    /// No network / server unreachable. Safe to keep the mutation queued and retry later.
    case offline
    /// 401 — token rejected. Session should be invalidated and the user re-prompted.
    case unauthorized
    /// 403 — authenticated but not permitted.
    case forbidden
    /// 404 — the record no longer exists on the server (drives delete-vs-edit conflicts).
    case notFound
    /// 409 or a detected concurrent modification.
    case conflict
    /// Any 5xx. Transient; retry with backoff.
    case server(status: Int)
    /// 4xx other than the above (validation errors etc.). Carries the server's message if any.
    case badRequest(status: Int, message: String?)
    /// Response body could not be decoded into the expected type.
    case decoding(String)
    /// The configured server URL is invalid.
    case invalidURL

    var isRetryable: Bool {
        switch self {
        case .offline, .server: return true
        default: return false
        }
    }

    /// A server-side 5xx specifically (excludes `offline`). Used to skip a single failing kind
    /// during a bulk pull without aborting the whole sync, while still treating a lost
    /// connection as a hard stop.
    var isServer: Bool {
        if case .server = self { return true }
        return false
    }

    var userMessage: String {
        switch self {
        case .offline: return "No connection to the Baby Buddy server."
        case .unauthorized: return "Your API token was rejected. Please sign in again."
        case .forbidden: return "You don't have permission to do that."
        case .notFound: return "That record no longer exists on the server."
        case .conflict: return "This record was changed on the server."
        case .server(let status): return "Server error (\(status)). Please try again later."
        case .badRequest(_, let message): return message ?? "The server rejected the request."
        case .decoding(let detail): return "Couldn't read the server response. \(detail)"
        case .invalidURL: return "The server address is not valid."
        }
    }
}
