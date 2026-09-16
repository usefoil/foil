import Foundation
import Darwin
import CryptoKit

final class ManagedLocalModelStore: @unchecked Sendable {
    enum Failure: Error, Equatable, LocalizedError {
        case unknownCapacity, insufficientSpace, unsafeStorage, unavailable, httpStatus, integrity, persistence, busy, legacyMigration
        var errorDescription: String? {
            switch self {
            case .unknownCapacity: "Foil cannot determine available disk space. Check this storage volume and try again."
            case .insufficientSpace: "There is not enough disk space for the model and safety headroom. Free space and retry."
            case .unsafeStorage: "The model store contains an unsafe file or link. Choose an intact app-owned model store."
            case .unavailable: "This model is missing, corrupt, selected, or still in use. Reinstall it or choose another verified model."
            case .httpStatus: "The model host rejected the download or redirected to an untrusted address. Retry when the host is available."
            case .integrity: "The download did not match the pinned model size and SHA-256. Retry the complete download."
            case .persistence: "The model configuration could not be saved. Check storage permissions and free space."
            case .busy: "Another model operation is finishing. Wait for it or cancel before retrying."
            case .legacyMigration: "The previous managed-model record cannot be migrated safely. Reinstall or explicitly choose a catalog model; existing provider choices are retained."
            }
        }
    }
    struct Snapshot: Sendable {
        var installed: [ManagedLocalModel] = []
        var selectedID: String?
        var recovery: [String] = []
    }
    enum Progress: Sendable { case downloading(Int64, Int64), verifying }
    private struct Inventory: Codable {
        var installed: [String]
        var selectedID: String?
    }
    private struct Transaction: Codable { let id: String }
    let root: URL
    let catalog: ManagedLocalModelCatalog
    private let capacity: @Sendable (URL) throws -> Int64?
    private let configuration: URLSessionConfiguration
    // Narrow filesystem dependencies allow deterministic OS-failure coverage
    // without replacing URLSession, integrity checks, or exclusive promotion.
    private let writeChunk: @Sendable (FileHandle, Data) throws -> Void
    private let atomicWrite: @Sendable (Data, URL) throws -> Void
    private let lock = NSLock()
    private var busy = false

    init(root: URL, catalog: ManagedLocalModelCatalog? = nil,
         capacity: (@Sendable (URL) throws -> Int64?)? = nil,
         configuration: URLSessionConfiguration = .ephemeral,
         writeChunk: @escaping @Sendable (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) },
         atomicWrite: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        self.root = URL(fileURLWithPath: root.path, isDirectory: true).standardizedFileURL
        self.catalog = try catalog ?? .bundled()
        self.configuration = configuration
        self.writeChunk = writeChunk
        self.atomicWrite = atomicWrite
        self.capacity = capacity ?? { url in
            try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
        }
    }

    func reconstruct() async throws -> Snapshot {
        try beginOperation()
        defer { endOperation() }
        return try await background { try self.reconstructFiles() }
    }

    private func reconstructFiles() throws -> Snapshot {
        try prepareRoot()
        let inventory = try readInventory()
        var result = Snapshot(selectedID: inventory.selectedID)
        try recoverTransactions(into: &result)
        for entry in catalog.models {
            try Task.checkCancellation()
            let url = installationURL(entry)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try regularFile(url)
                result.installed.append(try ManagedLocalModel.verify(url: url, id: entry.id,
                    size: entry.bytes, sha256: entry.sha256))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                result.recovery.append("\(entry.id) is unavailable: its installed file failed verification.")
            }
        }
        if let selected = result.selectedID, !result.installed.contains(where: { $0.id == selected }) {
            result.recovery.append("The selected model \(selected) is missing or corrupt. Reinstall it or choose another verified model.")
        }
        try Task.checkCancellation()
        // Reading an intact store must not require spare disk space or write
        // permission. Reconciliation changes still require an atomic durable write.
        let verifiedIDs = result.installed.map(\.id)
        if Set(inventory.installed) != Set(verifiedIDs)
            || !FileManager.default.fileExists(atPath: root.appendingPathComponent("inventory.json").path) {
            try writeInventory(Inventory(installed: verifiedIDs, selectedID: result.selectedID))
        }
        return result
    }

    func install(_ id: String, progress: @escaping @Sendable (Progress) -> Void) async throws -> ManagedLocalModel {
        try beginOperation()
        defer { endOperation() }
        let entry = try catalog.model(id)
        let destination = installationURL(entry)
        let transactionID = UUID().uuidString
        let partial = root.appendingPathComponent("partial-\(transactionID)")
        let journal = root.appendingPathComponent("transaction-\(transactionID).json")
        try await background {
            try self.prepareRoot()
            if FileManager.default.fileExists(atPath: destination.path) {
                try self.regularFile(destination)
                do {
                    _ = try ManagedLocalModel.verify(
                        url: destination,
                        id: id,
                        size: entry.bytes,
                        sha256: entry.sha256
                    )
                    throw Failure.unavailable
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as Failure {
                    throw error
                } catch {
                    // An invalid regular file at the catalog-owned destination
                    // blocks every retry. Explicit Install/Retry repairs it by
                    // removing only that unusable file before a fresh download.
                    try FileManager.default.removeItem(at: destination)
                }
            }
            guard let available = try self.capacity(self.root) else { throw Failure.unknownCapacity }
            // Existing files already consume free space. Promotion will rename the
            // partial on this filesystem, without duplicating the model bytes.
            guard available >= entry.bytes + 64 * 1024 * 1024 else { throw Failure.insufficientSpace }
            try self.atomicWrite(JSONEncoder().encode(Transaction(id: id)), journal)
        }
        do {
            let download = try ModelDownload(partial: partial, entry: entry, configuration: configuration,
                writeChunk: writeChunk, progress: progress)
            try await download.run()
            return try await background {
                try Task.checkCancellation()
                progress(.verifying)
                try self.regularFile(partial)
                _ = try ManagedLocalModel.verify(url: partial, id: id, size: entry.bytes, sha256: entry.sha256)
                try Task.checkCancellation()
                // RENAME_EXCL prevents an accidental overwrite, even if the destination
                // appears between the preflight and promotion.
                guard renameatx_np(AT_FDCWD, partial.path, AT_FDCWD, destination.path, UInt32(RENAME_EXCL)) == 0 else {
                    throw errno == ENOSPC ? Failure.insufficientSpace : Failure.unsafeStorage
                }
                let model = try ManagedLocalModel.verify(url: destination, id: id, size: entry.bytes, sha256: entry.sha256)
                var inventory = try self.readInventory()
                if !inventory.installed.contains(id) { inventory.installed.append(id) }
                try self.writeInventory(inventory)
                try FileManager.default.removeItem(at: journal)
                return model
            }
        } catch {
            // Keep the recorded transaction for truthful full-restart recovery.
            // Neither cancellation nor interruption can promote partial bytes.
            let nsError = error as NSError
            if nsError.code == NSFileWriteOutOfSpaceError || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC)) {
                throw Failure.insufficientSpace
            }
            throw error
        }
    }

    static func permitsDownloadURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
            && ["huggingface.co", "us.aws.cdn.hf.co", "cas-bridge.xethub.hf.co"].contains(url.host ?? "")
    }

    func installationURL(_ model: ManagedLocalModelCatalog.Model) -> URL {
        root.appendingPathComponent("\(ManagedLocalModelCatalog.revision)-\(model.sha256)-\(model.id).bin")
    }

    private func prepareRoot() throws {
        let manager = FileManager.default
        if let attributes = try? manager.attributesOfItem(atPath: root.path),
           attributes[.type] as? FileAttributeType != .typeDirectory { throw Failure.unsafeStorage }
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try manager.attributesOfItem(atPath: root.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              permissions & 0o022 == 0 else { throw Failure.unsafeStorage }
        let resolvedParent = root.deletingLastPathComponent().resolvingSymlinksInPath()
        guard root.resolvingSymlinksInPath() == resolvedParent.appendingPathComponent(root.lastPathComponent) else {
            throw Failure.unsafeStorage
        }
    }

    private func regularFile(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              url.resolvingSymlinksInPath().deletingLastPathComponent() == root.resolvingSymlinksInPath() else {
            throw Failure.unsafeStorage
        }
    }

    private func readInventory() throws -> Inventory {
        let url = root.appendingPathComponent("inventory.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return Inventory(installed: []) }
        try regularFile(url)
        return try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: url))
    }

    private func writeInventory(_ inventory: Inventory) throws {
        let url = root.appendingPathComponent("inventory.json")
        if FileManager.default.fileExists(atPath: url.path) { try regularFile(url) }
        try atomicWrite(JSONEncoder().encode(inventory), url)
    }

    /// Small synchronous atomic metadata commit, called on the runtime's commit
    /// boundary. Model hashing/download work has already completed off MainActor.
    func commitSelection(_ id: String) throws {
        try beginOperation()
        defer { endOperation() }
        try prepareRoot()
        _ = try catalog.model(id)
        var inventory = try readInventory()
        guard inventory.installed.contains(id) else { throw Failure.unavailable }
        inventory.selectedID = id
        try writeInventory(inventory)
    }

    func remove(_ id: String) async throws {
        try beginOperation()
        defer { endOperation() }
        try await background {
            try self.prepareRoot()
            let model = try self.catalog.model(id)
            var inventory = try self.readInventory()
            guard inventory.selectedID != id else { throw Failure.unavailable }
            let url = self.installationURL(model)
            try self.regularFile(url)
            try FileManager.default.removeItem(at: url)
            inventory.installed.removeAll { $0 == id }
            try self.writeInventory(inventory)
        }
    }

    private func recoverTransactions(into snapshot: inout Snapshot) throws {
        for filename in try FileManager.default.contentsOfDirectory(atPath: root.path) {
            guard filename.hasPrefix("transaction-"), filename.hasSuffix(".json") else { continue }
            let suffix = String(filename.dropFirst(12).dropLast(5))
            guard UUID(uuidString: suffix)?.uuidString == suffix else { continue }
            let journal = root.appendingPathComponent(filename)
            try regularFile(journal)
            let transaction = try JSONDecoder().decode(Transaction.self, from: Data(contentsOf: journal))
            _ = try catalog.model(transaction.id)
            let partial = root.appendingPathComponent("partial-\(suffix)")
            if FileManager.default.fileExists(atPath: partial.path) {
                try regularFile(partial)
                try FileManager.default.removeItem(at: partial)
            }
            try FileManager.default.removeItem(at: journal)
            snapshot.recovery.append("Interrupted \(transaction.id) installation recovered. A new download starts from the beginning.")
        }
    }

    private func beginOperation() throws {
        try lock.withLock {
            guard !busy else { throw Failure.busy }
            busy = true
        }
    }

    private func endOperation() { lock.withLock { busy = false } }

    private func background<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .utility) { try operation() }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

/// A private ephemeral session streams bounded chunks directly into an exclusive,
/// owned partial file. All delegate/file/hash work runs on a serial utility queue.
final class ModelDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Failure = ManagedLocalModelStore.Failure
    private let entry: ManagedLocalModelCatalog.Model
    private let file: FileHandle
    private let configuration: URLSessionConfiguration
    private let writeChunk: @Sendable (FileHandle, Data) throws -> Void
    private let progress: @Sendable (ManagedLocalModelStore.Progress) -> Void
    private let queue = OperationQueue()
    private let cancellationLock = NSLock()
    private var cancelled = false
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?
    private var count: Int64 = 0
    private var digest = SHA256()
    private var redirects = 0

    init(partial: URL, entry: ManagedLocalModelCatalog.Model, configuration: URLSessionConfiguration,
         writeChunk: @escaping @Sendable (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) },
         progress: @escaping @Sendable (ManagedLocalModelStore.Progress) -> Void) throws {
        let descriptor = open(partial.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw errno == ENOSPC ? Failure.insufficientSpace : Failure.unsafeStorage }
        self.file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        self.entry = entry
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.writeChunk = writeChunk
        self.progress = progress
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        super.init()
    }

    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.addOperation {
                    self.continuation = continuation
                    self.configuration.urlCredentialStorage = nil
                    self.configuration.httpCookieStorage = nil
                    self.configuration.httpShouldSetCookies = false
                    self.configuration.httpAdditionalHeaders = [:]
                    self.configuration.urlCache = nil
                    self.configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                    self.configuration.timeoutIntervalForRequest = 60
                    self.configuration.timeoutIntervalForResource = 1800
                    let session = URLSession(configuration: self.configuration, delegate: self, delegateQueue: self.queue)
                    self.session = session
                    let task = session.dataTask(with: self.entry.downloadURL)
                    self.cancellationLock.withLock {
                        self.task = task
                        if self.cancelled { task.cancel() }
                    }
                    task.resume()
                }
            }
        } onCancel: {
            self.cancellationLock.withLock { self.cancelled = true; self.task?.cancel() }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            failure = Failure.httpStatus; completionHandler(.cancel); return
        }
        guard let url = response.url, ManagedLocalModelStore.permitsDownloadURL(url),
              response.expectedContentLength == -1 || response.expectedContentLength == entry.bytes else {
            failure = Failure.integrity; completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        guard !cancellationLock.withLock({ cancelled }) else { dataTask.cancel(); return }
        guard Int64(data.count) <= entry.bytes - count else {
            failure = Failure.integrity; dataTask.cancel(); return
        }
        do {
            try writeChunk(file, data)
            digest.update(data: data); count += Int64(data.count)
            progress(.downloading(count, entry.bytes))
        } catch { failure = error; dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 5, let url = request.url, ManagedLocalModelStore.permitsDownloadURL(url) else {
            failure = Failure.httpStatus; completionHandler(nil); return
        }
        var clean = URLRequest(url: url)
        clean.httpMethod = "GET"
        completionHandler(clean)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate(); self.session = nil }
        var result = failure ?? error
        if cancellationLock.withLock({ cancelled }) { result = CancellationError() }
        if result == nil {
            if count != entry.bytes || digest.finalize().map({ String(format: "%02x", $0) }).joined() != entry.sha256 {
                result = Failure.integrity
            }
        }
        do { try file.synchronize(); try file.close() } catch { if result == nil { result = error } }
        if let result { continuation?.resume(throwing: result) } else { continuation?.resume() }
        continuation = nil
    }
}
