import Foundation
import Security

/// Stores the Claude.ai `sessionKey` cookie in the macOS Keychain as a generic
/// password. Used instead of UserDefaults so the secret is encrypted at rest and
/// protected by the system keychain rather than sitting in a plist.
enum KeychainStore {
    private static let service = "com.claudeusagehud.ClaudeUsageHUD"
    private static let account = "claude.ai-session-key"

    /// The session key currently stored, or `nil` if setup hasn't happened yet.
    static var sessionKey: String? { load() }

    /// Whether a session key has been saved.
    static var hasSessionKey: Bool { load()?.isEmpty == false }

    /// Saves (or overwrites) the session key. Returns `true` on success.
    @discardableResult
    static func save(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Delete any existing item first so we always end up with exactly one.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Reads the stored session key, or `nil` if none is present.
    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        return value
    }

    /// Removes the stored session key (e.g. when the user signs out).
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
