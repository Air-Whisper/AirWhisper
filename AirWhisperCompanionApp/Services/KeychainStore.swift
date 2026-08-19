import Foundation
import Security

final class KeychainStore {
    static let shared = KeychainStore()

    private let service: String

    private init(service: String = Bundle.main.bundleIdentifier ?? "dev.ayaan.AirWhisperCompanionApp") {
        self.service = service
    }

    @discardableResult
    func save(_ value: String, for account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        deleteValue(for: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Failed to save \(account): \(status)")
        }
        return status == errSecSuccess
    }

    func loadValue(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                print("[Keychain] Failed to load \(account): \(status)")
            }
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func deleteValue(for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("[Keychain] Failed to delete \(account): \(status)")
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
