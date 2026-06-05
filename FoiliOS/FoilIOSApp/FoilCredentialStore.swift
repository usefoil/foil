import Foundation
import Security

struct FoilCredentialStore {
    static let shared = FoilCredentialStore()

    private let service = "com.neonwatty.FoilIOS.groq"
    private let account = "groq-api-key"

    func loadGroqAPIKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return nonEmpty(value)
    }

    func saveGroqAPIKey(_ value: String) throws {
        guard let apiKey = nonEmpty(value),
              let data = apiKey.data(using: .utf8) else {
            throw FoilCredentialStoreError.emptyCredential
        }

        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw FoilCredentialStoreError.keychainStatus(updateStatus)
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw FoilCredentialStoreError.keychainStatus(addStatus)
        }
    }

    func clearGroqAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FoilCredentialStoreError.keychainStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

enum FoilCredentialStoreError: LocalizedError {
    case emptyCredential
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyCredential:
            return "Enter a Groq key before saving"
        case .keychainStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Could not update Groq key: \(message)"
            }
            return "Could not update Groq key: OSStatus \(status)"
        }
    }
}
