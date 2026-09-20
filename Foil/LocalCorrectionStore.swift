import Foundation

struct LocalCorrectionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let revision: Int
    let isEnabled: Bool
    let rules: [LocalCorrectionRule]

    init(revision: Int = 0, isEnabled: Bool = false, rules: [LocalCorrectionRule] = []) {
        schemaVersion = Self.currentSchemaVersion
        self.revision = revision
        self.isEnabled = isEnabled
        self.rules = rules
    }

    enum CodingKeys: String, CodingKey {
        case revision, rules
        case schemaVersion = "schema_version"
        case isEnabled = "is_enabled"
    }
}

enum LocalCorrectionStoreError: Error, Equatable {
    case unreadable
    case unsupportedSchema(Int)
    case revisionConflict(expected: Int, actual: Int)
    case writeFailed
}

final class LocalCorrectionStore {
    static let fileName = "local-corrections-v1.json"

    private let fileURL: URL
    private let fileManager: FileManager
    private let atomicWriter: (Data, URL) throws -> Void
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        atomicWriter: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.atomicWriter = atomicWriter
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    convenience init(fileManager: FileManager = .default) {
        let directory: URL
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            directory = fileManager.temporaryDirectory.appendingPathComponent(
                "Foil Local Correction Unit Tests \(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directoryName = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                ? "Foil UI Tests"
                : AppBrand.applicationSupportDirectoryName
            directory = appSupport.appendingPathComponent(directoryName, isDirectory: true)
        }
        self.init(fileURL: directory.appendingPathComponent(Self.fileName), fileManager: fileManager)
    }

    func load() throws -> LocalCorrectionSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return LocalCorrectionSnapshot()
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw LocalCorrectionStoreError.unreadable
        }

        let schemaVersion: Int
        do {
            schemaVersion = try decoder.decode(SchemaHeader.self, from: data).schemaVersion
        } catch {
            throw LocalCorrectionStoreError.unreadable
        }
        guard schemaVersion == LocalCorrectionSnapshot.currentSchemaVersion else {
            throw LocalCorrectionStoreError.unsupportedSchema(schemaVersion)
        }

        do {
            let snapshot = try decoder.decode(LocalCorrectionSnapshot.self, from: data)
            guard snapshot.revision >= 0 else { throw LocalCorrectionStoreError.unreadable }
            _ = try LocalCorrectionEngine.compile(snapshot.rules)
            return snapshot
        } catch let error as LocalCorrectionStoreError {
            throw error
        } catch {
            throw LocalCorrectionStoreError.unreadable
        }
    }

    @discardableResult
    func save(
        rules: [LocalCorrectionRule],
        isEnabled: Bool? = nil,
        expectedRevision: Int
    ) throws -> LocalCorrectionSnapshot {
        let current = try load()
        guard current.revision == expectedRevision else {
            throw LocalCorrectionStoreError.revisionConflict(
                expected: expectedRevision,
                actual: current.revision
            )
        }

        _ = try LocalCorrectionEngine.compile(rules)
        let snapshot = LocalCorrectionSnapshot(
            revision: current.revision + 1,
            isEnabled: isEnabled ?? current.isEnabled,
            rules: rules
        )
        let data = try encoder.encode(snapshot)
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try atomicWriter(data, fileURL)
        } catch {
            throw LocalCorrectionStoreError.writeFailed
        }
        return snapshot
    }

    private struct SchemaHeader: Decodable {
        let schemaVersion: Int

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
        }
    }
}
