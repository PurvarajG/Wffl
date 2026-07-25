import Foundation
import Security

/// Keychain-backed storage for LLM API keys. These used to live in
/// UserDefaults, which writes them as plaintext into a preferences plist that
/// any process running as the user (and every Time Machine / iCloud backup of
/// the home folder) can read. Generic-password items are encrypted at rest and
/// bound to this app's code signature instead.
///
/// Items use service "Wffl" with the provider id as the account, so one entry
/// per provider and no collisions with anything else in the login keychain.
enum KeychainStore {
    private static let service = "Wffl"

    /// Shared attributes identifying exactly one item. `kSecAttrSynchronizable`
    /// is pinned to `false` so keys stay on this Mac and never ride iCloud
    /// Keychain to the user's other devices.
    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    /// The stored secret, or "" when absent. A keychain read can also fail
    /// because the item was written by a differently-signed build of the app;
    /// that reads as absent, which degrades to "no key configured" rather than
    /// crashing mid-summary.
    static func read(account: String) -> String {
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    /// Stores (or replaces) the secret. An empty value deletes the item, so
    /// clearing the field in Settings actually removes the key rather than
    /// leaving an empty entry behind.
    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        guard !value.isEmpty else { return delete(account: account) }
        let data = Data(value.utf8)
        let q = query(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var insert = q
        insert[kSecValueData as String] = data
        // Keys are only needed while the app is running and the user is at the
        // machine; this is the strictest class that still survives a reboot.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
