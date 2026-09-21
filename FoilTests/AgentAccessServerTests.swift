import Darwin
import XCTest
@testable import Foil

final class AgentAccessServerTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        // AF_UNIX paths are capped at 104 bytes on macOS. XCTest's default
        // temporary directory can already exceed that before the fixture name.
        temporaryRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("foil-aa-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }

    func testBrandPathsAreIsolatedAndSocketPathLimitIsEnforced() throws {
        let production = AgentAccessPaths(applicationSupportRoot: temporaryRoot, directoryName: "Foil")
        let development = AgentAccessPaths(applicationSupportRoot: temporaryRoot, directoryName: "Foil Dev")

        XCTAssertNotEqual(production.socketURL, development.socketURL)
        XCTAssertTrue(production.socketURL.path.hasSuffix("Foil/agent-v1.sock"))
        XCTAssertTrue(development.socketURL.path.hasSuffix("Foil Dev/agent-v1.sock"))
        XCTAssertNoThrow(try production.validateSocketPath())

        let escaping = AgentAccessPaths(applicationSupportRoot: temporaryRoot, directoryName: "../escape")
        XCTAssertThrowsError(try escaping.validateSocketPath()) { error in
            XCTAssertEqual(error as? AgentAccessPathError, .unsafeLayout)
        }

        let longName = String(repeating: "x", count: AgentAccessPaths.maximumSocketPathBytes + 10)
        let tooLong = AgentAccessPaths(applicationSupportRoot: temporaryRoot, directoryName: longName)
        XCTAssertThrowsError(try tooLong.validateSocketPath()) { error in
            guard case let AgentAccessPathError.socketPathTooLong(actual, maximum) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertGreaterThan(actual, maximum)
        }
    }

    func testBootstrapCommandFailsWithinDocumentedBoundWhenSocketIsAbsent() throws {
        let missing = temporaryRoot.appendingPathComponent("missing.sock")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--silent", "--show-error", "--connect-timeout", "1", "--max-time", "12",
            "--retry", "10", "--retry-all-errors", "--retry-delay", "1",
            "--unix-socket", missing.path, "http://foil/v1/instructions"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let started = Date()

        try process.run()
        process.waitUntilExit()

        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 12.75)
    }

    func testPeerAndStaleSocketOwnershipDecisionsAreFailClosed() {
        let currentUser = getuid()
        XCTAssertTrue(AgentAccessServer.isAllowedPeer(
            effectiveUserID: currentUser,
            currentEffectiveUserID: currentUser
        ))
        XCTAssertFalse(AgentAccessServer.isAllowedPeer(
            effectiveUserID: currentUser &+ 1,
            currentEffectiveUserID: currentUser
        ))
        XCTAssertTrue(AgentAccessServer.isRemovableStaleSocket(
            mode: mode_t(S_IFSOCK | 0o600),
            ownerID: currentUser,
            currentUserID: currentUser
        ))
        XCTAssertFalse(AgentAccessServer.isRemovableStaleSocket(
            mode: mode_t(S_IFSOCK | 0o600),
            ownerID: currentUser &+ 1,
            currentUserID: currentUser
        ))
        XCTAssertFalse(AgentAccessServer.isRemovableStaleSocket(
            mode: mode_t(S_IFREG | 0o600),
            ownerID: currentUser,
            currentUserID: currentUser
        ))
    }

    func testLiveCurlReadsInstructionsOverOwnerOnlyUnixSocket() throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }
        try fixture.server.start()

        var socketInfo = stat()
        XCTAssertEqual(lstat(fixture.paths.socketURL.path, &socketInfo), 0)
        XCTAssertEqual(socketInfo.st_uid, getuid())
        XCTAssertEqual(socketInfo.st_mode & 0o777, 0o600)
        var directoryInfo = stat()
        XCTAssertEqual(lstat(fixture.paths.supportDirectory.path, &directoryInfo), 0)
        XCTAssertEqual(directoryInfo.st_mode & 0o777, 0o700)

        let result = try runCurl(socketURL: fixture.paths.socketURL, path: "/v1/instructions")
        XCTAssertEqual(result.status, 0, result.stderr)
        let decoded = try JSONDecoder().decode(AgentAccessInstructionsResponse.self, from: result.stdout)
        XCTAssertEqual(decoded.availableOperations.count, 5)
        XCTAssertTrue(decoded.bootstrapCommand.contains(fixture.paths.socketURL.path))
        let contract = try runCurl(socketURL: fixture.paths.socketURL, path: decoded.openAPIPath)
        XCTAssertEqual(contract.status, 0, contract.stderr)
        let openAPI = try XCTUnwrap(try JSONSerialization.jsonObject(with: contract.stdout) as? [String: Any])
        XCTAssertNotNil((openAPI["paths"] as? [String: Any])?["/v1/vocabulary/preview"])
    }

    func testSecondServerCannotReplaceActiveSocket() throws {
        let first = try makeServer()
        let second = try makeServer(paths: first.paths)
        defer {
            second.server.stop()
            first.server.stop()
        }
        try first.server.start()

        XCTAssertThrowsError(try second.server.start()) { error in
            XCTAssertEqual(error as? AgentAccessServerError, .lockUnavailable)
        }
        let result = try runCurl(socketURL: first.paths.socketURL, path: "/v1/instructions")
        XCTAssertEqual(result.status, 0, result.stderr)
    }

    func testOwnedStaleSocketIsReplacedAfterLockIsAvailable() throws {
        let paths = AgentAccessPaths(applicationSupportRoot: temporaryRoot, directoryName: "Foil")
        try FileManager.default.createDirectory(at: paths.supportDirectory, withIntermediateDirectories: true)
        try createStaleSocket(at: paths.socketURL)
        var before = stat()
        XCTAssertEqual(lstat(paths.socketURL.path, &before), 0)

        let fixture = try makeServer(paths: paths)
        defer { fixture.server.stop() }
        try fixture.server.start()
        var after = stat()
        XCTAssertEqual(lstat(paths.socketURL.path, &after), 0)
        XCTAssertNotEqual(before.st_ino, after.st_ino)

        let result = try runCurl(socketURL: paths.socketURL, path: "/v1/openapi.json")
        XCTAssertEqual(result.status, 0, result.stderr)
    }

    func testRegularFileAtSocketPathIsLeftUntouched() throws {
        let paths = AgentAccessPaths(applicationSupportRoot: temporaryRoot, directoryName: "Foil")
        try FileManager.default.createDirectory(at: paths.supportDirectory, withIntermediateDirectories: true)
        let sentinel = Data("do-not-delete".utf8)
        try sentinel.write(to: paths.socketURL)
        let fixture = try makeServer(paths: paths)

        XCTAssertThrowsError(try fixture.server.start()) { error in
            XCTAssertEqual(error as? AgentAccessServerError, .unsafeExistingSocket)
        }
        XCTAssertEqual(try Data(contentsOf: paths.socketURL), sentinel)
    }

    func testSymlinkAtSocketPathIsLeftUntouched() throws {
        let paths = AgentAccessPaths(applicationSupportRoot: temporaryRoot, directoryName: "Foil")
        try FileManager.default.createDirectory(at: paths.supportDirectory, withIntermediateDirectories: true)
        let target = temporaryRoot.appendingPathComponent("target")
        try Data("sentinel".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: paths.socketURL, withDestinationURL: target)
        let fixture = try makeServer(paths: paths)

        XCTAssertThrowsError(try fixture.server.start()) { error in
            XCTAssertEqual(error as? AgentAccessServerError, .unsafeExistingSocket)
        }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: paths.socketURL.path), target.path)
        XCTAssertEqual(try Data(contentsOf: target), Data("sentinel".utf8))
    }

    func testStopClosesPartialConnectionAndRemovesOnlyOwnedSocket() throws {
        let fixture = try makeServer()
        try fixture.server.start()
        let client = try connect(to: fixture.paths.socketURL)
        XCTAssertGreaterThanOrEqual(Darwin.send(client, "GET ", 4, 0), 0)

        fixture.server.stop()

        var byte: UInt8 = 0
        let count = Darwin.recv(client, &byte, 1, 0)
        XCTAssertLessThanOrEqual(count, 0)
        Darwin.close(client)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.socketURL.path))
    }

    func testStopDuringHandlerPreventsLateResponseAndAllowsCleanRestart() throws {
        let paths = AgentAccessPaths(applicationSupportRoot: temporaryRoot, directoryName: "Foil")
        let handlerEntered = DispatchSemaphore(value: 0)
        let releaseFirstHandler = DispatchSemaphore(value: 0)
        let callLock = NSLock()
        var callCount = 0
        let server = AgentAccessServer(paths: paths) { request in
            let call = callLock.withLock { () -> Int in
                callCount += 1
                return callCount
            }
            if call == 1 {
                handlerEntered.signal()
                _ = releaseFirstHandler.wait(timeout: .now() + 3)
            }
            return AgentAccessHTTPResponse(
                status: 200,
                reason: "OK",
                headers: ["content-type": "application/json"],
                body: Data(#"{"path":"\#(request.path)"}"#.utf8)
            )
        }
        defer {
            releaseFirstHandler.signal()
            server.stop()
        }
        try server.start()
        let oldClient = try connect(to: paths.socketURL)
        defer { Darwin.close(oldClient) }
        let request = "GET /v1/instructions HTTP/1.1\r\nHost: foil\r\n\r\n"
        XCTAssertEqual(Darwin.send(oldClient, request, request.utf8.count, 0), request.utf8.count)
        XCTAssertEqual(handlerEntered.wait(timeout: .now() + 2), .success)

        server.stop()
        var byte: UInt8 = 0
        XCTAssertLessThanOrEqual(Darwin.recv(oldClient, &byte, 1, 0), 0)

        try server.start()
        let restarted = try runCurl(socketURL: paths.socketURL, path: "/v1/openapi.json")
        XCTAssertEqual(restarted.status, 0, restarted.stderr)
        XCTAssertTrue(String(decoding: restarted.stdout, as: UTF8.self).contains("/v1/openapi.json"))

        releaseFirstHandler.signal()
        usleep(50_000)
        XCTAssertTrue(server.isRunning)
        XCTAssertEqual(callLock.withLock { callCount }, 2)
    }

    func testStopLeavesReplacementAtSocketPathUntouched() throws {
        let fixture = try makeServer()
        try fixture.server.start()
        let displacedSocket = temporaryRoot.appendingPathComponent("displaced.sock")
        try FileManager.default.moveItem(at: fixture.paths.socketURL, to: displacedSocket)
        let sentinel = Data("replacement".utf8)
        try sentinel.write(to: fixture.paths.socketURL)

        fixture.server.stop()

        XCTAssertEqual(try Data(contentsOf: fixture.paths.socketURL), sentinel)
        try FileManager.default.removeItem(at: displacedSocket)
    }

    func testDisconnectedPartialClientCannotTerminateServer() throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }
        try fixture.server.start()
        let client = try connect(to: fixture.paths.socketURL)
        XCTAssertGreaterThanOrEqual(Darwin.send(client, "GET ", 4, 0), 0)
        _ = shutdown(client, SHUT_RDWR)
        Darwin.close(client)
        usleep(100_000)

        let result = try runCurl(socketURL: fixture.paths.socketURL, path: "/v1/instructions")
        XCTAssertEqual(result.status, 0, result.stderr)
    }

    func testDisconnectedCompleteClientCannotTerminateServerDuringResponse() throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }
        try fixture.server.start()
        let client = try connect(to: fixture.paths.socketURL)
        let request = "GET /v1/instructions HTTP/1.1\r\nHost: foil\r\n\r\n"
        XCTAssertEqual(Darwin.send(client, request, request.utf8.count, 0), request.utf8.count)
        _ = shutdown(client, SHUT_RDWR)
        Darwin.close(client)
        usleep(100_000)

        let result = try runCurl(socketURL: fixture.paths.socketURL, path: "/v1/instructions")
        XCTAssertEqual(result.status, 0, result.stderr)
    }

    func testTwentyConcurrentClientsCompleteWithoutBlockingTheServer() throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }
        try fixture.server.start()
        let group = DispatchGroup()
        let lock = NSLock()
        var failures: [String] = []

        for index in 0..<20 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                do {
                    let result = try self.runCurl(
                        socketURL: fixture.paths.socketURL,
                        path: index.isMultiple(of: 2) ? "/v1/instructions" : "/v1/openapi.json"
                    )
                    if result.status != 0 || result.stdout.isEmpty {
                        lock.withLock { failures.append("client \(index): \(result.status) \(result.stderr)") }
                    }
                } catch {
                    lock.withLock { failures.append("client \(index): \(error)") }
                }
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(failures, [])
        XCTAssertTrue(fixture.server.isRunning)
    }

    func testDiagnosticsRecordMetadataWithoutRequestSecrets() throws {
        let secret = "SECRET_TRANSCRIPT_KEY_PATH_PROVIDER_SOURCE"
        let logURL = temporaryRoot.appendingPathComponent("diagnostics.log")
        DiagnosticLog.logURLOverride = logURL
        DiagnosticLog.isEnabledOverride = true
        DiagnosticLog.clearForTesting()
        defer {
            DiagnosticLog.clearForTesting()
            DiagnosticLog.logURLOverride = nil
            DiagnosticLog.isEnabledOverride = nil
        }
        let fixture = try makeServer()
        defer { fixture.server.stop() }
        try fixture.server.start()
        let client = try connect(to: fixture.paths.socketURL)
        defer { Darwin.close(client) }
        let body = #"{"corrections":[{"spoken_forms":["SECRET_TRANSCRIPT_KEY_PATH_PROVIDER_SOURCE"],"replacement":"safe"}]}"#
        let request = "POST /v1/vocabulary/preview HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nX-Foil-Request-ID: \(secret)\r\n\r\n\(body)"
        XCTAssertEqual(Darwin.send(client, request, request.utf8.count, 0), request.utf8.count)
        var response = [UInt8](repeating: 0, count: 16_384)
        XCTAssertGreaterThan(Darwin.recv(client, &response, response.count, 0), 0)

        let diagnostics = DiagnosticLog.recentLines(limit: 20).joined(separator: "\n")
        XCTAssertTrue(diagnostics.contains("route=vocabulary_preview"), diagnostics)
        XCTAssertTrue(diagnostics.contains("status=200"), diagnostics)
        XCTAssertFalse(diagnostics.contains(secret), diagnostics)
    }

    func testIncompleteClientReceivesBoundedTimeout() throws {
        let limits = AgentAccessLimits(
            maximumHeaderBytes: 16 * 1024,
            maximumBodyBytes: 64 * 1024,
            maximumCorrectionPairs: 50,
            maximumSpokenFormsPerPair: 10,
            maximumPhraseScalars: 256,
            requestDeadlineSeconds: 1
        )
        let fixture = try makeServer(limits: limits)
        defer { fixture.server.stop() }
        try fixture.server.start()
        let client = try connect(to: fixture.paths.socketURL)
        defer { Darwin.close(client) }
        XCTAssertGreaterThanOrEqual(Darwin.send(client, "GET ", 4, 0), 0)

        var response = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.recv(client, &response, response.count, 0)
        XCTAssertGreaterThan(count, 0)
        let text = String(decoding: response.prefix(Int(count)), as: UTF8.self)
        XCTAssertTrue(text.contains("408 Request Timeout"), text)
        XCTAssertTrue(text.contains("request_timeout"), text)
    }

    func testSlowHeaderCannotExtendAbsoluteDeadline() throws {
        let limits = AgentAccessLimits(
            maximumHeaderBytes: 16 * 1024,
            maximumBodyBytes: 64 * 1024,
            maximumCorrectionPairs: 50,
            maximumSpokenFormsPerPair: 10,
            maximumPhraseScalars: 256,
            requestDeadlineSeconds: 1
        )
        let fixture = try makeServer(limits: limits)
        defer { fixture.server.stop() }
        try fixture.server.start()
        let client = try connect(to: fixture.paths.socketURL)
        defer { Darwin.close(client) }
        let started = Date()
        XCTAssertGreaterThanOrEqual(Darwin.send(client, "G", 1, 0), 0)
        usleep(600_000)
        XCTAssertGreaterThanOrEqual(Darwin.send(client, "E", 1, 0), 0)

        var response = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.recv(client, &response, response.count, 0)
        XCTAssertGreaterThan(count, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.45)
        let text = String(decoding: response.prefix(Int(count)), as: UTF8.self)
        XCTAssertTrue(text.contains("408 Request Timeout"), text)
    }

    private func makeServer(
        paths: AgentAccessPaths? = nil,
        limits: AgentAccessLimits = .standard
    ) throws -> (server: AgentAccessServer, paths: AgentAccessPaths) {
        let resolvedPaths = paths ?? AgentAccessPaths(
            applicationSupportRoot: temporaryRoot,
            directoryName: "Foil"
        )
        let router = AgentAccessContractRouter(
            socketPath: resolvedPaths.socketURL.path,
            openAPIDocument: try openAPIData(),
            limits: limits
        )
        let server = AgentAccessServer(paths: resolvedPaths, limits: limits) { request in
            router.response(to: request)
        }
        return (server, resolvedPaths)
    }

    private func openAPIData() throws -> Data {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Foil/Resources/AgentAccessOpenAPI.json")
        return try Data(contentsOf: fileURL)
    }

    private func runCurl(socketURL: URL, path: String) throws -> (status: Int32, stdout: Data, stderr: String) {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--silent",
            "--show-error",
            "--max-time", "3",
            "--unix-socket", socketURL.path,
            "http://foil\(path)"
        ]
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            output.fileHandleForReading.readDataToEndOfFile(),
            String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func createStaleSocket(at url: URL) throws {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(fd) }
        var address = try socketAddress(for: url)
        let length = socketAddressLength(pathByteCount: url.path.utf8.count)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, length)
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private func connect(to url: URL) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var address = try socketAddress(for: url)
        let length = socketAddressLength(pathByteCount: url.path.utf8.count)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, length)
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return fd
    }

    private func socketAddress(for url: URL) throws -> sockaddr_un {
        let pathBytes = Array(url.path.utf8)
        guard pathBytes.count <= AgentAccessPaths.maximumSocketPathBytes else {
            throw AgentAccessPathError.socketPathTooLong(
                actualBytes: pathBytes.count,
                maximumBytes: AgentAccessPaths.maximumSocketPathBytes
            )
        }
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
}
