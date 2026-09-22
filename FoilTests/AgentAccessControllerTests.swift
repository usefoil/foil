import Darwin
import XCTest
@testable import Foil

@MainActor
final class AgentAccessControllerTests: XCTestCase {
    private final class ServerStub: AgentAccessServing {
        var startError: Error?
        var onStart: (() -> Void)?
        private(set) var startCount = 0
        private(set) var stopCount = 0

        func start() throws {
            startCount += 1
            onStart?()
            if let startError { throw startError }
        }

        func stop() { stopCount += 1 }
    }

    private struct StartFailure: Error, LocalizedError {
        var errorDescription: String? { "Socket is unavailable." }
    }

    func testDisabledPreferenceDoesNotConstructOrStartServer() throws {
        let state = makeState()
        state.setAgentAccessEnabled(false, notifyController: false)
        var factoryCount = 0
        let controller = AgentAccessController(
            appState: state,
            paths: paths(),
            openAPIDocument: Data("{}".utf8)
        ) { _, _, _ in
            factoryCount += 1
            return ServerStub()
        }

        controller.startIfEnabled()

        XCTAssertEqual(factoryCount, 0)
        XCTAssertEqual(state.agentAccessPresentationState, .off)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths().socketURL.path))
    }

    func testEnablePublishesStartingBeforeItStartsThenDisableStopsServer() async throws {
        let state = makeState()
        state.setAgentAccessEnabled(false, notifyController: false)
        let server = ServerStub()
        var observedStarting = false
        server.onStart = { observedStarting = state.agentAccessPresentationState == .starting }
        let controller = AgentAccessController(
            appState: state,
            paths: paths(),
            openAPIDocument: Data("{}".utf8)
        ) { _, _, _ in server }

        state.setAgentAccessEnabled(true)
        XCTAssertEqual(server.startCount, 0)
        XCTAssertEqual(state.agentAccessPresentationState, .starting)
        let didRun = await waitUntil { state.agentAccessPresentationState == .running }
        XCTAssertTrue(didRun)
        XCTAssertEqual(server.startCount, 1)
        XCTAssertTrue(observedStarting)
        XCTAssertEqual(state.agentAccessPresentationState, .running)

        state.setAgentAccessEnabled(false)
        XCTAssertEqual(server.stopCount, 1)
        XCTAssertEqual(state.agentAccessPresentationState, .off)
        withExtendedLifetime(controller) {}
    }

    func testStartupFailureFailsClosedAndPreservesActionableError() async throws {
        let state = makeState()
        let server = ServerStub()
        server.startError = StartFailure()
        let controller = AgentAccessController(
            appState: state,
            paths: paths(),
            openAPIDocument: Data("{}".utf8)
        ) { _, _, _ in server }

        state.setAgentAccessEnabled(true)

        let didFail = await waitUntil { state.agentAccessPresentationState == .error }
        XCTAssertTrue(didFail)
        XCTAssertFalse(state.agentAccessEnabled)
        XCTAssertEqual(state.agentAccessPresentationState, .error)
        XCTAssertEqual(state.agentAccessErrorMessage, "Socket is unavailable.")
        XCTAssertEqual(server.stopCount, 1)
        withExtendedLifetime(controller) {}
    }

    func testPurposeBuiltReadModelOmitsSourceAndTimestampFields() throws {
        let pathSecret = "SECRET_LOCAL_STORAGE_PATH"
        let state = makeState(storageMarker: pathSecret)
        let recordSecret = UUID()
        let correction = try XCTUnwrap(state.addVocabularyCorrection(
            writtenAs: "super base",
            correctVersion: "Supabase",
            note: "tech stack",
            sourceRecordID: recordSecret,
            sourceAppName: "SECRET_SOURCE_APP"
        ))
        _ = state.addVocabularyTerm("Codex", note: "agent")

        let model = AgentAccessController.makeReadModel(from: state)
        let exposed = try XCTUnwrap(model.corrections.first { $0.id == correction.id.uuidString.lowercased() })
        let vocabularyResponse = AgentAccessVocabularyResponse(
            requestID: "privacy-test",
            localCorrectionsEnabled: model.localCorrectionsEnabled,
            terms: model.terms,
            corrections: model.corrections
        )
        let scopesResponse = AgentAccessScopesResponse(requestID: "privacy-test", scopes: model.scopes)
        let exposedResponses = [
            try JSONEncoder().encode(vocabularyResponse),
            try JSONEncoder().encode(scopesResponse)
        ].map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")

        XCTAssertEqual(exposed.writtenAs, "super base")
        XCTAssertEqual(exposed.correctVersion, "Supabase")
        for secret in [recordSecret.uuidString, "SECRET_SOURCE_APP", pathSecret] {
            XCTAssertFalse(exposedResponses.contains(secret), "Leaked \(secret)")
        }
        XCTAssertFalse(exposedResponses.contains("created_at"))
        XCTAssertFalse(exposedResponses.contains("updated_at"))
    }

    func testRunningHandlerReceivesVocabularyChangesWithoutMainActorReads() async throws {
        let state = makeState()
        state.setAgentAccessEnabled(false, notifyController: false)
        var handler: AgentAccessServer.Handler?
        let server = ServerStub()
        let controller = AgentAccessController(
            appState: state,
            paths: paths(),
            openAPIDocument: Data("{}".utf8)
        ) { _, _, capturedHandler in
            handler = capturedHandler
            return server
        }
        state.setAgentAccessEnabled(true)
        let capturedHandler = await waitUntil { handler != nil }
        XCTAssertTrue(capturedHandler)
        _ = state.addVocabularyTerm("Codex", note: "agent")

        let request = AgentAccessHTTPRequest(
            method: .get,
            path: "/v1/vocabulary",
            headers: [:],
            body: Data()
        )
        let response = try XCTUnwrap(handler)(request)
        let decoded = try JSONDecoder().decode(AgentAccessVocabularyResponse.self, from: response.body)

        XCTAssertTrue(decoded.terms.map(\.term).contains("Codex"))
        state.setAgentAccessEnabled(false)
        withExtendedLifetime(controller) {}
    }

    func testRealServerDisableClosesPartialClientAndRemovesSocket() async throws {
        let state = makeState()
        state.setAgentAccessEnabled(false, notifyController: false)
        let livePaths = paths()
        let controller = AgentAccessController(
            appState: state,
            paths: livePaths,
            openAPIDocument: Data("{}".utf8)
        )
        defer {
            controller.stop()
            try? FileManager.default.removeItem(at: livePaths.supportDirectory)
        }

        state.setAgentAccessEnabled(true)
        let didCreateSocket = await waitUntil {
            FileManager.default.fileExists(atPath: livePaths.socketURL.path)
        }
        XCTAssertTrue(didCreateSocket)
        XCTAssertTrue(FileManager.default.fileExists(atPath: livePaths.socketURL.path))
        let client = try connect(to: livePaths.socketURL)
        XCTAssertGreaterThanOrEqual(Darwin.send(client, "GET ", 4, 0), 0)

        state.setAgentAccessEnabled(false)

        var byte: UInt8 = 0
        XCTAssertLessThanOrEqual(Darwin.recv(client, &byte, 1, 0), 0)
        Darwin.close(client)
        XCTAssertFalse(FileManager.default.fileExists(atPath: livePaths.socketURL.path))
        XCTAssertEqual(state.agentAccessPresentationState, .off)
    }

    func testReadRoutesAndDiagnosticsExcludeSeededForbiddenDataAndPreviewDoesNotPersist() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-agent-privacy-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "com.neonwatty.Foil.AgentAccessPrivacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let providerSecret = "SECRET_PROVIDER_MODEL"
        let baseURLSecret = "https://SECRET_PROVIDER_BASE_URL.invalid/v1"
        let historySecret = "SECRET_HISTORY_TRANSCRIPT"
        let keySecret = "SECRET_CREDENTIAL_VALUE"
        let pathSecret = "/Applications/SECRET_SOURCE_PATH.app"
        let sourceAppSecret = "SECRET_SOURCE_APP"
        let sourceRecordSecret = UUID()
        defaults.set(providerSecret, forKey: "whisperModel")
        defaults.set(baseURLSecret, forKey: "customTranscriptionBaseURL")
        let state = AppState(
            localCorrectionStore: LocalCorrectionStore(
                fileURL: root.appendingPathComponent("SECRET_LOCAL_RULE_PATH/rules.json")
            ),
            agentAccessDefaults: defaults,
            initialDefaultsOverride: defaults
        )
        XCTAssertEqual(state.selectedModel, providerSecret)
        XCTAssertEqual(state.customTranscriptionBaseURL, baseURLSecret)
        let correction = try XCTUnwrap(state.addVocabularyCorrection(
            writtenAs: "super base",
            correctVersion: "Supabase",
            note: "database",
            sourceRecordID: sourceRecordSecret,
            sourceAppName: sourceAppSecret
        ))
        defer { _ = state.deleteVocabularyCorrection(id: correction.id) }

        let history = TranscriptionHistory(
            storageDirectory: root.appendingPathComponent("History"),
            retentionLimit: 10,
            isPersistenceEnabled: true
        )
        history.addSuccess(text: historySecret, sourceAppName: sourceAppSecret)
        history.addFailure(
            error: "failure",
            audioFileURL: nil,
            sourceAppName: sourceAppSecret,
            sourceAppPath: pathSecret
        )
        XCTAssertTrue(history.records.contains { $0.text == historySecret })
        XCTAssertTrue(history.records.contains { $0.sourceAppPath == pathSecret })
        let previousCredentialRoot = KeychainHelper.storageDirectoryOverride
        let previousCredentialService = KeychainHelper.serviceOverride
        let previousCredentialAccount = KeychainHelper.accountOverride
        defer {
            KeychainHelper.storageDirectoryOverride = previousCredentialRoot
            KeychainHelper.serviceOverride = previousCredentialService
            KeychainHelper.accountOverride = previousCredentialAccount
        }
        KeychainHelper.storageDirectoryOverride = root.appendingPathComponent("Credentials")
        KeychainHelper.serviceOverride = "com.neonwatty.Foil.agent-access-privacy"
        KeychainHelper.accountOverride = "agent-access-privacy"
        try KeychainHelper.save(apiKey: keySecret)
        XCTAssertEqual(KeychainHelper.readApiKey(), keySecret)

        let livePaths = AgentAccessPaths(
            applicationSupportRoot: FileManager.default.temporaryDirectory,
            directoryName: "foil-agent-privacy-socket-\(UUID().uuidString.prefix(8))"
        )
        let logURL = root.appendingPathComponent("diagnostics.log")
        DiagnosticLog.logURLOverride = logURL
        DiagnosticLog.isEnabledOverride = true
        DiagnosticLog.clearForTesting()
        let controller = AgentAccessController(
            appState: state,
            paths: livePaths,
            openAPIDocument: Data("{}".utf8)
        )
        defer {
            controller.stop()
            DiagnosticLog.clearForTesting()
            DiagnosticLog.logURLOverride = nil
            DiagnosticLog.isEnabledOverride = nil
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: livePaths.supportDirectory)
        }
        let termsBefore = state.vocabularyTerms
        let correctionsBefore = state.vocabularyCorrections
        let rulesBefore = state.localCorrectionSnapshot

        state.setAgentAccessEnabled(true)
        let didCreateSocket = await waitUntil {
            FileManager.default.fileExists(atPath: livePaths.socketURL.path)
        }
        XCTAssertTrue(didCreateSocket)
        XCTAssertEqual(KeychainHelper.readApiKey(), keySecret)

        var exposed = Data()
        for path in ["/v1/instructions", "/v1/openapi.json", "/v1/vocabulary/scopes", "/v1/vocabulary"] {
            exposed.append(try sendHTTPRequest(to: livePaths.socketURL, method: "GET", path: path))
        }
        let previewBody = Data(#"{"corrections":[{"spoken_forms":["cloud code"],"replacement":"Claude Code"}]}"#.utf8)
        exposed.append(try sendHTTPRequest(
            to: livePaths.socketURL,
            method: "POST",
            path: "/v1/vocabulary/preview",
            body: previewBody
        ))
        let proposalAliasSecret = "SECRET_PROPOSAL_ALIAS"
        let proposalReplacementSecret = "SECRET_PROPOSAL_REPLACEMENT"
        let proposalNoteSecret = "SECRET_PROPOSAL_NOTE"
        let proposalBody = Data(#"{"schema_version":1,"request_id":"privacy-proposal","scope":{"kind":"global","id":"global"},"corrections":[{"spoken_forms":["SECRET_PROPOSAL_ALIAS"],"replacement":"SECRET_PROPOSAL_REPLACEMENT","note":"SECRET_PROPOSAL_NOTE"}]}"#.utf8)
        exposed.append(try sendHTTPRequest(
            to: livePaths.socketURL,
            method: "POST",
            path: "/v1/vocabulary/proposals",
            body: proposalBody
        ))
        let diagnostics = DiagnosticLog.recentLines(limit: 100).joined(separator: "\n")
        let responseText = String(decoding: exposed, as: UTF8.self)

        for secret in [
            providerSecret, baseURLSecret, historySecret, keySecret, pathSecret,
            sourceAppSecret, sourceRecordSecret.uuidString, "SECRET_LOCAL_RULE_PATH",
            proposalAliasSecret, proposalReplacementSecret, proposalNoteSecret
        ] {
            XCTAssertFalse(responseText.contains(secret), "Response leaked \(secret)")
            XCTAssertFalse(diagnostics.contains(secret), "Diagnostics leaked \(secret)")
        }
        XCTAssertEqual(state.vocabularyTerms, termsBefore)
        XCTAssertEqual(state.vocabularyCorrections, correctionsBefore)
        XCTAssertEqual(state.localCorrectionSnapshot, rulesBefore)
    }

    func testDisableWhileStartingCancelsPendingStartup() async throws {
        let state = makeState()
        state.setAgentAccessEnabled(false, notifyController: false)
        let server = ServerStub()
        let controller = AgentAccessController(
            appState: state,
            paths: paths(),
            openAPIDocument: Data("{}".utf8),
            startupDelayNanoseconds: 1_000_000_000
        ) { _, _, _ in server }

        state.setAgentAccessEnabled(true)
        XCTAssertEqual(state.agentAccessPresentationState, .starting)
        state.setAgentAccessEnabled(false)
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(server.startCount, 0)
        XCTAssertEqual(server.stopCount, 0)
        XCTAssertEqual(state.agentAccessPresentationState, .off)
        withExtendedLifetime(controller) {}
    }

    func testProposalSubmissionIsInertAndCapturedHandlerFailsAfterDisable() async throws {
        let state = makeState()
        state.setAgentAccessEnabled(false, notifyController: false)
        let livePaths = paths()
        let proposalStore = VocabularyProposalStore(fileURL: livePaths.proposalStoreURL)
        let vocabularyBefore = state.vocabularyCorrections
        let rulesBefore = state.localCorrectionSnapshot
        var handler: AgentAccessServer.Handler?
        let server = ServerStub()
        let controller = AgentAccessController(
            appState: state,
            paths: livePaths,
            openAPIDocument: Data("{}".utf8),
            proposalStore: proposalStore
        ) { _, _, capturedHandler in
            handler = capturedHandler
            return server
        }
        defer { try? FileManager.default.removeItem(at: livePaths.supportDirectory) }

        state.setAgentAccessEnabled(true)
        let didStart = await waitUntil { handler != nil && state.agentAccessPresentationState == .running }
        XCTAssertTrue(didStart)
        let firstBody = try JSONEncoder().encode(VocabularyProposalRequest(
            requestID: "request-1",
            scope: .init(kind: "global", id: "global"),
            corrections: [.init(spokenForms: ["super base"], replacement: "Supabase")]
        ))
        let created = (try XCTUnwrap(handler))(AgentAccessHTTPRequest(
            method: .post,
            path: "/v1/vocabulary/proposals",
            headers: [:],
            body: firstBody
        ))

        XCTAssertEqual(created.status, 201)
        let didPublish = await waitUntil { state.agentAccessPendingProposalCount == 1 }
        XCTAssertTrue(didPublish)
        XCTAssertEqual(state.vocabularyCorrections, vocabularyBefore)
        XCTAssertEqual(state.localCorrectionSnapshot, rulesBefore)

        state.setAgentAccessEnabled(false)
        let secondBody = try JSONEncoder().encode(VocabularyProposalRequest(
            requestID: "request-2",
            scope: .init(kind: "global", id: "global"),
            corrections: [.init(spokenForms: ["cloud code"], replacement: "Claude Code")]
        ))
        let disabled = (try XCTUnwrap(handler))(AgentAccessHTTPRequest(
            method: .post,
            path: "/v1/vocabulary/proposals",
            headers: [:],
            body: secondBody
        ))

        XCTAssertEqual(disabled.status, 503)
        XCTAssertEqual(try proposalStore.load().proposals.count, 1)
        XCTAssertEqual(state.agentAccessPendingProposalCount, 1)

        let proposalID = try XCTUnwrap(state.agentAccessProposals.first?.id)
        state.transitionAgentAccessProposal(id: proposalID, to: .rejected)
        XCTAssertEqual(state.agentAccessPendingProposalCount, 0)
        XCTAssertEqual(state.vocabularyCorrections, vocabularyBefore)
        XCTAssertEqual(state.localCorrectionSnapshot, rulesBefore)
        withExtendedLifetime(controller) {}
    }

    func testUITestSeedUsesProposalServiceWithoutEnablingAccess() throws {
        let state = makeState()
        state.setAgentAccessEnabled(false, notifyController: false)
        let livePaths = paths()
        let vocabularyBefore = state.vocabularyCorrections
        let rulesBefore = state.localCorrectionSnapshot
        let controller = AgentAccessController(
            appState: state,
            paths: livePaths,
            openAPIDocument: Data("{}".utf8)
        )
        defer {
            controller.stop()
            try? FileManager.default.removeItem(at: livePaths.supportDirectory)
        }

        controller.seedVocabularyProposalForUITesting()

        XCTAssertFalse(state.agentAccessEnabled)
        XCTAssertEqual(state.agentAccessPresentationState, .off)
        XCTAssertEqual(state.agentAccessPendingProposalCount, 1)
        XCTAssertEqual(state.agentAccessProposals.first?.corrections.first?.replacement, "Supabase")
        XCTAssertEqual(state.vocabularyCorrections, vocabularyBefore)
        XCTAssertEqual(state.localCorrectionSnapshot, rulesBefore)
    }

    func testAgentAccessPreferencePersistsInInjectedDefaultsSuite() throws {
        let suiteName = "com.neonwatty.Foil.AgentAccessTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = makeState(agentAccessDefaults: defaults)

        first.setAgentAccessEnabled(true, notifyController: false)
        let reloaded = makeState(agentAccessDefaults: defaults)

        XCTAssertTrue(reloaded.agentAccessEnabled)
        reloaded.setAgentAccessEnabled(false, notifyController: false)
        XCTAssertFalse(makeState(agentAccessDefaults: defaults).agentAccessEnabled)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func makeState(
        agentAccessDefaults: UserDefaults? = nil,
        storageMarker: String = UUID().uuidString,
        initialDefaultsOverride: UserDefaults? = nil
    ) -> AppState {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-agent-controller-\(storageMarker)", isDirectory: true)
        let defaults = agentAccessDefaults ?? UserDefaults(
            suiteName: "com.neonwatty.Foil.AgentAccessTests.\(UUID().uuidString)"
        )!
        return AppState(
            localCorrectionStore: LocalCorrectionStore(fileURL: root.appendingPathComponent("rules.json")),
            agentAccessDefaults: defaults,
            initialDefaultsOverride: initialDefaultsOverride
        )
    }

    private func paths() -> AgentAccessPaths {
        AgentAccessPaths(
            applicationSupportRoot: FileManager.default.temporaryDirectory,
            directoryName: "foil-agent-controller-\(UUID().uuidString.prefix(8))"
        )
    }

    private func connect(to url: URL) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_un()
        let length = socklen_t(
            MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path)! + url.path.utf8.count + 1
        )
        address.sun_len = UInt8(length)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(url.path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            destination.copyBytes(from: bytes)
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, length)
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return fd
    }

    private func sendHTTPRequest(
        to socketURL: URL,
        method: String,
        path: String,
        body: Data = Data()
    ) throws -> Data {
        let client = try connect(to: socketURL)
        defer { Darwin.close(client) }
        var request = "\(method) \(path) HTTP/1.1\r\nHost: foil\r\n"
        if !body.isEmpty {
            request += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
        }
        request += "\r\n"
        var bytes = Data(request.utf8)
        bytes.append(body)
        let written = bytes.withUnsafeBytes { buffer in
            Darwin.send(client, buffer.baseAddress, buffer.count, 0)
        }
        guard written == bytes.count else { throw POSIXError(.EIO) }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.recv(client, &buffer, buffer.count, 0)
            if count > 0 {
                response.append(buffer, count: count)
            } else if count == 0 {
                return response
            } else if errno == EINTR {
                continue
            } else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }
}
