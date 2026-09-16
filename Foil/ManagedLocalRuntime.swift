import CryptoKit
import Darwin
import Foundation
import Network
import Observation
import Security

enum ManagedLocalError: Error, Equatable, LocalizedError {
    case modelIntegrity, invalidRuntime, unsafeAddress, foreignService, notReady, startupFailed, timedOut, transport

    var errorDescription: String? {
        switch self {
        case .modelIntegrity: "The local model failed its integrity check."
        case .invalidRuntime: "The bundled local transcription runtime is missing or invalid."
        case .unsafeAddress: "The local transcription address is not safely available on this Mac."
        case .foreignService: "Another service answered on the local transcription address."
        case .notReady: "The managed local model is not ready."
        case .startupFailed: "The managed local model could not start."
        case .timedOut: "The managed local model took too long to start."
        case .transport: "The managed local transcription connection failed."
        }
    }
}

/// Created only after checking an installer-provided immutable size and digest.
struct ManagedLocalModel: Equatable, Sendable {
    let url: URL
    let id: String
    let size: Int64
    let sha256: String

    private init(url: URL, id: String, size: Int64, sha256: String) {
        self.url = url; self.id = id; self.size = size; self.sha256 = sha256
    }

    static func verify(url: URL, id: String, size: Int64, sha256: String) throws -> Self {
        let model = Self(url: url, id: id, size: size, sha256: sha256)
        try model.revalidate()
        return model
    }

    func revalidate() throws {
        try Task.checkCancellation()
        guard size > 0, sha256.count == 64, sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value == size,
              let file = try? FileHandle(forReadingFrom: url) else { throw ManagedLocalError.modelIntegrity }
        defer { try? file.close() }
        var digest = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            digest.update(data: data)
        }
        guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else {
            throw ManagedLocalError.modelIntegrity
        }
    }
}

enum ManagedLocalHealth {
    static func matches(_ data: Data, session: UUID, modelSHA256: String, pid: Int32) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.count == 5 else { return false }
        return object["status"] as? String == "ok" && object["service"] as? String == "foil-whisper"
            && object["session"] as? String == session.uuidString
            && object["model_sha256"] as? String == modelSHA256
            && (object["pid"] as? NSNumber)?.int32Value == pid
    }
}

/// This client resolves the requested hostname through Network.framework, constrains
/// the connection to the loopback interface, bypasses proxies, and never follows redirects.
/// It accepts the helper's bounded Content-Length responses only.
final class ManagedLocalHTTP: @unchecked Sendable {
    static let hostname = "transcribe.foil.localhost"
    private let queue = DispatchQueue(label: "com.usefoil.managed-http")
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var received = Data()
    private var cancelled = false

    static func validateResolution() throws {
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, nil, nil, &result) == 0, let first = result else {
            throw ManagedLocalError.unsafeAddress
        }
        defer { freeaddrinfo(first) }
        var item: UnsafeMutablePointer<addrinfo>? = first
        while let current = item {
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen,
                              &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0,
                  ["127.0.0.1", "::1"].contains(String(cString: name)) else {
                throw ManagedLocalError.unsafeAddress
            }
            item = current.pointee.ai_next
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        try Self.validateResolution()
        guard let url = request.url, url.scheme == "http", url.host == Self.hostname,
              let portNumber = url.port, let port = NWEndpoint.Port(rawValue: UInt16(exactly: portNumber) ?? 0),
              portNumber > 0, url.query == nil, url.user == nil, url.password == nil else {
            throw ManagedLocalError.unsafeAddress
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.continuation = continuation
                    guard !self.cancelled else { self.finish(.failure(CancellationError())); return }
                    let parameters = NWParameters.tcp
                    parameters.requiredInterfaceType = .loopback
                    parameters.preferNoProxies = true
                    let connection = NWConnection(host: NWEndpoint.Host(Self.hostname), port: port, using: parameters)
                    self.connection = connection
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            var header = "\(request.httpMethod ?? "GET") \(url.path) HTTP/1.1\r\nHost: \(Self.hostname):\(portNumber)\r\nConnection: close\r\n"
                            if let contentType = request.value(forHTTPHeaderField: "Content-Type") {
                                guard !contentType.contains("\r"), !contentType.contains("\n") else {
                                    self.finish(.failure(ManagedLocalError.transport)); return
                                }
                                header += "Content-Type: \(contentType)\r\n"
                            }
                            let body = request.httpBody ?? Data()
                            header += "Content-Length: \(body.count)\r\n\r\n"
                            var bytes = Data(header.utf8); bytes.append(body)
                            connection.send(content: bytes, completion: .contentProcessed { error in
                                if error != nil { self.finish(.failure(ManagedLocalError.transport)) }
                                else { self.receive(url: url) }
                            })
                        case .failed, .waiting: self.finish(.failure(ManagedLocalError.transport))
                        default: break
                        }
                    }
                    connection.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + max(1, min(request.timeoutInterval, 120))) {
                        self.finish(.failure(ManagedLocalError.timedOut))
                    }
                }
            }
        } onCancel: {
            self.queue.async { self.cancelled = true; self.finish(.failure(CancellationError())) }
        }
    }

    private func receive(url: URL) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
            if let data { self.received.append(data) }
            guard error == nil, self.received.count <= 8_388_608 else {
                self.finish(.failure(ManagedLocalError.transport)); return
            }
            if let boundary = self.received.range(of: Data("\r\n\r\n".utf8)) {
                guard let header = String(data: self.received[..<boundary.lowerBound], encoding: .utf8) else {
                    self.finish(.failure(ManagedLocalError.transport)); return
                }
                let lines = header.components(separatedBy: "\r\n")
                let status = lines[0].split(separator: " ").dropFirst().first.flatMap { Int($0) }
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = line[..<colon].lowercased()
                    guard headers[key] == nil else { self.finish(.failure(ManagedLocalError.transport)); return }
                    headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                guard let status, !(300...399).contains(status), headers["transfer-encoding"] == nil,
                      let lengthText = headers["content-length"], let length = Int(lengthText), length >= 0,
                      length <= 8_388_608 else { self.finish(.failure(ManagedLocalError.transport)); return }
                let body = Data(self.received[boundary.upperBound...])
                if body.count >= length {
                    guard body.count == length,
                          let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
                        self.finish(.failure(ManagedLocalError.transport)); return
                    }
                    self.finish(.success((body, response))); return
                }
            }
            if complete { self.finish(.failure(ManagedLocalError.transport)) }
            else { self.receive(url: url) }
        }
    }

    private func finish(_ result: Result<(Data, URLResponse), Error>) {
        guard let continuation else { return }
        self.continuation = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        continuation.resume(with: result)
    }
}

final class ManagedLocalSession: Equatable, @unchecked Sendable {
    let id: UUID
    let model: ManagedLocalModel
    private let process: Process
    private let lifetime: Pipe
    private let directory: URL
    private let token: String
    let port: Int
    private let lock = NSLock()
    private var stopped = false
    var displayAddress: String { "http://\(ManagedLocalHTTP.hostname):\(port)" }
    var isRunning: Bool { lock.withLock { !stopped && process.isRunning } }
    static func == (lhs: ManagedLocalSession, rhs: ManagedLocalSession) -> Bool { lhs === rhs }

    init(id: UUID, model: ManagedLocalModel, process: Process, lifetime: Pipe, directory: URL, token: String, port: Int) {
        self.id = id; self.model = model; self.process = process; self.lifetime = lifetime
        self.directory = directory; self.token = token; self.port = port
    }

    func health() async throws -> Bool {
        guard isRunning else { return false }
        var request = URLRequest(url: endpoint("health")); request.timeoutInterval = 1
        let (data, response) = try await ManagedLocalHTTP().data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        guard ManagedLocalHealth.matches(data, session: id, modelSHA256: model.sha256, pid: process.processIdentifier) else {
            throw ManagedLocalError.foreignService
        }
        return isRunning
    }

    func transcribe(body: Data, contentType: String) async throws -> (Data, URLResponse) {
        guard try await health() else { throw ManagedLocalError.notReady }
        var request = URLRequest(url: endpoint("v1/audio/transcriptions"))
        request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 120
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let response = try await ManagedLocalHTTP().data(for: request)
        guard process.isRunning else { throw ManagedLocalError.notReady }
        return response
    }

    private func endpoint(_ path: String) -> URL { URL(string: "\(displayAddress)/\(token)/\(path)")! }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        try? lifetime.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: directory)
    }

    deinit { stop() }
}

@MainActor @Observable
final class ManagedLocalRuntime {
    private final class RetiredSession {
        weak var value: ManagedLocalSession?
        init(_ value: ManagedLocalSession) { self.value = value }
    }
    enum State: Equatable { case idle, starting(String), ready(String), failed(String) }
    private(set) var state: State = .idle
    private(set) var session: ManagedLocalSession?
    @ObservationIgnored private var pending: ManagedLocalSession?
    @ObservationIgnored private var retired: [RetiredSession] = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let helperURL: URL
    @ObservationIgnored private let startupTimeout: TimeInterval
    @ObservationIgnored private let portAllocator: () throws -> Int

    init(helperURL: URL? = nil, startupTimeout: TimeInterval = 30, portAllocator: (() throws -> Int)? = nil) {
        self.helperURL = helperURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/whisper-server")
        self.startupTimeout = max(0, min(30, startupTimeout))
        self.portAllocator = portAllocator ?? Self.availablePort
    }

    func start(model: ManagedLocalModel, beforeCommit: () throws -> Void = {}) async throws -> ManagedLocalSession {
        let generation = UUID(); self.generation = generation
        pending?.stop(); pending = nil
        state = .starting(model.id)
        do {
            let helperURL = self.helperURL
            let validation = Task.detached(priority: .utility) {
                try model.revalidate()
                try Self.verifyHelper(helperURL)
                try ManagedLocalHTTP.validateResolution()
            }
            try await withTaskCancellationHandler { try await validation.value } onCancel: { validation.cancel() }
            for _ in 0..<3 {
                try Task.checkCancellation()
                guard self.generation == generation else { throw CancellationError() }
                let candidate = try launch(model: model)
                pending = candidate
                let deadline = Date().addingTimeInterval(startupTimeout)
                var collision = false
                while candidate.isRunning && Date() < deadline {
                    try Task.checkCancellation()
                    guard self.generation == generation else { candidate.stop(); throw CancellationError() }
                    let healthy: Bool
                    do { healthy = try await candidate.health() }
                    catch ManagedLocalError.foreignService { collision = true; break }
                    catch { healthy = false }
                    if healthy {
                        try Task.checkCancellation()
                        guard self.generation == generation else { candidate.stop(); throw CancellationError() }
                        // No suspension between durable selection and activation. A
                        // failed atomic write leaves the previous session untouched.
                        try beforeCommit()
                        let previous = session
                        session = candidate; pending = nil; state = .ready(model.id)
                        // A provider/request retaining the old session owns its lifetime.
                        // Weak tracking allows explicit shutdown without prematurely
                        // terminating audio conversion or an in-flight HTTP response.
                        retired.removeAll { $0.value == nil }
                        if let previous { retired.append(RetiredSession(previous)) }
                        return candidate
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                candidate.stop()
                if pending?.id == candidate.id { pending = nil }
                guard self.generation == generation else { throw CancellationError() }
                if Date() >= deadline && !collision { throw ManagedLocalError.timedOut }
            }
            throw ManagedLocalError.startupFailed
        } catch {
            if self.generation == generation {
                pending?.stop(); pending = nil
                state = .failed((error as? ManagedLocalError)?.errorDescription ?? "Local model startup was cancelled.")
            }
            throw error
        }
    }

    func stop() {
        generation = UUID(); pending?.stop(); pending = nil
        retired.forEach { $0.value?.stop() }; retired.removeAll()
        session?.stop(); session = nil; state = .idle
    }

    func cancelPending() {
        generation = UUID(); pending?.stop(); pending = nil
        state = session.flatMap { $0.isRunning ? .ready($0.model.id) : nil } ?? .idle
    }

    var protectedModelIDs: Set<String> {
        Set(([session, pending] + retired.map(\.value)).compactMap { value in
            guard let value, value.isRunning else { return nil }
            return value.model.id
        })
    }

    private func launch(model: ManagedLocalModel) throws -> ManagedLocalSession {
        let port = try portAllocator()
        guard (1...65535).contains(port) else { throw ManagedLocalError.startupFailed }
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            throw ManagedLocalError.startupFailed
        }
        let token = random.map { String(format: "%02x", $0) }.joined()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("foil-runtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let process = Process(), lifetime = Pipe(), id = UUID()
        let candidate = ManagedLocalSession(id: id, model: model, process: process, lifetime: lifetime,
            directory: directory, token: token, port: port)
        process.executableURL = helperURL
        process.arguments = ["-m", model.url.path, "--host", "127.0.0.1", "--port", String(port), "--public", directory.path]
        process.environment = ["FOIL_MANAGED_TOKEN": token, "FOIL_SESSION_ID": id.uuidString,
            "FOIL_MODEL_SHA256": model.sha256, "PATH": "/usr/bin:/bin"]
        process.standardInput = lifetime
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session?.id == id else { return }
                self.session = nil; self.state = .failed("The managed local runtime exited.")
            }
        }
        do { try process.run(); try lifetime.fileHandleForReading.close() }
        catch { candidate.stop(); throw ManagedLocalError.startupFailed }
        return candidate
    }

    nonisolated private static func verifyHelper(_ url: URL) throws {
        var code: SecStaticCode?
        guard FileManager.default.isExecutableFile(atPath: url.path),
              SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw ManagedLocalError.invalidRuntime
        }
    }

    private static func availablePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ManagedLocalError.startupFailed }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1")); address.sin_port = 0
        return try withUnsafeMutablePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                var size = socklen_t(MemoryLayout<sockaddr_in>.size)
                guard bind(descriptor, socketAddress, size) == 0,
                      getsockname(descriptor, socketAddress, &size) == 0 else { throw ManagedLocalError.startupFailed }
                return Int(UInt16(bigEndian: pointer.pointee.sin_port))
            }
        }
    }
}
