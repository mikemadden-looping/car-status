import Foundation
import Security

/// Small wrapper around the keychain group shared by the app and the widget.
/// Everything secret (Kia sign-in, ABRP keys) and the last fetched status
/// lives here, readable after the phone's first unlock so the widget can
/// refresh while the phone is locked.
enum Keychain {
    private static let service = "CarStatus"

    private static var accessGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "KeychainGroup") as? String,
              !group.isEmpty, !group.hasPrefix("."), !group.contains("$(") else { return nil }
        return group
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    static func data(_ key: String) -> Data? {
        var q = baseQuery(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func set(_ data: Data?, for key: String) {
        let q = baseQuery(key)
        guard let data else {
            SecItemDelete(q as CFDictionary)
            return
        }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(q as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = q
            attrs.forEach { add[$0.key] = $0.value }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func string(_ key: String) -> String? {
        data(key).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func set(_ string: String?, for key: String) {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines)
        set((trimmed?.isEmpty ?? true) ? nil : trimmed!.data(using: .utf8), for: key)
    }

    static func codable<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        data(key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    static func set<T: Encodable>(codable value: T?, for key: String) {
        set(value.flatMap { try? JSONEncoder().encode($0) }, for: key)
    }
}

enum Keys {
    static let kiaEmail = "kia.email"
    static let kiaPassword = "kia.password"
    static let kiaDeviceID = "kia.deviceID"
    static let kiaSession = "kia.session"
    static let kiaRememberToken = "kia.rmtoken"
    static let kiaVehicleID = "kia.vehicleID"
    static let abrpAPIKey = "abrp.apiKey"
    static let abrpUserToken = "abrp.userToken"
    static let snapshot = "status.snapshot"
}
