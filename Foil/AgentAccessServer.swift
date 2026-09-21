import Darwin
import Foundation

enum AgentAccessServerError: Error, Equatable, LocalizedError {
    case alreadyRunning
    case unsafeSupportDirectory
    case unsafeLockFile
    case lockUnavailable
    case unsafeExistingSocket
    case systemCall(name: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "Agent Access is already running."
        case .unsafeSupportDirectory:
            "Agent Access requires an owner-only Application Support directory."
        case .unsafeLockFile:
            "Agent Access found an unsafe lock file and left it unchanged."
        case .lockUnavailable:
            "Another Agent Access server is already using this socket."
        case .unsafeExistingSocket:
            "Agent Access found an unsafe item at its socket path and left it unchanged."
        case let .systemCall(name, code):
            "Agent Access could not \(name) (errno \(code))."
        }
    }
}

final class AgentAccessServer {
    typealias Handler = (AgentAccessHTTPRequest) -> AgentAccessHTTPResponse

    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    let paths: AgentAccessPaths
    let limits: AgentAccessLimits

    private let parser: AgentAccessHTTPRequestParser
    private let handler: Handler
    private let acceptQueue: DispatchQueue
    private let connectionQueue: DispatchQueue
    private let stateLock = NSLock()

    private var listenerFD: Int32 = -1
    private var ownershipLockFD: Int32 = -1
    private var socketIdentity: FileIdentity?
    private var activeConnections = Set<Int32>()
    private var generation = UUID()

    init(
        paths: AgentAccessPaths,
        limits: AgentAccessLimits = .standard,
        handler: @escaping Handler
    ) {
        self.paths = paths
        self.limits = limits
        parser = AgentAccessHTTPRequestParser(limits: limits)
        self.handler = handler
        acceptQueue = DispatchQueue(label: "com.neonwatty.Foil.AgentAccess.accept")
        connectionQueue = DispatchQueue(
            label: "com.neonwatty.Foil.AgentAccess.connections",
            attributes: .concurrent
        )
    }

    var isRunning: Bool {
        stateLock.withLock { listenerFD >= 0 }
    }

    static func isAllowedPeer(effectiveUserID: uid_t, currentEffectiveUserID: uid_t) -> Bool {
        effectiveUserID == currentEffectiveUserID
    }

    static func isRemovableStaleSocket(mode: mode_t, ownerID: uid_t, currentUserID: uid_t) -> Bool {
        mode & mode_t(S_IFMT) == S_IFSOCK && ownerID == currentUserID
    }

    func start() throws {
        try paths.validateSocketPath()
        try prepareSupportDirectory()

        stateLock.lock()
        if listenerFD >= 0 {
            stateLock.unlock()
            throw AgentAccessServerError.alreadyRunning
        }
        stateLock.unlock()

        let acquiredLockFD = try acquireOwnershipLock()
        var newListenerFD: Int32 = -1
        do {
            try removeOwnedStaleSocket()
            newListenerFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard newListenerFD >= 0 else {
                throw systemError("create its Unix socket")
            }
            _ = fcntl(newListenerFD, F_SETFD, FD_CLOEXEC)

            var address = try socketAddress()
            let addressLength = socketAddressLength(pathByteCount: paths.socketURL.path.utf8.count)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(newListenerFD, $0, addressLength)
                }
            }
            guard bindResult == 0 else { throw systemError("bind its Unix socket") }
            guard chmod(paths.socketURL.path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
                throw systemError("secure its Unix socket")
            }
            guard Darwin.listen(newListenerFD, 32) == 0 else {
                throw systemError("listen on its Unix socket")
            }
            let identity = try fileIdentity(at: paths.socketURL, expectedType: S_IFSOCK)
            let newGeneration = UUID()

            stateLock.withLock {
                listenerFD = newListenerFD
                ownershipLockFD = acquiredLockFD
                socketIdentity = identity
                generation = newGeneration
            }
            DiagnosticLog.write("AgentAccess: server started transport=unix")
            acceptQueue.async { [weak self] in
                self?.acceptConnections(listenerFD: newListenerFD, generation: newGeneration)
            }
        } catch {
            if newListenerFD >= 0 { Darwin.close(newListenerFD) }
            removeSocketIfOwnedByCurrentUser()
            _ = flock(acquiredLockFD, LOCK_UN)
            Darwin.close(acquiredLockFD)
            throw error
        }
    }

    func stop() {
        let captured: (listener: Int32, lock: Int32, connections: [Int32], identity: FileIdentity?) = stateLock.withLock {
            let value = (
                listener: listenerFD,
                lock: ownershipLockFD,
                connections: Array(activeConnections),
                identity: socketIdentity
            )
            listenerFD = -1
            ownershipLockFD = -1
            activeConnections.removeAll()
            socketIdentity = nil
            generation = UUID()
            return value
        }

        guard captured.listener >= 0 || captured.lock >= 0 else { return }
        if captured.listener >= 0 {
            _ = shutdown(captured.listener, SHUT_RDWR)
            Darwin.close(captured.listener)
        }
        for connection in captured.connections {
            _ = shutdown(connection, SHUT_RDWR)
            Darwin.close(connection)
        }
        removeSocket(ifIdentityMatches: captured.identity)
        if captured.lock >= 0 {
            _ = flock(captured.lock, LOCK_UN)
            Darwin.close(captured.lock)
        }
        DiagnosticLog.write("AgentAccess: server stopped")
    }

    deinit {
        stop()
    }

    private func prepareSupportDirectory() throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: paths.supportDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        } catch {
            throw systemError("create its Application Support directory")
        }
        var info = stat()
        guard lstat(paths.supportDirectory.path, &info) == 0,
              fileType(info.st_mode) == S_IFDIR,
              info.st_uid == getuid(),
              chmod(paths.supportDirectory.path, 0o700) == 0 else {
            throw AgentAccessServerError.unsafeSupportDirectory
        }
    }

    private func acquireOwnershipLock() throws -> Int32 {
        let flags = O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW
        let fd = Darwin.open(paths.lockURL.path, flags, mode_t(S_IRUSR | S_IWUSR))
        guard fd >= 0 else {
            if errno == ELOOP { throw AgentAccessServerError.unsafeLockFile }
            throw systemError("open its ownership lock")
        }
        var info = stat()
        guard fstat(fd, &info) == 0,
              fileType(info.st_mode) == S_IFREG,
              info.st_uid == getuid(),
              fchmod(fd, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            Darwin.close(fd)
            throw AgentAccessServerError.unsafeLockFile
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw AgentAccessServerError.lockUnavailable
        }
        return fd
    }

    private func removeOwnedStaleSocket() throws {
        var info = stat()
        let result = lstat(paths.socketURL.path, &info)
        if result != 0 {
            guard errno == ENOENT else { throw systemError("inspect its Unix socket") }
            return
        }
        guard Self.isRemovableStaleSocket(
            mode: info.st_mode,
            ownerID: info.st_uid,
            currentUserID: getuid()
        ) else {
            throw AgentAccessServerError.unsafeExistingSocket
        }
        guard unlink(paths.socketURL.path) == 0 else {
            throw systemError("remove its stale Unix socket")
        }
    }

    private func removeSocketIfOwnedByCurrentUser() {
        var info = stat()
        guard lstat(paths.socketURL.path, &info) == 0,
              fileType(info.st_mode) == S_IFSOCK,
              info.st_uid == getuid() else { return }
        _ = unlink(paths.socketURL.path)
    }

    private func removeSocket(ifIdentityMatches expected: FileIdentity?) {
        guard let expected,
              let actual = try? fileIdentity(at: paths.socketURL, expectedType: S_IFSOCK),
              actual == expected else { return }
        _ = unlink(paths.socketURL.path)
    }

    private func fileIdentity(at url: URL, expectedType: mode_t) throws -> FileIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              fileType(info.st_mode) == expectedType,
              info.st_uid == getuid() else {
            throw AgentAccessServerError.unsafeExistingSocket
        }
        return FileIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private func socketAddress() throws -> sockaddr_un {
        try paths.validateSocketPath()
        let pathBytes = Array(paths.socketURL.path.utf8)
        var address = sockaddr_un()
        address.sun_len = UInt8(socketAddressLength(pathByteCount: pathBytes.count))
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: pathBytes)
        }
        return address
    }

    private func socketAddressLength(pathByteCount: Int) -> socklen_t {
        let offset = MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path)!
        return socklen_t(offset + pathByteCount + 1)
    }

    private func acceptConnections(listenerFD: Int32, generation expectedGeneration: UUID) {
        while stateLock.withLock({ self.listenerFD == listenerFD && generation == expectedGeneration }) {
            let connection = Darwin.accept(listenerFD, nil, nil)
            if connection < 0 {
                if errno == EINTR { continue }
                break
            }
            _ = fcntl(connection, F_SETFD, FD_CLOEXEC)
            guard validatePeer(connection) else {
                Darwin.close(connection)
                continue
            }
            let accepted = stateLock.withLock { () -> Bool in
                guard self.listenerFD == listenerFD, generation == expectedGeneration else { return false }
                activeConnections.insert(connection)
                return true
            }
            guard accepted else {
                Darwin.close(connection)
                continue
            }
            connectionQueue.async { [weak self] in
                self?.serve(connection: connection, generation: expectedGeneration)
            }
        }
    }

    private func validatePeer(_ connection: Int32) -> Bool {
        var effectiveUserID: uid_t = 0
        var effectiveGroupID: gid_t = 0
        return getpeereid(connection, &effectiveUserID, &effectiveGroupID) == 0
            && Self.isAllowedPeer(
                effectiveUserID: effectiveUserID,
                currentEffectiveUserID: geteuid()
            )
    }

    private func serve(connection: Int32, generation expectedGeneration: UUID) {
        defer {
            let shouldClose = stateLock.withLock { activeConnections.remove(connection) != nil }
            if shouldClose { Darwin.close(connection) }
        }
        configureSendSafety(on: connection)
        var received = Data()
        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(max(1, limits.requestDeadlineSeconds)) * 1_000_000_000

        while stateLock.withLock({ generation == expectedGeneration && activeConnections.contains(connection) }) {
            switch parser.parse(received) {
            case let .complete(request):
                send(handler(request), to: connection)
                return
            case let .failure(error):
                send(parseErrorResponse(error), to: connection)
                return
            case .incomplete:
                break
            }

            guard configureReceiveDeadline(on: connection, deadline: deadline) else {
                sendTimeout(to: connection)
                return
            }

            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.recv(connection, &buffer, buffer.count, 0)
            if count > 0 {
                received.append(buffer, count: count)
                continue
            }
            if count == 0 {
                return
            }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                sendTimeout(to: connection)
            }
            return
        }
    }

    private func configureSendSafety(on connection: Int32) {
        var noSignal: Int32 = 1
        _ = setsockopt(
            connection,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )
        var timeout = timeval(tv_sec: limits.requestDeadlineSeconds, tv_usec: 0)
        withUnsafePointer(to: &timeout) { pointer in
            _ = setsockopt(
                connection,
                SOL_SOCKET,
                SO_SNDTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }
    }

    private func configureReceiveDeadline(on connection: Int32, deadline: UInt64) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { return false }
        let remaining = deadline - now
        var timeout = timeval(
            tv_sec: Int(remaining / 1_000_000_000),
            tv_usec: Int32(max(1, (remaining % 1_000_000_000) / 1_000))
        )
        return withUnsafePointer(to: &timeout) { pointer in
            setsockopt(
                connection,
                SOL_SOCKET,
                SO_RCVTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.size)
            ) == 0
        }
    }

    private func sendTimeout(to connection: Int32) {
        let timeout = AgentAccessHTTPError(
            status: 408,
            reason: "Request Timeout",
            code: "request_timeout",
            message: "The request did not complete before the Agent Access deadline."
        )
        send(parseErrorResponse(timeout), to: connection)
    }

    private func send(_ response: AgentAccessHTTPResponse, to connection: Int32) {
        let data = response.serialized()
        data.withUnsafeBytes { rawBuffer in
            guard var base = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = Darwin.send(connection, base, remaining, MSG_NOSIGNAL)
                if written > 0 {
                    remaining -= written
                    base = base.advanced(by: written)
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }

    private func parseErrorResponse(_ error: AgentAccessHTTPError) -> AgentAccessHTTPResponse {
        let requestID = UUID().uuidString.lowercased()
        let value = AgentAccessErrorBody(requestID: requestID, code: error.code, message: error.message)
        return (try? AgentAccessHTTPResponse.json(
            status: error.status,
            reason: error.reason,
            requestID: requestID,
            value: value
        )) ?? AgentAccessHTTPResponse(status: error.status, reason: error.reason, headers: [:], body: Data())
    }

    private func fileType(_ mode: mode_t) -> mode_t {
        mode & mode_t(S_IFMT)
    }

    private func systemError(_ operation: String) -> AgentAccessServerError {
        AgentAccessServerError.systemCall(name: operation, code: errno)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
