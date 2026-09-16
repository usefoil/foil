import AVFAudio
import Foundation
import Network
import XCTest
@testable import Foil

@MainActor
final class ManagedLocalRuntimeIntegrationTests: XCTestCase {
    func testPersistenceFailureCannotRetirePreviousHealthySession() async throws {
        enum PersistenceFailure: Error { case writeDenied }
        let runtime = ManagedLocalRuntime()
        defer { runtime.stop() }
        let model = try fixtureModel()
        let original = try await runtime.start(model: model)
        do {
            _ = try await runtime.start(model: model, beforeCommit: { throw PersistenceFailure.writeDenied })
            XCTFail("A session was committed without durable selection")
        } catch { XCTAssertTrue(error is PersistenceFailure) }
        XCTAssertEqual(runtime.session?.id, original.id)
        let healthy = try await original.health()
        XCTAssertTrue(healthy)
    }

    func testSuccessfulSwitchPreservesRetainedTranscriptionSession() async throws {
        let runtime = ManagedLocalRuntime()
        defer { runtime.stop() }
        let model = try fixtureModel()
        let original = try await runtime.start(model: model)
        let replacement = try await runtime.start(model: model)
        XCTAssertNotEqual(original.id, replacement.id)
        let healthy = try await original.health()
        XCTAssertTrue(healthy, "A transcript holding the original session must survive a successful switch")
    }

    private func fixtureModel() throws -> ManagedLocalModel {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ggml-tiny.en", withExtension: "bin"))
        return try ManagedLocalModel.verify(url: url,
            id: "tiny.en", size: 77_704_715, sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f")
    }

    func testRealSwiftSessionConvertsAACTranscribesAndRejectsStoppedSession() async throws {
        let model = try fixtureModel()
        let runtime = ManagedLocalRuntime()
        defer { runtime.stop() }
        let session = try await runtime.start(model: model)
        let healthy = try await session.health()
        XCTAssertTrue(healthy)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let aiff = directory.appendingPathComponent("speech.aiff")
        let aac = directory.appendingPathComponent("speech.m4a")
        let speech = Process()
        speech.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        speech.arguments = ["-o", aiff.path, "The quick brown fox jumps over the lazy dog."]
        try speech.run(); speech.waitUntilExit()
        XCTAssertEqual(speech.terminationStatus, 0)
        try encodeAAC(source: aiff, destination: aac)
        let service = TranscriptionService(provider: .managedLocal(session: session))
        let transcript = try await service.transcribe(audioFileURL: aac, apiKey: nil, model: "whisper-1", format: .m4a)
        XCTAssertTrue(transcript.lowercased().contains("quick brown fox"), transcript)
        XCTAssertEqual(runtime.state, .ready("tiny.en"))
        let replacement = try await runtime.start(model: model)
        XCTAssertNotEqual(session.id, replacement.id)
        let replacementHealthy = try await replacement.health()
        XCTAssertTrue(replacementHealthy)
        runtime.stop()
        do {
            _ = try await service.transcribe(audioFileURL: aac, apiKey: nil, model: "whisper-1")
            XCTFail("Stopped session accepted an upload")
        } catch { XCTAssertEqual(error as? ManagedLocalError, .notReady) }
    }

    func testManagedValidationUsesOwnedHealthAndRejectsStoppedSession() async throws {
        let runtime = ManagedLocalRuntime()
        defer { runtime.stop() }
        let session = try await runtime.start(model: fixtureModel())
        let transport = ValidationTransport()
        let service = TranscriptionService(provider: .managedLocal(session: session), transport: transport)
        let result = try await service.validateProviderConfiguration(apiKey: "must-not-send")
        XCTAssertEqual(result, .modelsValidated)
        XCTAssertEqual(transport.calls, 0)
        session.stop()
        runtime.cancelPending()
        XCTAssertEqual(runtime.state, .idle, "Cancelling a candidate cannot claim a stopped active session is Ready")
        do {
            _ = try await service.validateProviderConfiguration(apiKey: nil)
            XCTFail("Stopped managed session validated")
        } catch { XCTAssertEqual(error as? ManagedLocalError, .notReady) }
        XCTAssertEqual(transport.calls, 0)
    }

    func testManagedValidationRejectsForeignHealthAndGenericStatuses() async throws {
        let model = try fixtureModel()
        for status in [200, 404, 405] {
            let listener = try NWListener(using: .tcp, on: .any)
            defer { listener.cancel() }
            let ready = expectation(description: "Foreign validation listener")
            listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                    let response = "HTTP/1.1 \(status) Fixture\r\nContent-Length: 15\r\n\r\n{\"status\":\"ok\"}"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            listener.start(queue: .global())
            await fulfillment(of: [ready], timeout: 5)
            let process = Process()
            let lifetime = Pipe()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            process.executableURL = URL(fileURLWithPath: "/bin/cat")
            process.standardInput = lifetime
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            let session = ManagedLocalSession(id: UUID(), model: model, process: process, lifetime: lifetime,
                directory: directory, token: "fixture", port: Int(try XCTUnwrap(listener.port).rawValue))
            defer { session.stop() }
            let transport = ValidationTransport()
            let service = TranscriptionService(provider: .managedLocal(session: session), transport: transport)
            do {
                _ = try await service.validateProviderConfiguration(apiKey: nil)
                XCTFail("Foreign health HTTP \(status) validated")
            } catch { XCTAssertEqual(error as? ManagedLocalError, status == 200 ? .foreignService : .notReady) }
            XCTAssertEqual(transport.calls, 0)
        }
    }

    private final class ValidationTransport: TranscriptionTransport {
        var calls = 0
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            calls += 1
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testFailedCandidatePreservesExistingReadySession() async throws {
        let runtime = ManagedLocalRuntime()
        defer { runtime.stop() }
        let original = try await runtime.start(model: fixtureModel())
        let badURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: badURL) }
        try Data("abc".utf8).write(to: badURL)
        let invalidWhisper = try ManagedLocalModel.verify(url: badURL, id: "bad", size: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        do { _ = try await runtime.start(model: invalidWhisper); XCTFail("Invalid model became ready") }
        catch { XCTAssertEqual(error as? ManagedLocalError, .startupFailed) }
        XCTAssertEqual(runtime.session?.id, original.id)
        let originalHealthy = try await original.health()
        XCTAssertTrue(originalHealthy)
    }

    func testCompressedInputCannotExceedUploadLimitAfterConversion() async throws {
        let runtime = ManagedLocalRuntime()
        defer { runtime.stop() }
        let session = try await runtime.start(model: fixtureModel())
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: source) }
        try makeLongCompressedAudio(at: source)
        let sourceBytes = try FileManager.default.attributesOfItem(atPath: source.path)[.size] as! NSNumber
        XCTAssertLessThan(sourceBytes.intValue, TranscriptionService.maxUploadBytes)
        let service = TranscriptionService(provider: .managedLocal(session: session))
        do {
            _ = try await service.transcribe(audioFileURL: source, apiKey: nil, model: "whisper-1", format: .m4a)
            XCTFail("Expanded WAV exceeded upload limit")
        } catch { XCTAssertEqual(error as? TranscriptionService.TranscriptionError, .fileTooLarge) }
    }

    func testCancelledLaunchCannotActivateSession() async throws {
        let runtime = ManagedLocalRuntime()
        defer { runtime.stop() }
        let model = try fixtureModel()
        let launch = Task { try await runtime.start(model: model) }
        launch.cancel()
        do { _ = try await launch.value; XCTFail("Cancelled launch activated") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(runtime.session)
    }

    func testOccupiedPortRetriesAreBoundedAndForeignListenerSurvives() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        defer { listener.cancel() }
        let ready = expectation(description: "Foreign listener ready")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 15\r\n\r\n{\"status\":\"ok\"}"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .global())
        await fulfillment(of: [ready], timeout: 5)
        let port = Int(try XCTUnwrap(listener.port).rawValue)
        var allocations = 0
        let runtime = ManagedLocalRuntime(portAllocator: { allocations += 1; return port })
        defer { runtime.stop() }
        do { _ = try await runtime.start(model: fixtureModel()); XCTFail("Occupied port was accepted") }
        catch { XCTAssertEqual(error as? ManagedLocalError, .startupFailed) }
        XCTAssertEqual(allocations, 3)
        XCTAssertNil(runtime.session)
        if case .ready = listener.state {} else { XCTFail("Unowned listener was stopped") }
    }

    func testReadinessTimeoutCannotActivateSession() async throws {
        let runtime = ManagedLocalRuntime(startupTimeout: 0)
        defer { runtime.stop() }
        do { _ = try await runtime.start(model: fixtureModel()); XCTFail("Timed-out runtime activated") }
        catch { XCTAssertEqual(error as? ManagedLocalError, .timedOut) }
        XCTAssertNil(runtime.session)
    }

    func testSupersededLaunchCannotReplaceNewerSession() async throws {
        let runtime = ManagedLocalRuntime()
        defer { runtime.stop() }
        let model = try fixtureModel()
        let first = Task { try await runtime.start(model: model) }
        await Task.yield()
        let latest = try await runtime.start(model: model)
        do { _ = try await first.value; XCTFail("Superseded launch was accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(runtime.session?.id, latest.id)
        let healthy = try await latest.health()
        XCTAssertTrue(healthy)
    }

    func testUnsafeNamespaceIsRejectedBeforeConnecting() async throws {
        let request = URLRequest(url: URL(string: "http://example.com:1234/private-token/health")!)
        do { _ = try await ManagedLocalHTTP().data(for: request); XCTFail("Unsafe endpoint accepted") }
        catch { XCTAssertEqual(error as? ManagedLocalError, .unsafeAddress) }
    }

    func testRedirectAndAmbiguousFramingAreRejected() async throws {
        for response in [
            "HTTP/1.1 302 Found\r\nLocation: http://203.0.113.1/leak\r\nContent-Length: 0\r\n\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nContent-Length: 10\r\n\r\n"
        ] {
            let listener = try NWListener(using: .tcp, on: .any)
            let ready = expectation(description: "Fixture listener ready")
            listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            listener.start(queue: .global())
            await fulfillment(of: [ready], timeout: 5)
            let port = try XCTUnwrap(listener.port)
            var request = URLRequest(url: URL(string: "http://transcribe.foil.localhost:\(port.rawValue)/health")!)
            request.timeoutInterval = 2
            do { _ = try await ManagedLocalHTTP().data(for: request); XCTFail("Unsafe response accepted") }
            catch { XCTAssertEqual(error as? ManagedLocalError, .transport) }
            listener.cancel()
        }
    }

    private func encodeAAC(source: URL, destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let output = try AVAudioFile(forWriting: destination, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        while input.framePosition < input.length { try input.read(into: buffer); try output.write(from: buffer) }
    }

    private func makeLongCompressedAudio(at url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for index in 0..<16_000 { buffer.floatChannelData![0][index] = sin(Float(index) * 0.1) * 0.1 }
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 16_000])
        for _ in 0..<840 { try file.write(from: buffer) }
    }
}
