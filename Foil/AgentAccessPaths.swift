import Darwin
import Foundation

struct AgentAccessPaths: Equatable {
    static let socketFileName = "agent-v1.sock"
    static let lockFileName = ".agent-v1.lock"
    static let proposalStoreFileName = "agent-vocabulary-proposals-v1.json"

    let applicationSupportRoot: URL
    let supportDirectory: URL
    let socketURL: URL
    let lockURL: URL
    let proposalStoreURL: URL

    init(applicationSupportRoot: URL, directoryName: String) {
        self.applicationSupportRoot = applicationSupportRoot.standardizedFileURL
        supportDirectory = self.applicationSupportRoot.appendingPathComponent(directoryName, isDirectory: true)
        socketURL = supportDirectory.appendingPathComponent(Self.socketFileName)
        lockURL = supportDirectory.appendingPathComponent(Self.lockFileName)
        proposalStoreURL = supportDirectory.appendingPathComponent(Self.proposalStoreFileName)
    }

    static func current(fileManager: FileManager = .default) -> AgentAccessPaths {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return AgentAccessPaths(
            applicationSupportRoot: applicationSupport,
            directoryName: AppBrand.applicationSupportDirectoryName
        )
    }

    static var maximumSocketPathBytes: Int {
        var address = sockaddr_un()
        return withUnsafeBytes(of: &address.sun_path) { $0.count - 1 }
    }

    func validateSocketPath() throws {
        let standardizedSupportDirectory = supportDirectory.standardizedFileURL
        guard standardizedSupportDirectory.deletingLastPathComponent() == applicationSupportRoot,
              socketURL.standardizedFileURL.deletingLastPathComponent() == standardizedSupportDirectory,
              lockURL.standardizedFileURL.deletingLastPathComponent() == standardizedSupportDirectory,
              proposalStoreURL.standardizedFileURL.deletingLastPathComponent() == standardizedSupportDirectory else {
            throw AgentAccessPathError.unsafeLayout
        }
        let bytes = Array(socketURL.path.utf8)
        guard !bytes.contains(0), bytes.count <= Self.maximumSocketPathBytes else {
            throw AgentAccessPathError.socketPathTooLong(
                actualBytes: bytes.count,
                maximumBytes: Self.maximumSocketPathBytes
            )
        }
    }
}

enum AgentAccessPathError: Error, Equatable, LocalizedError {
    case unsafeLayout
    case socketPathTooLong(actualBytes: Int, maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .unsafeLayout:
            "Agent Access paths must remain inside the selected Application Support directory."
        case let .socketPathTooLong(actualBytes, maximumBytes):
            "Agent Access socket path is \(actualBytes) bytes; macOS allows at most \(maximumBytes)."
        }
    }
}
