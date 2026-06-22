import Foundation

/// Parses the `BABYBUDDY-LOGIN:` QR payload produced by a Baby Buddy server's
/// User → Add a Device page (`/user/add-device/`). The QR encodes the server's absolute
/// root URL and the user's API key — everything this client needs to sign in — so scanning
/// it avoids manually copying the token and works for any self-hosted domain.
///
/// Payload shape (the `session_cookies` field is for Home Assistant ingress and is ignored):
/// `BABYBUDDY-LOGIN:{"url":"https://baby.example.com/","api_key":"<token>","session_cookies":{}}`
enum DeviceLoginQR {
    static let prefix = "BABYBUDDY-LOGIN:"

    struct Credentials: Equatable {
        var serverURL: String
        var token: String
    }

    private struct Payload: Decodable {
        let url: String
        let apiKey: String
        enum CodingKeys: String, CodingKey {
            case url
            case apiKey = "api_key"
        }
    }

    /// Returns the embedded server URL + token, or `nil` if `string` is not a recognizable
    /// Baby Buddy login payload.
    static func parse(_ string: String) -> Credentials? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let json = String(trimmed.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        let url = payload.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = payload.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !token.isEmpty else { return nil }
        return Credentials(serverURL: url, token: token)
    }
}
