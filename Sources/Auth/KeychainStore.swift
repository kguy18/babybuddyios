import Foundation
import Security

/// Minimal Keychain wrapper for the server URL + API token. The token is the only
/// secret; both are stored with `WhenUnlockedThisDeviceOnly` so they never sync or
/// leave the device.
///
/// Items are stored in a shared keychain access group so the widget/intents extension can read
/// the token to push timer changes to the server immediately. When the entitlement isn't
/// applied (e.g. unsigned `CODE_SIGNING_ALLOWED=NO` simulator builds) the access-group queries
/// fail with `errSecMissingEntitlement`, so every operation falls back to the app-only keychain.
enum KeychainStore {
    private static let service = "com.kurtisguy.BabyBuddy"
    private static let tokenAccount = "api-token"
    private static let urlAccount = "server-url"

    /// Shared keychain group; must match the `keychain-access-groups` entitlement on both
    /// targets. This equals the app's pre-existing default group (`<teamID>.<appBundleID>`),
    /// so tokens saved before sharing was added are already readable here.
    private static let accessGroup = "547DWTTFY6.com.kurtisguy.BabyBuddy"

    static func save(config: ServerConfig) {
        set(config.token, account: tokenAccount)
        set(config.baseURL.absoluteString, account: urlAccount)
    }

    static func load() -> ServerConfig? {
        guard let token = get(account: tokenAccount),
              let urlString = get(account: urlAccount),
              let url = URL(string: urlString) else { return nil }
        return ServerConfig(baseURL: url, token: token)
    }

    static func clear() {
        delete(account: tokenAccount)
        delete(account: urlAccount)
    }

    // MARK: Primitives

    private static func set(_ value: String, account: String) {
        delete(account: account)
        var query = baseQuery(account: account, shared: true)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        // Fall back to the app-only keychain on any failure — the access group is unavailable
        // on unsigned builds, and the simulator reports it inconsistently.
        if SecItemAdd(query as CFDictionary, nil) != errSecSuccess {
            var legacy = baseQuery(account: account, shared: false)
            legacy[kSecValueData as String] = Data(value.utf8)
            legacy[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(legacy as CFDictionary, nil)
        }
    }

    private static func get(account: String) -> String? {
        if let value = copy(account: account, shared: true) { return value }
        // A token stored before keychain sharing (or on an unsigned build) lives in the
        // app-only keychain; read it and migrate it into the shared group.
        if let legacy = copy(account: account, shared: false) {
            set(legacy, account: account)
            return legacy
        }
        return nil
    }

    private static func copy(account: String, shared: Bool) -> String? {
        var query = baseQuery(account: account, shared: shared)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account, shared: true) as CFDictionary)
        SecItemDelete(baseQuery(account: account, shared: false) as CFDictionary)
    }

    private static func baseQuery(account: String, shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if shared { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}
