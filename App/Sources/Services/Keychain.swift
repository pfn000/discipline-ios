import Foundation
import Security

/// Stores the optional GitHub token. Plain keychain items need no extra entitlement.
enum Keychain {
    private static let service = "com.ncom.discipline.github"

    static func save(_ value: String) -> Bool {
        delete()
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return true }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                                kSecValueData as String: data]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func delete() -> Bool {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        let s = SecItemDelete(q as CFDictionary)
        return s == errSecSuccess || s == errSecItemNotFound
    }
}
