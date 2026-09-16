import Foundation
import Security
import agtermCore

/// The login-keychain items behind Insert Secret and `secret.*`: one generic-password item per label under
/// `Brand.keychainService`, so Keychain Access lists them together and a Debug build (a different code
/// signature) is asked before reading what Release stored. Nothing is cached: every read hits the keychain,
/// so a value never sits in process memory longer than one insert.
enum KeychainSecretStore {
    enum Failure: Error, CustomStringConvertible {
        case status(OSStatus)

        var description: String {
            switch self {
            case .status(let status):
                return (SecCopyErrorMessageString(status, nil) as String?) ?? "keychain error \(status)"
            }
        }
    }

    static func labels() throws -> [String] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Brand.keychainService,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw Failure.status(status) }
        let items = result as? [[CFString: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount] as? String }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Store `value` under `label`, replacing an existing item so re-adding rotates a password in place.
    static func set(_ value: String, label: String) throws {
        let data = Data(value.utf8)
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(itemQuery(label) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Failure.status(status) }
        var item = itemQuery(label)
        item[kSecValueData] = data
        item[kSecAttrLabel] = "\(Brand.productName): \(label)"
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.status(added) }
    }

    /// Whether an item was there to delete.
    static func remove(label: String) throws -> Bool {
        let status = SecItemDelete(itemQuery(label) as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw Failure.status(status) }
        return true
    }

    /// Nil when no item carries `label`.
    static func value(label: String) throws -> String? {
        var query = itemQuery(label)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure.status(status) }
        return String(decoding: data, as: UTF8.self)
    }

    private static func itemQuery(_ label: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Brand.keychainService,
            kSecAttrAccount: label,
        ]
    }
}
