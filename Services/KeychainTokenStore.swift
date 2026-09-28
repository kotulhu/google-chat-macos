import Foundation
import Security

/// Persists the Google OAuth refresh token in the macOS Keychain
/// (`kSecClassGenericPassword`), so the app can restore a session without
/// re-running the interactive OAuth flow on every launch.
///
/// Only the refresh token lives here (it is a long-lived secret). Non-secret
/// session details (e-mail / display name) are kept in UserDefaults as a
/// convenience for restoring the UI, never in plain text on disk.
enum KeychainTokenStore {
    private static let service = "khtulhu.GoogleChat.auth"
    private static let account = "googleOAuthRefreshToken"

    /// Stores (or replaces) the refresh token. Returns whether the write succeeded.
    @discardableResult
    static func saveRefreshToken(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Returns the stored refresh token, or `nil` when not present.
    static var refreshToken: String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the stored refresh token (e.g. after sign-out or `invalid_grant`).
    static func deleteRefreshToken() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}