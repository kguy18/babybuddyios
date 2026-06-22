import Foundation
import Security

/// Minimal Keychain wrapper for the server URL + API token. The token is the only
/// secret; both are stored with `WhenUnlockedThisDeviceOnly` so they never sync or
/// leave the device.
enum KeychainStore {
    private static let service = "com.kurtisguy.BabyBuddy"
    private static let tokenAccount = "api-token"
    private static let urlAccount = "server-url"

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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
