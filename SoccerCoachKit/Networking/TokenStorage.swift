import Foundation
import Security

/// The string key/value backing `TokenStore` persists tokens through. Production
/// uses the Keychain; tests inject an in-memory implementation so they don't
/// touch (or depend on) the shared system keychain.
protocol TokenStorage: AnyObject {
    func string(forKey key: String) -> String?
    /// Stores (or, for `nil`, removes) a value, reporting whether it worked.
    /// The result is load-bearing: a keychain write can fail — the device is
    /// locked before first unlock, the item is inaccessible, the entitlement is
    /// missing on an unsigned build — and a failure that isn't reported reads
    /// back as a missing token later, which surfaces as a session that can never
    /// be established no matter how often the coach signs in.
    @discardableResult
    func set(_ value: String?, forKey key: String) -> Bool
}

/// Keychain-backed token storage. Session tokens are bearer credentials, so they
/// belong here rather than in `UserDefaults` (which is a plist readable from an
/// unencrypted device backup). Items are generic passwords scoped to this app's
/// service, accessible after the first unlock so background sync can read them.
final class KeychainTokenStorage: TokenStorage {
    private let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "SoccerCoachKit") + ".tokens") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    @discardableResult
    func set(_ value: String?, forKey key: String) -> Bool {
        guard let value, let data = value.data(using: .utf8) else {
            let status = SecItemDelete(baseQuery(key) as CFDictionary)
            // Nothing there to delete is the outcome the caller asked for.
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, update)
        guard status == errSecItemNotFound else { return status == errSecSuccess }

        var insert = baseQuery(key)
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
