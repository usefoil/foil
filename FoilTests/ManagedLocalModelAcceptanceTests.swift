import AVFAudio
import XCTest
@testable import Foil

@MainActor
final class ManagedLocalModelAcceptanceTests: XCTestCase {
    func testProductionInstallSwitchAndOfflineReconstruction() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let scenario = environment["FOIL_MODELS_SCENARIO"],
              let rootPath = environment["FOIL_MODELS_STATE_ROOT"],
              let appPath = environment["FOIL_MODELS_APP"] else {
            throw XCTSkip("Run scripts/test-managed-local-models.sh for real network/offline acceptance")
        }
        let root = URL(fileURLWithPath: rootPath)
        let runtime = ManagedLocalRuntime(helperURL: URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents/Helpers/whisper-server"))
        defer { runtime.stop() }
        let configuration = URLSessionConfiguration.ephemeral
        if scenario == "offline-relaunch" { configuration.protocolClasses = [OfflineModelNetworkTrap.self] }
        let store = try ManagedLocalModelStore(root: root, configuration: configuration)
        let coordinator = ManagedLocalModelCoordinator(runtime: runtime, store: store)
        var transcripts: [String] = []
        var writeFailureCode: Int?
        var overlappingRequestFinished = false
        var retiredChildExited = false
        var recoveredPromotedModel = false
        if scenario == "clean-install-switch" {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "Clean installation must begin with absent app-owned storage")
            try await coordinator.refresh()
            XCTAssertTrue(coordinator.installed.isEmpty)
            XCTAssertNil(coordinator.selectedID)
            try await coordinator.installAndSelect("base.en")
            XCTAssertEqual(coordinator.activeID, "base.en")
            transcripts.append(try await transcript(session: try XCTUnwrap(runtime.session), root: root))
            // Download first so the overlap covers candidate activation, not a
            // race between download duration and a short transcription.
            _ = try await store.install("base") { _ in }
            let speech = root.appendingPathComponent("overlap.aiff")
            try makeSpeech(at: speech, repetitions: 180)
            weak var original = runtime.session
            let originalPort = try XCTUnwrap(original).port
            let originalPID = try listenerPID(port: originalPort)
            var finished = false
            var outstanding: Task<String, Error>? = Task { [session = try XCTUnwrap(runtime.session)] in
                defer { finished = true }
                return try await TranscriptionService(provider: .managedLocal(session: session))
                    .transcribe(audioFileURL: speech, apiKey: nil, model: "whisper-1")
            }
            // Observe a sustained real connection after the short health request.
            let connectionDeadline = Date().addingTimeInterval(15)
            var established = false
            while !finished, Date() < connectionDeadline {
                try await Task.sleep(for: .milliseconds(200))
                if hasConnection(port: originalPort, state: "ESTABLISHED") {
                    try await Task.sleep(for: .milliseconds(200))
                    if hasConnection(port: originalPort, state: "ESTABLISHED") { established = true; break }
                }
            }
            XCTAssertTrue(established, "Real transcription connection must be outstanding before switching")
            XCTAssertFalse(finished)
            try await coordinator.installAndSelect("base")
            XCTAssertEqual(coordinator.activeID, "base")
            XCTAssertEqual(coordinator.selectedID, "base")
            XCTAssertEqual(Set(coordinator.installed.map(\.id)), ["base", "base.en"])
            XCTAssertFalse(finished, "The transcription must deliberately overlap successful activation")
            XCTAssertNotNil(original, "The outstanding request must lease its original session")
            do { try await coordinator.remove("base.en"); XCTFail("Retained session file was removed") }
            catch { XCTAssertEqual(error as? ManagedLocalModelStore.Failure, .unavailable) }
            transcripts.append(try await XCTUnwrap(outstanding).value)
            overlappingRequestFinished = finished
            outstanding = nil
            let retirementDeadline = Date().addingTimeInterval(5)
            while Date() < retirementDeadline,
                  original != nil || kill(originalPID, 0) == 0 {
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertNil(original, "The completed request must release the final lease")
            retiredChildExited = kill(originalPID, 0) == -1 && errno == ESRCH
            XCTAssertTrue(retiredChildExited, "The previous child must retire after lease release")
            XCTAssertFalse(runtime.protectedModelIDs.contains("base.en"))
            transcripts.append(try await transcript(session: try XCTUnwrap(runtime.session), root: root))
            let previous = try XCTUnwrap(runtime.session)
            let failedSwitch = Task { try await coordinator.installAndSelect("base.en") }
            let deadline = Date().addingTimeInterval(10)
            while coordinator.state != .starting("base.en"), Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard coordinator.state == .starting("base.en") else {
                failedSwitch.cancel(); _ = try? await failedSwitch.value
                return XCTFail("Candidate did not reach the pre-commit startup boundary")
            }
            // Deny an actual atomic metadata write after candidate preparation
            // began. No fake persistence implementation is involved.
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            do {
                defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
                do { try await failedSwitch.value; XCTFail("Read-only store allowed a selection commit") }
                catch {
                    XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain,
                        "The candidate must reach a real filesystem write failure")
                    writeFailureCode = (error as NSError).code
                }
            }
            XCTAssertEqual(runtime.session?.id, previous.id)
            XCTAssertEqual(coordinator.selectedID, "base")
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("inventory.json"))) as! [String: Any]
            XCTAssertEqual(saved["selectedID"] as? String, "base")
            transcripts.append(try await transcript(session: previous, root: root))
            try await coordinator.remove("base.en")
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.installationURL(try store.catalog.model("base.en")).path))
            let durableBeforeInterruption = try Data(contentsOf: root.appendingPathComponent("inventory.json"))
            // Exercise production download, digest verification and promotion;
            // inject only deterministic ENOSPC at the subsequent atomic write.
            let interruptedStore = try ManagedLocalModelStore(root: root, atomicWrite: { data, url in
                if url.lastPathComponent == "inventory.json" {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
                }
                try data.write(to: url, options: .atomic)
            })
            do { _ = try await interruptedStore.install("base.en") { _ in }; XCTFail("Post-promotion inventory failure was hidden") }
            catch { XCTAssertEqual(error as? ManagedLocalModelStore.Failure, .insufficientSpace) }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("inventory.json")), durableBeforeInterruption)
            let restartedStore = try ManagedLocalModelStore(root: root)
            let recovered = try await restartedStore.reconstruct()
            XCTAssertEqual(recovered.selectedID, "base")
            XCTAssertEqual(Set(recovered.installed.map(\.id)), ["base", "base.en"])
            XCTAssertFalse(recovered.recovery.isEmpty)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains {
                $0.hasPrefix("partial-") || $0.hasPrefix("transaction-")
            })
            recoveredPromotedModel = recovered.installed.contains { $0.id == "base.en" }
            try await coordinator.refresh()
        } else if scenario == "offline-relaunch" {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("receipt-clean-install-switch.json").path))
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            do {
                defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
                try await coordinator.restore()
            }
            XCTAssertEqual(coordinator.activeID, "base")
            XCTAssertEqual(coordinator.selectedID, "base")
            transcripts.append(try await transcript(session: try XCTUnwrap(runtime.session), root: root))
            XCTAssertEqual(OfflineModelNetworkTrap.requests, 0, "Offline restoration attempted model network access")
            runtime.stop()
            let fullStore = try ManagedLocalModelStore(root: root, capacity: { _ in 0 },
                configuration: configuration, atomicWrite: { _, _ in
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
                })
            XCTAssertThrowsError(try fullStore.commitSelection("base.en")) {
                XCTAssertEqual(($0 as NSError).domain, NSPOSIXErrorDomain)
                XCTAssertEqual(($0 as NSError).code, Int(ENOSPC))
            }
            let fullCoordinator = ManagedLocalModelCoordinator(runtime: runtime, store: fullStore)
            try await fullCoordinator.restore()
            XCTAssertEqual(fullCoordinator.selectedID, "base", "Failed writes must not change the durable selection")
            transcripts.append(try await transcript(session: try XCTUnwrap(runtime.session), root: root))
            XCTAssertEqual(OfflineModelNetworkTrap.requests, 0)
        } else { return XCTFail("Unknown acceptance scenario") }
        for text in transcripts { XCTAssertTrue(text.lowercased().contains("quick brown fox"), text) }
        let receipt: [String: Any] = ["scenario": scenario, "active": coordinator.activeID ?? "",
            "selected": coordinator.selectedID ?? "", "installed": coordinator.installed.map(\.id),
            "transcripts": transcripts, "offlineModelRequests": OfflineModelNetworkTrap.requests,
            "writeFailureCode": writeFailureCode ?? NSNull(),
            "overlappingRequestFinished": overlappingRequestFinished, "retiredChildExited": retiredChildExited,
            "recoveredPromotedModel": recoveredPromotedModel,
            "runtimeAddress": runtime.session?.displayAddress ?? "", "process": ProcessInfo.processInfo.processIdentifier]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("receipt-\(scenario).json"), options: .atomic)
    }

    private func transcript(session: ManagedLocalSession, root: URL) async throws -> String {
        let speech = root.appendingPathComponent("acceptance-speech.aiff")
        try makeSpeech(at: speech, repetitions: 1)
        return try await TranscriptionService(provider: .managedLocal(session: session))
            .transcribe(audioFileURL: speech, apiKey: nil, model: "whisper-1")
    }

    private func makeSpeech(at speech: URL, repetitions: Int) throws {
        let source = repetitions == 1 ? speech : speech.deletingLastPathComponent().appendingPathComponent("overlap-source.aiff")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", source.path, "The quick brown fox jumps over the lazy dog."]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        if repetitions > 1 {
            let input = try AVAudioFile(forReading: source)
            let output = try AVAudioFile(forWriting: speech, settings: input.fileFormat.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)))
            try input.read(into: buffer)
            for _ in 0..<repetitions { try output.write(from: buffer) }
        }
    }

    private func hasConnection(port: Int, state: String) -> Bool {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-iTCP:\(port)", "-sTCP:\(state)"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { XCTFail("Cannot inspect owned connection: \(error)"); return false }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && !data.isEmpty
    }

    private func listenerPID(port: Int) throws -> pid_t {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-t", "-a", "-iTCP:\(port)", "-sTCP:LISTEN"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(pid_t(value))
        XCTAssertGreaterThan(pid, 0)
        return pid
    }
}

private final class OfflineModelNetworkTrap: URLProtocol {
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
