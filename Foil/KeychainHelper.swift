import Foundation
import LocalAuthentication
import Security

enum KeychainHelper {
    private static let defaultAccount = "groq-api-key"

    #if DEBUG
    static var storageDirectoryOverride: URL?
    static var serviceOverride: String?
    static var accountOverride: String?
    #endif

    private static var service: String {
        #if DEBUG
        serviceOverride ?? AppBrand.keychainService
        #else
        AppBrand.keychainService
        #endif
    }

    private static func account(for providerID: TranscriptionProviderID) -> String {
        #if DEBUG
        let base = accountOverride ?? defaultAccount
        #else
        let base = defaultAccount
        #endif
        switch providerID {
        case .groq:
            return base
        case .openAI:
            return "\(base).\(providerID.rawValue)"
        case .openAICompatible:
            return "\(base).\(providerID.rawValue)"
        }
    }

    private static func cleanupAccount(for providerID: TranscriptCleanupProviderID) -> String {
        #if DEBUG
        let base = accountOverride ?? defaultAccount
        #else
        let base = defaultAccount
        #endif
        return "\(base).cleanup.\(providerID.rawValue)"
    }

    private static var legacyPlaintextStorageURL: URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        #if DEBUG
        if let storageDirectoryOverride {
            return storageDirectoryOverride.appendingPathComponent("api-key")
        }
        #endif

        let dir = appSupport.appendingPathComponent(AppBrand.applicationSupportDirectoryName, isDirectory: true)
        return dir.appendingPathComponent("api-key")
    }

    static func save(apiKey: String) throws {
        try save(apiKey: apiKey, for: .groq)
    }

    static func save(apiKey: String, for providerID: TranscriptionProviderID) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try saveToKeychain(apiKey: trimmed, for: providerID)
        if providerID == .groq, let legacyURL = legacyPlaintextStorageURL {
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    static func readApiKey() -> String? {
        readApiKey(for: .groq)
    }

    static func readApiKey(for providerID: TranscriptionProviderID) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        if args.contains("--ui-testing"),
           (!args.contains("--e2e-transcribe") || env["E2E_API_KEY"]?.isEmpty == false) {
            return nil
        }
        #endif
        if let key = readFromKeychain(for: providerID) {
            if providerID == .groq, let legacyURL = legacyPlaintextStorageURL {
                try? FileManager.default.removeItem(at: legacyURL)
            }
            return key
        }
        guard providerID == .groq else { return nil }
        return migrateLegacyPlaintextFile()
    }

    static func delete() {
        delete(for: .groq)
    }

    static func delete(for providerID: TranscriptionProviderID) {
        deleteFromKeychain(for: providerID)
        if providerID == .groq, let legacyURL = legacyPlaintextStorageURL {
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    static func saveCleanupApiKey(_ apiKey: String, for providerID: TranscriptCleanupProviderID) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try saveToKeychain(apiKey: trimmed, account: cleanupAccount(for: providerID))
    }

    static func readCleanupApiKey(for providerID: TranscriptCleanupProviderID) -> String? {
        readFromKeychain(account: cleanupAccount(for: providerID))
    }

    static func deleteCleanupApiKey(for providerID: TranscriptCleanupProviderID) {
        deleteFromKeychain(account: cleanupAccount(for: providerID))
    }

    // MARK: - Keychain storage

    private static func saveToKeychain(apiKey: String, for providerID: TranscriptionProviderID = .groq) throws {
        try saveToKeychain(apiKey: apiKey, account: account(for: providerID))
    }

    private static func saveToKeychain(apiKey: String, account: String) throws {
        let data = Data(apiKey.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let addStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        if addStatus == errSecSuccess { return }

        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(updateStatus)
            }
            return
        }

        throw KeychainError.unhandledStatus(addStatus)
    }

    private static func readFromKeychain(for providerID: TranscriptionProviderID = .groq) -> String? {
        readFromKeychain(account: account(for: providerID))
    }

    private static func readFromKeychain(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        let started = Date()
        let (status, result) = copyMatching(query)
        logKeychainRead(status: status, account: account, started: started)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    private static func logKeychainRead(status: OSStatus, account: String, started: Date) {
        let elapsedMilliseconds = Int(Date().timeIntervalSince(started) * 1000)
        DiagnosticLog.write(
            "KeychainHelper: read account=\(account) service=\(service) status=\(statusName(status)) durationMs=\(elapsedMilliseconds) interactionAllowed=false"
        )
    }

    private static func statusName(_ status: OSStatus) -> String {
        switch status {
        case errSecSuccess:
            return "success"
        case errSecItemNotFound:
            return "itemNotFound"
        case errSecInteractionNotAllowed:
            return "interactionNotAllowed"
        case errSecAuthFailed:
            return "authFailed"
        case errSecUserCanceled:
            return "userCanceled"
        default:
            return "osStatus(\(status))"
        }
    }

    private static func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?) {
        guard Thread.isMainThread else {
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result)
        }

        final class KeychainResultBox: @unchecked Sendable {
            private let lock = NSLock()
            private var status: OSStatus = errSecInteractionNotAllowed
            private var result: AnyObject?

            func store(status: OSStatus, result: AnyObject?) {
                lock.lock()
                self.status = status
                self.result = result
                lock.unlock()
            }

            func load() -> (OSStatus, AnyObject?) {
                lock.lock()
                defer { lock.unlock() }
                return (status, result)
            }
        }

        let box = KeychainResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            box.store(status: status, result: result)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 1.5) == .timedOut {
            DiagnosticLog.write("KeychainHelper: timed out reading keychain on main thread")
            return (errSecInteractionNotAllowed, nil)
        }

        return box.load()
    }

    private static func deleteFromKeychain(for providerID: TranscriptionProviderID = .groq) {
        deleteFromKeychain(account: account(for: providerID))
    }

    private static func deleteFromKeychain(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func baseQuery(for providerID: TranscriptionProviderID = .groq) -> [String: Any] {
        baseQuery(account: account(for: providerID))
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    // MARK: - Legacy plaintext migration

    private static func migrateLegacyPlaintextFile() -> String? {
        guard let legacyURL = legacyPlaintextStorageURL,
              let data = try? Data(contentsOf: legacyURL),
              let key = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            if let legacyURL = legacyPlaintextStorageURL {
                try? FileManager.default.removeItem(at: legacyURL)
            }
            return nil
        }

        do {
            try saveToKeychain(apiKey: key, for: .groq)
            try? FileManager.default.removeItem(at: legacyURL)
            return key
        } catch {
            DiagnosticLog.write("KeychainHelper: failed to migrate legacy plaintext API key status=\(error.localizedDescription)")
            return key
        }
    }

    enum KeychainError: LocalizedError, Equatable {
        case unhandledStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unhandledStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return "Keychain error \(status)"
            }
        }
    }
}
