import CryptoKit
import Darwin
import XCTest
@testable import Foil

final class ManagedLocalRuntimeTests: XCTestCase {
    #if DEBUG
    func testStartupTracePipeNeverEmitsSecretsAndCapsItsOutput() async throws {
        let capture = StartupTraceCapture()
        let trace = ManagedLocalStartupTrace(output: { capture.append($0) })
        let descriptor = dup(trace.pipe.fileHandleForWriting.fileDescriptor)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        let child = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        trace.didLaunch(pid: 1234)
        let secret = String(repeating: "b", count: 64)
        let bytes = "GET /\(secret)/health\nmodel: /private/fixture.bin\n"
            + "FOIL_STARTUP_STAGE model_begin \(secret)\n"
            + String(repeating: "FOIL_STARTUP_STAGE backend_ready\n", count: 60)
        try child.write(contentsOf: Data(bytes.utf8))
        try child.close()
        for _ in 0..<100 where capture.lines.count < 32 {
            try await Task.sleep(for: .milliseconds(10))
        }
        trace.report(.exit(9, 1))
        XCTAssertEqual(capture.lines.count, 32)
        XCTAssertTrue(capture.lines.allSatisfy {
            $0.hasPrefix("[ManagedLocalStartup] pid=1234 elapsed_ms=")
                && ($0.hasSuffix("stage=launched\n") || $0.hasSuffix("stage=backend_ready\n"))
        })
        XCTAssertFalse(capture.lines.joined().contains(secret))
        XCTAssertFalse(capture.lines.joined().contains("/private/"))
    }

    func testStartupTraceDecodesOnlyCompleteAllowlistedStages() {
        var decoder = ManagedLocalStartupTraceDecoder()
        XCTAssertTrue(decoder.consume(Data("FOIL_STARTUP_STA".utf8)).isEmpty)
        XCTAssertEqual(decoder.consume(Data("GE backend_begin\n".utf8)), [.backendBegin])
        for stage in ManagedLocalStartupTraceDecoder.Stage.allCases {
            XCTAssertEqual(decoder.consume(Data("FOIL_STARTUP_STAGE \(stage.rawValue)\n".utf8)), [stage])
        }
    }

    func testStartupTraceDiscardsPathsTokensUnknownAndOversizedLines() {
        var decoder = ManagedLocalStartupTraceDecoder()
        let secret = String(repeating: "a", count: 64)
        let noise = "GET /\(secret)/health\nmodel: /private/fixture.bin\n"
            + "FOIL_STARTUP_STAGE model_begin \(secret)\n"
            + "FOIL_STARTUP_STAGE unknown\n"
            + String(repeating: "x", count: 100_000) + "FOIL_STARTUP_STAGE model_begin\n"
        XCTAssertTrue(decoder.consume(Data(noise.utf8)).isEmpty)
        XCTAssertEqual(decoder.consume(Data("FOIL_STARTUP_STAGE bound\n".utf8)), [.bound])
    }

    #endif

    func testCancelledHashingStopsBeforeAcceptingModel() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        let model = try ManagedLocalModel.verify(url: url, id: "fixture", size: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(try model.revalidate()) { error in XCTAssertTrue(error is CancellationError) }
        }.value
    }

    func testCorruptOrTruncatedModelCannotBeVerified() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        XCTAssertThrowsError(try ManagedLocalModel.verify(url: url, id: "fixture", size: 4,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        XCTAssertThrowsError(try ManagedLocalModel.verify(url: url, id: "fixture", size: 3,
            sha256: String(repeating: "0", count: 64)))
    }

    func testVerifiedModelDetectsReplacementBeforeLaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        let model = try ManagedLocalModel.verify(url: url, id: "fixture", size: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try Data("xyz".utf8).write(to: url)
        XCTAssertThrowsError(try model.revalidate())
    }

    func testForeignHealthCannotProveReadiness() throws {
        let id = UUID()
        let hash = String(repeating: "a", count: 64)
        let foreign = Data("{\"status\":\"ok\"}".utf8)
        XCTAssertFalse(ManagedLocalHealth.matches(foreign, session: id, modelSHA256: hash, pid: 123))
        let exact = try JSONSerialization.data(withJSONObject: ["status": "ok", "service": "foil-whisper",
            "session": id.uuidString, "model_sha256": hash, "pid": 123])
        XCTAssertTrue(ManagedLocalHealth.matches(exact, session: id, modelSHA256: hash, pid: 123))
        XCTAssertFalse(ManagedLocalHealth.matches(exact, session: UUID(), modelSHA256: hash, pid: 123))
        XCTAssertFalse(ManagedLocalHealth.matches(exact, session: id, modelSHA256: hash, pid: 124))
        XCTAssertFalse(ManagedLocalHealth.matches(exact, session: id, modelSHA256: String(repeating: "b", count: 64), pid: 123))
    }
}

#if DEBUG
private final class StartupTraceCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var lines: [String] { lock.withLock { storage } }
    func append(_ line: String) { lock.withLock { storage.append(line) } }
}
#endif
