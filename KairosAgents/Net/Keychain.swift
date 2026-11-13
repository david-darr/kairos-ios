import Foundation
import Security

/// The phone's desktop token lives here and nowhere else: one generic password item,
/// readable after the first unlock so a notification action can still sign a request.
nonisolated enum Keychain {
    private static let service = "app.kairos-agents.mobile.desktop"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        SecItemDelete(query(account) as CFDictionary)
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// What a read found. `unreadable` is not "missing": before the first unlock after a restart the item
    /// is there but cannot be read yet.
    nonisolated enum Lookup: Equatable, Sendable {
        case found(String)
        case missing
        case unreadable
    }

    static func lookup(account: String) -> Lookup {
        var item = query(account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess else { return .unreadable }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { return .missing }
        return .found(value)
    }

    static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
