import Darwin
import XCTest
@testable import Foil

@MainActor
final class AgentAccessControllerTests: XCTestCase {
    private final class ServerStub: AgentAccessServing {
        var startError: Error?
        var onStart: (() -> Void)?
        var onStop: (() -> Void)?
        private(set) var startCount = 0
        private(set) var stopCount = 0

        func start() throws {
            startCount += 1
            onStart?()
            if let startError { throw startError }
        }

        func stop() {
            stopCount += 1
            onStop?()
        }
    }

    private final class EventRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []

        func record(_ event: String) {
            lock.withLock { events.append(event) }
        }

        func snapshot() -> [String] {
            lock.withLock { events }
        }
    }

    private final class HandlerBox: @unchecked Sendable {
        let handler: AgentAccessServer.Handler

        init(_ handler: @escaping AgentAccessServer.Handler) {
            self.handler = handler
        }
    }

    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var response: AgentAccessHTTPResponse?

        func set(_ response: AgentAccessHTTPResponse) {
            lock.withLock { self.response = response }
        }

        func get() -> AgentAccessHTTPResponse? {
            lock.withLock { response }
        }
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

    func testDisableWaitsForInFlightProposalCommitBeforeReportingOff() async throws {
        let state = makeState()
        state.setAgentAccessEnabled(false, notifyController: false)
        let livePaths = paths()
        let recorder = EventRecorder()
        let writerStarted = DispatchSemaphore(value: 0)
        let writerDelay = DispatchSemaphore(value: 0)
        let proposalStore = VocabularyProposalStore(
            fileURL: livePaths.proposalStoreURL,
            atomicWriter: { data, url in
                recorder.record("write_started")
                writerStarted.signal()
                _ = writerDelay.wait(timeout: .now() + 0.3)
                try data.write(to: url, options: .atomic)
                recorder.record("write_finished")
            }
        )
        var handler: AgentAccessServer.Handler?
        let server = ServerStub()
        server.onStop = { recorder.record("server_stopped") }
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
        let didStart = await waitUntil {
            handler != nil && state.agentAccessPresentationState == .running
        }
        XCTAssertTrue(didStart)
        let request = AgentAccessHTTPRequest(
            method: .post,
            path: "/v1/vocabulary/proposals",
            headers: [:],
            body: try JSONEncoder().encode(VocabularyProposalRequest(
                requestID: "in-flight-request",
                scope: .init(kind: "global", id: "global"),
                corrections: [.init(spokenForms: ["super base"], replacement: "Supabase")]
            ))
        )
        let handlerBox = HandlerBox(try XCTUnwrap(handler))
        let responseBox = ResponseBox()
        let responseFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            responseBox.set(handlerBox.handler(request))
            responseFinished.signal()
        }

        XCTAssertEqual(writerStarted.wait(timeout: .now() + 1), .success)
        state.setAgentAccessEnabled(false)
        XCTAssertEqual(responseFinished.wait(timeout: .now() + 1), .success)

        XCTAssertEqual(responseBox.get()?.status, 201)
        XCTAssertEqual(state.agentAccessPresentationState, .off)
        XCTAssertEqual(server.stopCount, 1)
        XCTAssertEqual(try proposalStore.load().proposals.count, 1)
        let events = recorder.snapshot()
        let writeFinished = try XCTUnwrap(events.firstIndex(of: "write_finished"))
        let serverStopped = try XCTUnwrap(events.firstIndex(of: "server_stopped"))
        XCTAssertLessThan(writeFinished, serverStopped, events.joined(separator: ", "))
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

    func testReviewedScopedProposalAppliesThroughCatalogAndReconcilesInbox() throws {
        let marker = UUID().uuidString
        let state = makeState(storageMarker: marker, activateCatalog: true)
        state.setCleanupGroups([
            CleanupGroup.defaultGroup(),
            CleanupGroup(id: "agents", name: "Agent editors", sortOrder: 1)
        ])
        let proposalStore = VocabularyProposalStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("foil-agent-controller-\(marker)", isDirectory: true)
                .appendingPathComponent("proposals.json")
        )
        let controller = AgentAccessController(
            appState: state,
            paths: paths(),
            openAPIDocument: Data("{}".utf8),
            proposalStore: proposalStore
        ) { _, _, _ in ServerStub() }
        controller.seedVocabularyProposalForUITesting()
        let proposalID = try XCTUnwrap(state.agentAccessProposals.first?.id)
        state.reviseAgentAccessProposal(
            id: proposalID,
            scope: .init(kind: "cleanup_group", id: "agents"),
            corrections: [
                .init(spokenForms: ["Superbase", "super base"], replacement: "Supabase"),
                .init(spokenForms: ["codecs"], replacement: "Codex")
            ]
        )

        state.applyAgentAccessProposal(id: proposalID)

        XCTAssertEqual(state.vocabularyCorrections.map(\.writtenAs), [
            "Superbase", "super base", "codecs"
        ])
        XCTAssertEqual(state.localCorrectionSnapshot.rules.count, 3)
        XCTAssertTrue(state.localCorrectionSnapshot.rules.allSatisfy { $0.group == "agents" })
        XCTAssertFalse(state.localCorrectionSnapshot.isEnabled)
        XCTAssertEqual(try proposalStore.proposal(id: proposalID)?.state, .applied)
        XCTAssertEqual(state.agentAccessPendingProposalCount, 0)
        _ = try state.setLocalCorrectionsEnabled(true)
        XCTAssertEqual(
            state.previewLocalCorrections("Superbase and codecs", activeGroupID: "agents").text,
            "Supabase and Codex"
        )
        XCTAssertEqual(
            state.previewLocalCorrections("Superbase and codecs", activeGroupID: "messages").text,
            "Superbase and codecs"
        )
        withExtendedLifetime(controller) {}
    }

    func testUnrelatedSecondProposalAllowsRevalidatedReviewedApply() throws {
        let marker = UUID().uuidString
        let state = makeState(storageMarker: marker, activateCatalog: true)
        let proposalStore = VocabularyProposalStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("foil-agent-controller-\(marker)", isDirectory: true)
                .appendingPathComponent("proposals.json")
        )
        let controller = AgentAccessController(
            appState: state,
            paths: paths(),
            openAPIDocument: Data("{}".utf8),
            proposalStore: proposalStore
        ) { _, _, _ in ServerStub() }
        controller.seedVocabularyProposalForUITesting()
        let proposalID = try XCTUnwrap(state.agentAccessProposals.first?.id)
        let token = try XCTUnwrap(state.agentAccessProposals.first?.snapshotToken)
        let secondID = try proposalStore.submit(VocabularyProposalRequest(
            requestID: "second-unrelated-\(marker)",
            scope: .init(kind: "global", id: "global"),
            corrections: [.init(spokenForms: ["cloud code"], replacement: "Claude Code")]
        ), snapshotToken: token).receipt.proposalID
        controller.refreshProposals()
        state.applyAgentAccessProposal(id: secondID)

        XCTAssertTrue(state.agentAccessStaleProposalIDs.contains(proposalID))
        XCTAssertEqual(state.agentAccessProposalPreviews[proposalID]?.valid, true)

        state.applyAgentAccessProposal(id: proposalID)

        XCTAssertEqual(Set(state.vocabularyCorrections.map(\.writtenAs)),
                       Set(["cloud code", "super base", "Superbase", "codecs"]))
        XCTAssertEqual(try proposalStore.proposal(id: proposalID)?.state, .applied)
        XCTAssertNil(state.agentAccessProposalInboxErrorMessage)
        withExtendedLifetime(controller) {}
    }

    func testConflictingSecondProposalBlocksRevalidatedReviewedApply() throws {
        let marker = UUID().uuidString
        let state = makeState(storageMarker: marker, activateCatalog: true)
        let proposalStore = VocabularyProposalStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("foil-agent-controller-\(marker)", isDirectory: true)
                .appendingPathComponent("proposals.json")
        )
        let controller = AgentAccessController(
            appState: state,
            paths: paths(),
            openAPIDocument: Data("{}".utf8),
            proposalStore: proposalStore
        ) { _, _, _ in ServerStub() }
        controller.seedVocabularyProposalForUITesting()
        let proposalID = try XCTUnwrap(state.agentAccessProposals.first?.id)
        let token = try XCTUnwrap(state.agentAccessProposals.first?.snapshotToken)
        let secondID = try proposalStore.submit(VocabularyProposalRequest(
            requestID: "second-conflicting-\(marker)",
            scope: .init(kind: "global", id: "global"),
            corrections: [.init(spokenForms: ["super base"], replacement: "Another product")]
        ), snapshotToken: token).receipt.proposalID
        controller.refreshProposals()
        state.applyAgentAccessProposal(id: secondID)

        XCTAssertEqual(state.agentAccessProposalPreviews[proposalID]?.valid, false)
        XCTAssertTrue(state.agentAccessProposalPreviews[proposalID]?.issues.contains(where: {
            $0.code == "correction_conflict"
        }) == true)
        XCTAssertTrue(state.agentAccessProposalPreviews[proposalID]?.issues.contains(where: {
            $0.message.contains("super base") && $0.message.contains("Every app")
        }) == true)
        state.applyAgentAccessProposal(id: proposalID)

        XCTAssertEqual(state.vocabularyCorrections.map(\.writtenAs), ["super base"])
        XCTAssertEqual(try proposalStore.proposal(id: proposalID)?.state, .pending)
        XCTAssertNotNil(state.agentAccessProposalInboxErrorMessage)
        withExtendedLifetime(controller) {}
    }

    func testAgentActionRequiresFoilApprovalAndReplayIsAudited() async throws {
        let state = makeState(storageMarker: UUID().uuidString, activateCatalog: true)
        state.setAgentAccessEnabled(false, notifyController: false)
        let livePaths = paths()
        let actionStore = AgentAccessActionStore(fileURL: livePaths.actionStoreURL)
        var handler: AgentAccessServer.Handler?
        let controller = AgentAccessController(
            appState: state,
            paths: livePaths,
            openAPIDocument: Data("{}".utf8),
            actionStore: actionStore
        ) { _, _, captured in
            handler = captured
            return ServerStub()
        }
        defer { try? FileManager.default.removeItem(at: livePaths.supportDirectory) }
        state.setAgentAccessEnabled(true)
        let didStart = await waitUntil { handler != nil && state.agentAccessPresentationState == .running }
        XCTAssertTrue(didStart)
        let request = AgentAccessActionRequest(
            requestID: "turn-on-1", action: .setLocalCorrectionsEnabled, enabled: true
        )
        let body = try JSONEncoder().encode(request)
        let created = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/actions", headers: [:], body: body
        ))
        XCTAssertEqual(created.status, 201)
        XCTAssertFalse(state.localCorrectionSnapshot.isEnabled)
        let didPublish = await waitUntil { state.agentAccessPendingActionCount == 1 }
        XCTAssertTrue(didPublish)
        let actionID = try XCTUnwrap(state.agentAccessActions.first?.id)
        XCTAssertEqual(try actionStore.load().records.first?.state, .pending)

        state.decideAgentAccessAction(id: actionID, approve: true)
        XCTAssertTrue(state.localCorrectionSnapshot.isEnabled)
        XCTAssertEqual(try actionStore.load().records.first?.state, .approved)
        let replay = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/actions", headers: [:], body: body
        ))
        XCTAssertEqual(replay.status, 200)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let replayBody = try decoder.decode(AgentAccessActionResponse.self, from: replay.body)
        XCTAssertTrue(replayBody.replayed)
        XCTAssertEqual(replayBody.state, .approved)
        let uppercaseStatus = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .get, path: "/v1/vocabulary/actions/\(actionID.uppercased())", headers: [:], body: Data()
        ))
        XCTAssertEqual(uppercaseStatus.status, 200)
        XCTAssertEqual(try decoder.decode(AgentAccessActionResponse.self, from: uppercaseStatus.body).actionID, actionID)
        state.decideAgentAccessAction(id: actionID, approve: true)
        XCTAssertEqual(try actionStore.load().revision, 3)

        let proposalBody = try JSONEncoder().encode(VocabularyProposalRequest(
            requestID: "proposal-for-action",
            scope: .init(kind: "global", id: "global"),
            corrections: [.init(spokenForms: ["super base"], replacement: "Supabase")]
        ))
        let proposalResponse = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/proposals", headers: [:], body: proposalBody
        ))
        XCTAssertEqual(proposalResponse.status, 201)
        let didPublishProposal = await waitUntil { state.agentAccessPendingProposalCount == 1 }
        XCTAssertTrue(didPublishProposal)
        let proposalID = try XCTUnwrap(state.agentAccessProposals.first?.id)
        let applyRequest = AgentAccessActionRequest(
            requestID: "apply-proposal-1", action: .applyProposal, proposalID: proposalID.uppercased()
        )
        let actionResponse = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/actions", headers: [:],
            body: try JSONEncoder().encode(applyRequest)
        ))
        XCTAssertEqual(actionResponse.status, 201)
        let canonicalReplay = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/actions", headers: [:],
            body: try JSONEncoder().encode(AgentAccessActionRequest(
                requestID: "apply-proposal-1", action: .applyProposal, proposalID: proposalID
            ))
        ))
        XCTAssertEqual(canonicalReplay.status, 200)
        XCTAssertTrue(state.vocabularyCorrections.isEmpty)
        let didPublishApply = await waitUntil { state.agentAccessPendingActionCount == 1 }
        XCTAssertTrue(didPublishApply)
        let applyActionID = try XCTUnwrap(state.agentAccessActions.first(where: {
            $0.request.requestID == "apply-proposal-1"
        })?.id)
        state.decideAgentAccessAction(id: applyActionID, approve: true)
        XCTAssertEqual(state.vocabularyCorrections.map(\.writtenAs), ["super base"])
        XCTAssertEqual(state.agentAccessProposals.first?.state, .applied)
        XCTAssertEqual(try actionStore.load().records.first(where: {
            $0.id == applyActionID
        })?.state, .approved)
        withExtendedLifetime(controller) {}
    }

    func testAgentCreatesExactAppGroupThenRescopesExistingGlobalProposalInPlace() async throws {
        let marker = UUID().uuidString
        let state = makeState(storageMarker: marker, activateCatalog: true)
        let originalGroups = state.cleanupGroups
        state.setCleanupGroups([.defaultGroup()])
        state.setAgentAccessEnabled(false, notifyController: false)
        let livePaths = paths()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-agent-exact-apps-\(marker)", isDirectory: true)
        let chatGPT = try makeAppFixture(root: root, name: "ChatGPT", bundleID: "com.openai.codex")
        let codex = try makeAppFixture(root: root, name: "Codex", bundleID: "com.openai.codex")
        let paths = [chatGPT.path, codex.path]
        let groupName = "ChatGPT and Codex \(marker)"
        var handler: AgentAccessServer.Handler?
        let controller = AgentAccessController(
            appState: state, paths: livePaths, openAPIDocument: Data("{}".utf8)
        ) { _, _, captured in
            handler = captured
            return ServerStub()
        }
        defer {
            state.setCleanupGroups(originalGroups)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: livePaths.supportDirectory)
        }
        state.setAgentAccessEnabled(true)
        let started = await waitUntil { handler != nil && state.agentAccessPresentationState == .running }
        XCTAssertTrue(started)
        let sendAction: (AgentAccessActionRequest) throws -> AgentAccessHTTPResponse = { request in
            try XCTUnwrap(handler)(AgentAccessHTTPRequest(
                method: .post, path: "/v1/vocabulary/actions", headers: [:],
                body: try JSONEncoder().encode(request)
            ))
        }
        let proposalRequest = VocabularyProposalRequest(
            requestID: "vercel-supabase-global",
            scope: .init(kind: "global", id: "global"),
            corrections: [
                .init(spokenForms: ["verse cell"], replacement: "Vercel"),
                .init(spokenForms: ["super base"], replacement: "Supabase")
            ]
        )
        let proposalResponse = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/proposals", headers: [:],
            body: try JSONEncoder().encode(proposalRequest)
        ))
        XCTAssertEqual(proposalResponse.status, 201)
        let proposalPublished = await waitUntil { state.agentAccessPendingProposalCount == 1 }
        XCTAssertTrue(proposalPublished)
        let proposalID = try XCTUnwrap(state.agentAccessProposals.first?.id)

        let groupRequest = AgentAccessActionRequest(
            requestID: "create-chatgpt-codex-group", action: .createCleanupGroup,
            groupName: groupName, appPaths: paths
        )
        let groupResponse = try sendAction(groupRequest)
        XCTAssertEqual(groupResponse.status, 201)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pendingGroup = try decoder.decode(AgentAccessActionResponse.self, from: groupResponse.body)
        XCTAssertEqual(pendingGroup.state, .pending)
        XCTAssertEqual(pendingGroup.groupID, pendingGroup.actionID)
        let initialGroupCount = state.cleanupGroups.count
        XCTAssertEqual(state.agentAccessProposals.first?.scope.kind, "global")
        XCTAssertTrue(state.vocabularyCorrections.isEmpty)
        let groupReplay = try sendAction(.init(
            requestID: groupRequest.requestID, action: .createCleanupGroup,
            groupName: groupName, appPaths: Array(paths.reversed())
        ))
        XCTAssertEqual(groupReplay.status, 200)
        let groupPublished = await waitUntil { state.agentAccessPendingActionCount == 1 }
        XCTAssertTrue(groupPublished)
        state.decideAgentAccessAction(id: pendingGroup.actionID, approve: true)
        let groupID = pendingGroup.actionID
        let group = try XCTUnwrap(state.cleanupGroups.first(where: { $0.id == groupID }))
        XCTAssertTrue(AgentAccessAppTargeting.hasExactlyThesePaths(group, paths: paths))
        XCTAssertEqual(state.cleanupGroups.count, initialGroupCount + 1)
        XCTAssertEqual(try AgentAccessActionStore(fileURL: livePaths.actionStoreURL).load().records.first?.state, .approved)

        let chatContext = CleanupAppContext(displayName: "ChatGPT", bundleIdentifier: "com.openai.codex", appPath: chatGPT.path)
        let codexContext = CleanupAppContext(displayName: "Codex", bundleIdentifier: "com.openai.codex", appPath: codex.path)
        let otherContext = CleanupAppContext(displayName: "Other", bundleIdentifier: "com.openai.codex", appPath: "/Applications/Other.app")
        let pathlessImpostor = CleanupAppContext(displayName: "ChatGPT", bundleIdentifier: "example.impostor", appPath: nil)
        XCTAssertEqual(state.resolveCleanupGroup(for: chatContext).group.id, groupID)
        XCTAssertEqual(state.resolveCleanupGroup(for: codexContext).group.id, groupID)
        XCTAssertEqual(state.resolveCleanupGroup(for: otherContext).group.id, CleanupGroup.defaultGroupID)
        XCTAssertEqual(state.resolveCleanupGroup(for: pathlessImpostor).group.id, CleanupGroup.defaultGroupID)

        let rescope = AgentAccessActionRequest(
            requestID: "rescope-vercel-supabase", action: .rescopeProposal,
            proposalID: proposalID, groupID: groupID, appPaths: paths
        )
        let rescopeResponse = try sendAction(rescope)
        XCTAssertEqual(rescopeResponse.status, 201)
        let pendingRescope = try decoder.decode(AgentAccessActionResponse.self, from: rescopeResponse.body)
        XCTAssertEqual(pendingRescope.groupID, groupID)
        XCTAssertEqual(state.agentAccessProposals.first?.scope.kind, "global")
        XCTAssertTrue(state.vocabularyCorrections.isEmpty)
        let rescopePublished = await waitUntil { state.agentAccessPendingActionCount == 1 }
        XCTAssertTrue(rescopePublished)
        state.applyAgentAccessProposal(id: proposalID)
        XCTAssertTrue(state.vocabularyCorrections.isEmpty)
        XCTAssertEqual(state.agentAccessProposals.first?.scope.kind, "global")
        XCTAssertTrue(state.agentAccessProposalInboxErrorMessage?.contains("scope change is awaiting review") == true)
        state.decideAgentAccessAction(id: pendingRescope.actionID, approve: true)
        let scoped = try XCTUnwrap(state.agentAccessProposals.first(where: { $0.id == proposalID }))
        XCTAssertEqual(scoped.scope, .init(kind: "cleanup_group", id: groupID))
        XCTAssertEqual(scoped.state, .pending)
        XCTAssertEqual(state.agentAccessProposals.filter { $0.state == .pending }.count, 1)
        XCTAssertTrue(state.vocabularyCorrections.isEmpty)
        XCTAssertEqual(try AgentAccessActionStore(fileURL: livePaths.actionStoreURL).load().records.first(where: {
            $0.id == pendingRescope.actionID
        })?.state, .approved)

        state.applyAgentAccessProposal(id: proposalID)
        XCTAssertEqual(state.agentAccessProposals.first?.state, .applied)
        XCTAssertEqual(state.vocabularyCorrections.count, 2)
        let compiled = try LocalCorrectionEngine.compile(state.localCorrectionSnapshot.rules)
        let phrase = "verse cell and super base"
        XCTAssertEqual(LocalCorrectionEngine.correct(phrase, activeGroup: groupID, enabled: true, compiled: compiled).text,
                       "Vercel and Supabase")
        XCTAssertEqual(LocalCorrectionEngine.correct(phrase, activeGroup: nil, enabled: true, compiled: compiled).text,
                       phrase)
        withExtendedLifetime(controller) {}
    }

    func testRescopeRequestFailsClosedIfGroupOrProposalChangedBeforeApproval() async throws {
        let marker = UUID().uuidString
        let state = makeState(storageMarker: marker, activateCatalog: true)
        let originalGroups = state.cleanupGroups
        state.setCleanupGroups([.defaultGroup()])
        state.setAgentAccessEnabled(false, notifyController: false)
        let livePaths = paths()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-agent-rescope-conflict-\(marker)", isDirectory: true)
        let app = try makeAppFixture(root: root, name: "ChatGPT", bundleID: "com.openai.codex")
        let group = state.createCleanupGroup(named: "Agent apps")
        state.addAppMatcher(CleanupAppMatcher(displayName: "ChatGPT", appPath: app.path), toCleanupGroupID: group.id)
        var handler: AgentAccessServer.Handler?
        let controller = AgentAccessController(
            appState: state, paths: livePaths, openAPIDocument: Data("{}".utf8)
        ) { _, _, captured in
            handler = captured
            return ServerStub()
        }
        defer {
            state.setCleanupGroups(originalGroups)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: livePaths.supportDirectory)
        }
        state.setAgentAccessEnabled(true)
        let started = await waitUntil { handler != nil && state.agentAccessPresentationState == .running }
        XCTAssertTrue(started)
        let proposal = VocabularyProposalRequest(
            requestID: "conflict-global", scope: .init(kind: "global", id: "global"),
            corrections: [.init(spokenForms: ["verse cell"], replacement: "Vercel")]
        )
        XCTAssertEqual(try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/proposals", headers: [:],
            body: try JSONEncoder().encode(proposal)
        )).status, 201)
        let proposalPublished = await waitUntil { state.agentAccessPendingProposalCount == 1 }
        XCTAssertTrue(proposalPublished)
        let proposalID = try XCTUnwrap(state.agentAccessProposals.first?.id)
        let request = AgentAccessActionRequest(
            requestID: "rescope-conflict", action: .rescopeProposal,
            proposalID: proposalID, groupID: group.id, appPaths: [app.path]
        )
        let response = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/actions", headers: [:],
            body: try JSONEncoder().encode(request)
        ))
        XCTAssertEqual(response.status, 201)
        let actionPublished = await waitUntil { state.agentAccessPendingActionCount == 1 }
        XCTAssertTrue(actionPublished)
        let actionID = try XCTUnwrap(state.agentAccessActions.first?.id)
        XCTAssertTrue(state.updateCleanupGroup(id: group.id) { $0.isEnabled = false })
        let replayResponse = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/actions", headers: [:],
            body: try JSONEncoder().encode(request)
        ))
        XCTAssertEqual(replayResponse.status, 200)
        let replayDecoder = JSONDecoder()
        replayDecoder.dateDecodingStrategy = .iso8601
        let replayReceipt = try replayDecoder.decode(AgentAccessActionResponse.self, from: replayResponse.body)
        XCTAssertEqual(replayReceipt.actionID, actionID)
        XCTAssertTrue(replayReceipt.replayed)
        XCTAssertTrue(state.updateCleanupGroup(id: group.id) { $0.isEnabled = true })
        state.addAppMatcher(CleanupAppMatcher(displayName: "Another", appPath: "/Applications/Another.app"),
                            toCleanupGroupID: group.id)
        state.decideAgentAccessAction(id: actionID, approve: true)
        XCTAssertEqual(state.agentAccessProposals.first?.scope.kind, "global")
        XCTAssertEqual(try AgentAccessActionStore(fileURL: livePaths.actionStoreURL).load().records.first?.state,
                       .approvedPendingApply)
        XCTAssertTrue(state.agentAccessActionErrorMessage?.contains("exactly the requested apps") == true)
        state.removeAppMatcher(membershipKey: "path:/applications/another.app", fromCleanupGroupID: group.id)
        state.reviseAgentAccessProposal(
            id: proposalID, scope: .init(kind: "global", id: "global"),
            corrections: [.init(spokenForms: ["verse cell"], replacement: "Different")]
        )
        state.decideAgentAccessAction(id: actionID, approve: true)
        XCTAssertEqual(state.agentAccessProposals.first?.scope.kind, "global")
        XCTAssertTrue(state.agentAccessActionErrorMessage?.contains("changed after") == true)
        XCTAssertEqual(try AgentAccessActionStore(fileURL: livePaths.actionStoreURL).load().records.first?.state,
                       .approvedPendingApply)
        withExtendedLifetime(controller) {}
    }

    func testGroupApprovalDoesNotMoveAnExistingPathAssignmentWithoutReview() throws {
        let marker = UUID().uuidString
        let state = makeState(storageMarker: marker, activateCatalog: true)
        let originalGroups = state.cleanupGroups
        state.setCleanupGroups([.defaultGroup()])
        let livePaths = paths()
        let actionStore = AgentAccessActionStore(fileURL: livePaths.actionStoreURL)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-agent-group-conflict-\(marker)", isDirectory: true)
        let chatGPT = try makeAppFixture(root: root, name: "ChatGPT", bundleID: "com.openai.codex")
        let existing = state.createCleanupGroup(named: "Existing app group \(marker)")
        state.addAppMatcher(CleanupAppMatcher(displayName: "ChatGPT", appPath: chatGPT.path),
                            toCleanupGroupID: existing.id)
        let controller = AgentAccessController(
            appState: state, paths: livePaths, openAPIDocument: Data("{}".utf8),
            actionStore: actionStore
        ) { _, _, _ in ServerStub() }
        defer {
            state.setCleanupGroups(originalGroups)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: livePaths.supportDirectory)
        }
        let action = try actionStore.submit(.init(
            requestID: "group-path-conflict", action: .createCleanupGroup,
            groupName: "New app group \(marker)", appPaths: [chatGPT.path]
        )).0
        controller.refreshActions()
        state.decideAgentAccessAction(id: action.id, approve: true)
        XCTAssertFalse(state.cleanupGroups.contains(where: { $0.id == action.id }))
        XCTAssertEqual(state.resolveCleanupGroup(for: .init(
            displayName: "ChatGPT", bundleIdentifier: "com.openai.codex", appPath: chatGPT.path
        )).group.id, existing.id)
        XCTAssertEqual(try actionStore.load().records.first?.state, .approvedPendingApply)
        XCTAssertTrue(state.agentAccessActionErrorMessage?.contains("already assigned") == true)
        state.removeAppMatcher(membershipKey: "path:\(chatGPT.path.lowercased())", fromCleanupGroupID: existing.id)
        state.decideAgentAccessAction(id: action.id, approve: true)
        XCTAssertEqual(state.resolveCleanupGroup(for: .init(
            displayName: "ChatGPT", bundleIdentifier: "com.openai.codex", appPath: chatGPT.path
        )).group.id, action.id)
        XCTAssertEqual(try actionStore.load().records.first?.state, .approved)
        withExtendedLifetime(controller) {}
    }

    func testInterruptedGroupCreationAndProposalRescopeReplayWithoutDuplicates() throws {
        let marker = UUID().uuidString
        let state = makeState(storageMarker: marker, activateCatalog: true)
        let originalGroups = state.cleanupGroups
        state.setCleanupGroups([.defaultGroup()])
        let livePaths = paths()
        let actionStore = AgentAccessActionStore(fileURL: livePaths.actionStoreURL)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-agent-scope-replay-\(marker)", isDirectory: true)
        let chatGPT = try makeAppFixture(root: root, name: "ChatGPT", bundleID: "com.openai.codex")
        let codex = try makeAppFixture(root: root, name: "Codex", bundleID: "com.openai.codex")
        let appPaths = [chatGPT.path, codex.path]
        let groupName = "ChatGPT and Codex \(marker)"
        let controller = AgentAccessController(
            appState: state, paths: livePaths, openAPIDocument: Data("{}".utf8),
            actionStore: actionStore
        ) { _, _, _ in ServerStub() }
        defer {
            state.setCleanupGroups(originalGroups)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: livePaths.supportDirectory)
        }
        let create = try actionStore.submit(.init(
            requestID: "create-before-interruption", action: .createCleanupGroup,
            groupName: groupName, appPaths: appPaths
        )).0
        _ = try actionStore.transition(id: create.id, to: .approvedPendingApply)
        _ = state.createCleanupGroup(named: groupName, id: create.id)
        state.addAppMatcher(CleanupAppMatcher(displayName: "ChatGPT", appPath: chatGPT.path),
                            toCleanupGroupID: create.id)
        controller.refreshActions()
        state.decideAgentAccessAction(id: create.id, approve: true)
        XCTAssertNil(state.agentAccessActionErrorMessage, state.agentAccessActionErrorMessage ?? "")
        XCTAssertEqual(state.cleanupGroups.filter { $0.id == create.id }.count, 1)
        XCTAssertTrue(AgentAccessAppTargeting.hasExactlyThesePaths(
            try XCTUnwrap(state.cleanupGroups.first(where: { $0.id == create.id })), paths: appPaths
        ))
        XCTAssertEqual(try actionStore.load().records.first?.state, .approved)

        controller.seedVocabularyProposalForUITesting()
        let proposal = try XCTUnwrap(state.agentAccessProposals.first)
        let desiredScope = VocabularyProposalScope(kind: "cleanup_group", id: create.id)
        let desiredDigest = try VocabularyProposalRequest(
            requestID: proposal.requestID, scope: desiredScope,
            corrections: proposal.corrections
        ).canonicalPayloadDigest()
        let rescope = try actionStore.submit(.init(
            requestID: "rescope-before-interruption", action: .rescopeProposal,
            proposalID: proposal.id, groupID: create.id, appPaths: appPaths
        ), targetDigest: proposal.requestHash, resultDigest: desiredDigest).0
        _ = try actionStore.transition(id: rescope.id, to: .approvedPendingApply)
        state.reviseAgentAccessProposal(
            id: proposal.id, scope: desiredScope, corrections: proposal.corrections
        )
        XCTAssertEqual(state.agentAccessProposals.first?.reviewHash, desiredDigest)
        controller.refreshActions()
        state.decideAgentAccessAction(id: rescope.id, approve: true)
        XCTAssertEqual(try actionStore.load().records.first(where: { $0.id == rescope.id })?.state,
                       .approved)
        XCTAssertEqual(state.agentAccessProposals.count, 1)
        XCTAssertEqual(state.agentAccessProposals.first?.scope, desiredScope)
        withExtendedLifetime(controller) {}
    }

    func testAgentCannotClaimApprovalOrChangeSettingsThroughStatusRoute() async throws {
        let state = makeState(storageMarker: UUID().uuidString, activateCatalog: true)
        state.setAgentAccessEnabled(false, notifyController: false)
        let livePaths = paths()
        var handler: AgentAccessServer.Handler?
        let controller = AgentAccessController(
            appState: state, paths: livePaths, openAPIDocument: Data("{}".utf8)
        ) { _, _, captured in
            handler = captured
            return ServerStub()
        }
        defer { try? FileManager.default.removeItem(at: livePaths.supportDirectory) }
        state.setAgentAccessEnabled(true)
        let didStart = await waitUntil { handler != nil && state.agentAccessPresentationState == .running }
        XCTAssertTrue(didStart)
        let body = Data(#"{"schema_version":1,"request_id":"claim-1","action":"set_local_corrections_enabled","enabled":true,"approved":true}"#.utf8)
        let created = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/actions", headers: [:], body: body
        ))
        XCTAssertEqual(created.status, 201)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(AgentAccessActionResponse.self, from: created.body)
        XCTAssertEqual(response.state, .pending)
        XCTAssertFalse(state.localCorrectionSnapshot.isEnabled)
        let direct = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/actions/\(response.actionID)", headers: [:], body: Data("{}".utf8)
        ))
        XCTAssertEqual(direct.status, 405)
        XCTAssertFalse(state.localCorrectionSnapshot.isEnabled)
        withExtendedLifetime(controller) {}
    }

    func testActionStoreRejectsChangedReplayAndPersistsRejectedAudit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-action-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("actions.json")
        let store = AgentAccessActionStore(fileURL: url)
        let original = AgentAccessActionRequest(
            requestID: "same-id", action: .setLocalCorrectionsEnabled, enabled: true
        )
        let first = try store.submit(original)
        XCTAssertFalse(first.1)
        XCTAssertTrue(try store.submit(original).1)
        XCTAssertThrowsError(try store.submit(.init(
            requestID: "same-id", action: .setLocalCorrectionsEnabled, enabled: false
        ))) { error in
            XCTAssertEqual(error as? AgentAccessActionError, .requestConflict)
        }
        _ = try store.transition(id: first.0.id, to: .rejected)
        let reloaded = try AgentAccessActionStore(fileURL: url).load()
        XCTAssertEqual(reloaded.records.first?.state, .rejected)
        XCTAssertEqual(reloaded.revision, 2)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testActionStoreRemainsReadableWhenClockMovesBackward() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-action-clock-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("actions.json")
        let first = AgentAccessActionStore(fileURL: url, now: { Date(timeIntervalSince1970: 2_000) })
        let approvedAction = try first.submit(.init(
            requestID: "clock-approval", action: .setLocalCorrectionsEnabled, enabled: true
        )).0
        let rejectedAction = try first.submit(.init(
            requestID: "clock-rejection", action: .setLocalCorrectionsEnabled, enabled: false
        )).0
        let backward = AgentAccessActionStore(fileURL: url, now: { Date(timeIntervalSince1970: 1_999) })
        _ = try backward.transition(id: approvedAction.id, to: .approvedPendingApply)
        _ = try backward.transition(id: approvedAction.id, to: .approved)
        _ = try backward.transition(id: rejectedAction.id, to: .rejected)

        let records = try AgentAccessActionStore(fileURL: url).load().records
        XCTAssertEqual(records.first(where: { $0.id == approvedAction.id })?.state, .approved)
        XCTAssertEqual(records.first(where: { $0.id == approvedAction.id })?.approvedAt, approvedAction.createdAt)
        XCTAssertEqual(records.first(where: { $0.id == rejectedAction.id })?.state, .rejected)
        XCTAssertTrue(records.allSatisfy { $0.createdAt <= $0.updatedAt })
        _ = try backward.submit(.init(
            requestID: "after-clock-change", action: .setLocalCorrectionsEnabled, enabled: true
        ))
        XCTAssertEqual(try first.load().records.count, 3)
    }

    func testApprovedScopeAndAppRoutingUseExistingFoilSetters() async throws {
        let marker = UUID().uuidString
        let state = makeState(storageMarker: marker, activateCatalog: true)
        state.setAgentAccessEnabled(false, notifyController: false)
        let earlierGroup = state.createCleanupGroup(named: "Earlier app match")
        let group = state.createCleanupGroup(named: "Agent tests")
        let correction = try XCTUnwrap(state.addVocabularyCorrection(
            writtenAs: "super base", correctVersion: "Supabase"
        ))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-agent-app-fixture-\(marker)", isDirectory: true)
        let appURL = root.appendingPathComponent("Test Editor.app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let bundleID = "com.example.FoilActionTest"
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleID, "CFBundleName": "Test Editor"],
            format: .xml, options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        state.addAppMatcher(
            CleanupAppMatcher(displayName: "Test Editor", appPath: appURL.path),
            toCleanupGroupID: earlierGroup.id
        )
        state.addAppMatcher(
            CleanupAppMatcher(displayName: "Test Editor"),
            toCleanupGroupID: earlierGroup.id
        )
        let appContext = CleanupAppContext(
            displayName: "Test Editor", bundleIdentifier: bundleID, appPath: appURL.path
        )
        let otherAppContext = CleanupAppContext(
            displayName: "Test Editor", bundleIdentifier: "com.example.OtherEditor",
            appPath: "/Applications/Other Editor.app"
        )
        XCTAssertEqual(state.resolveCleanupGroup(for: appContext).group.id, earlierGroup.id)
        XCTAssertEqual(state.resolveCleanupGroup(for: otherAppContext).group.id, earlierGroup.id)
        let livePaths = paths()
        var handler: AgentAccessServer.Handler?
        let controller = AgentAccessController(
            appState: state,
            paths: livePaths,
            openAPIDocument: Data("{}".utf8),
            appURLForBundleID: { $0 == bundleID ? appURL : nil }
        ) { _, _, captured in
            handler = captured
            return ServerStub()
        }
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: livePaths.supportDirectory)
        }
        state.setAgentAccessEnabled(true)
        let didStart = await waitUntil { handler != nil && state.agentAccessPresentationState == .running }
        XCTAssertTrue(didStart)
        for request in [
            AgentAccessActionRequest(
                requestID: "scope-1", action: .setCorrectionScope,
                correctionID: correction.id.uuidString.uppercased(), scopeID: group.id
            ),
            AgentAccessActionRequest(
                requestID: "app-1", action: .assignAppToGroup,
                appBundleID: bundleID, groupID: group.id
            )
        ] {
            let response = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
                method: .post, path: "/v1/vocabulary/actions", headers: [:],
                body: try JSONEncoder().encode(request)
            ))
            XCTAssertEqual(response.status, 201)
        }
        let didPublish = await waitUntil { state.agentAccessPendingActionCount == 2 }
        XCTAssertTrue(didPublish)
        XCTAssertNil(state.localCorrectionRule(forVocabularyCorrectionID: correction.id))
        XCTAssertTrue(state.cleanupGroups.first(where: { $0.id == group.id })?.appMatchers.isEmpty == true)

        let actions = state.agentAccessActions
        for action in actions { state.decideAgentAccessAction(id: action.id, approve: true) }
        XCTAssertEqual(state.localCorrectionRule(forVocabularyCorrectionID: correction.id)?.group, group.id)
        XCTAssertTrue(state.cleanupGroups.first(where: { $0.id == group.id })?.appMatchers.contains(where: {
            $0.bundleIdentifier == bundleID
        }) == true)
        XCTAssertEqual(state.resolveCleanupGroup(for: appContext).group.id, group.id)
        XCTAssertEqual(state.resolveCleanupGroup(for: otherAppContext).group.id, earlierGroup.id)
        XCTAssertEqual(state.cleanupGroups.first(where: { $0.id == earlierGroup.id })?.appMatchers.count, 2)
        XCTAssertEqual(state.agentAccessPendingActionCount, 0)
        XCTAssertTrue(try AgentAccessActionStore(fileURL: livePaths.actionStoreURL).load().records.allSatisfy {
            $0.state == .approved
        })
        let defaultRequest = AgentAccessActionRequest(
            requestID: "app-default-1", action: .assignAppToGroup,
            appBundleID: bundleID, groupID: CleanupGroup.defaultGroupID
        )
        let defaultResponse = try XCTUnwrap(handler)(AgentAccessHTTPRequest(
            method: .post, path: "/v1/vocabulary/actions", headers: [:],
            body: try JSONEncoder().encode(defaultRequest)
        ))
        XCTAssertEqual(defaultResponse.status, 201)
        let didPublishDefault = await waitUntil { state.agentAccessPendingActionCount == 1 }
        XCTAssertTrue(didPublishDefault)
        let defaultActionID = try XCTUnwrap(state.agentAccessActions.first(where: {
            $0.request.requestID == "app-default-1"
        })?.id)
        state.decideAgentAccessAction(id: defaultActionID, approve: true)
        XCTAssertEqual(state.resolveCleanupGroup(for: appContext).group.id, CleanupGroup.defaultGroupID)
        XCTAssertEqual(state.resolveCleanupGroup(for: otherAppContext).group.id, earlierGroup.id)
        XCTAssertTrue(state.cleanupGroups.first(where: { $0.id == CleanupGroup.defaultGroupID })?.appMatchers.contains {
            $0.bundleIdentifier == bundleID
        } == true)
        XCTAssertEqual(try AgentAccessActionStore(fileURL: livePaths.actionStoreURL).load().records.first(where: {
            $0.id == defaultActionID
        })?.state, .approved)
        withExtendedLifetime(controller) {}
    }

    func testLiveSocketActionRemainsInertUntilFoilDecision() async throws {
        let state = makeState(storageMarker: UUID().uuidString, activateCatalog: true)
        state.setAgentAccessEnabled(false, notifyController: false)
        let livePaths = paths()
        let controller = AgentAccessController(
            appState: state, paths: livePaths, openAPIDocument: Data("{}".utf8)
        )
        defer {
            controller.stop()
            try? FileManager.default.removeItem(at: livePaths.supportDirectory)
        }
        state.setAgentAccessEnabled(true)
        let didStart = await waitUntil {
            state.agentAccessPresentationState == .running
                && FileManager.default.fileExists(atPath: livePaths.socketURL.path)
        }
        XCTAssertTrue(didStart)
        let actionBody = Data(#"{"schema_version":1,"request_id":"live-toggle-1","action":"set_local_corrections_enabled","enabled":true}"#.utf8)
        let created = try sendHTTPRequest(
            to: livePaths.socketURL, method: "POST", path: "/v1/vocabulary/actions", body: actionBody
        )
        XCTAssertTrue(String(decoding: created, as: UTF8.self).contains("201 Created"))
        XCTAssertTrue(String(decoding: created, as: UTF8.self).contains("\"state\":\"pending\""))
        XCTAssertFalse(state.localCorrectionSnapshot.isEnabled)
        let didPublish = await waitUntil { state.agentAccessPendingActionCount == 1 }
        XCTAssertTrue(didPublish)
        let id = try XCTUnwrap(state.agentAccessActions.first?.id)
        state.decideAgentAccessAction(id: id, approve: true)
        XCTAssertTrue(state.localCorrectionSnapshot.isEnabled)
        let status = try sendHTTPRequest(
            to: livePaths.socketURL, method: "GET", path: "/v1/vocabulary/actions/\(id)"
        )
        XCTAssertTrue(String(decoding: status, as: UTF8.self).contains("\"state\":\"approved\""))
        state.setAgentAccessEnabled(false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: livePaths.socketURL.path))
        XCTAssertTrue(state.localCorrectionSnapshot.isEnabled)
    }

    func testChangedProposalCannotBeAppliedThroughEarlierAgentAction() throws {
        let state = makeState(storageMarker: UUID().uuidString, activateCatalog: true)
        let livePaths = paths()
        let actionStore = AgentAccessActionStore(fileURL: livePaths.actionStoreURL)
        let controller = AgentAccessController(
            appState: state, paths: livePaths, openAPIDocument: Data("{}".utf8),
            actionStore: actionStore
        ) { _, _, _ in ServerStub() }
        defer { try? FileManager.default.removeItem(at: livePaths.supportDirectory) }
        controller.seedVocabularyProposalForUITesting()
        let original = try XCTUnwrap(state.agentAccessProposals.first)
        let action = try actionStore.submit(.init(
            requestID: "apply-original", action: .applyProposal, proposalID: original.id
        ), targetDigest: original.reviewHash ?? original.requestHash).0
        state.reviseAgentAccessProposal(
            id: original.id,
            scope: .init(kind: "global", id: "global"),
            corrections: [.init(spokenForms: ["super base"], replacement: "Different value")]
        )
        XCTAssertNotEqual(state.agentAccessProposals.first?.reviewHash, action.targetDigest)
        state.decideAgentAccessAction(id: action.id, approve: true)
        XCTAssertTrue(state.vocabularyCorrections.isEmpty)
        XCTAssertEqual(try actionStore.load().records.first?.state, .approvedPendingApply)
        let approvalTime = try XCTUnwrap(actionStore.load().records.first?.approvedAt)
        XCTAssertTrue(state.agentAccessActionErrorMessage?.contains("changed after") == true)
        state.decideAgentAccessAction(id: action.id, approve: false)
        XCTAssertEqual(try actionStore.load().records.first?.state, .cancelledAfterApproval)
        XCTAssertEqual(try actionStore.load().records.first?.approvedAt, approvalTime)
        withExtendedLifetime(controller) {}
    }

    func testApprovedProposalActionReplaysCatalogReceiptAfterInterruptedFinalization() throws {
        let state = makeState(storageMarker: UUID().uuidString, activateCatalog: true)
        let livePaths = paths()
        let actionStore = AgentAccessActionStore(fileURL: livePaths.actionStoreURL)
        let controller = AgentAccessController(
            appState: state, paths: livePaths, openAPIDocument: Data("{}".utf8),
            actionStore: actionStore
        ) { _, _, _ in ServerStub() }
        defer { try? FileManager.default.removeItem(at: livePaths.supportDirectory) }
        controller.seedVocabularyProposalForUITesting()
        let proposal = try XCTUnwrap(state.agentAccessProposals.first)
        let action = try actionStore.submit(.init(
            requestID: "apply-before-interruption", action: .applyProposal, proposalID: proposal.id
        ), targetDigest: proposal.reviewHash ?? proposal.requestHash).0
        _ = try actionStore.transition(id: action.id, to: .approvedPendingApply)
        // This is the durable state after a catalog save but before finalizing
        // the action audit (for example, if Foil exits between the two writes).
        state.applyAgentAccessProposal(id: proposal.id)
        XCTAssertEqual(state.agentAccessProposals.first?.state, .applied)
        XCTAssertEqual(try actionStore.load().records.first?.state, .approvedPendingApply)
        XCTAssertEqual(state.vocabularyCorrections.map(\.writtenAs), ["super base", "Superbase", "codecs"])

        controller.refreshActions()
        state.decideAgentAccessAction(id: action.id, approve: true)

        XCTAssertEqual(try actionStore.load().records.first?.state, .approved)
        XCTAssertEqual(state.vocabularyCorrections.map(\.writtenAs), ["super base", "Superbase", "codecs"])
        XCTAssertNil(state.agentAccessActionErrorMessage)
        withExtendedLifetime(controller) {}
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
        initialDefaultsOverride: UserDefaults? = nil,
        activateCatalog: Bool = false
    ) -> AppState {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-agent-controller-\(storageMarker)", isDirectory: true)
        let defaults = agentAccessDefaults ?? UserDefaults(
            suiteName: "com.neonwatty.Foil.AgentAccessTests.\(UUID().uuidString)"
        )!
        return AppState(
            localCorrectionStore: LocalCorrectionStore(fileURL: root.appendingPathComponent("rules.json")),
            vocabularyCatalogStore: activateCatalog
                ? VocabularyCatalogStore(fileURL: root.appendingPathComponent(VocabularyCatalogStore.fileName))
                : nil,
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

    private func makeAppFixture(root: URL, name: String, bundleID: String) throws -> URL {
        let appURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": bundleID,
                "CFBundleName": name,
                "CFBundleDisplayName": name
            ],
            format: .xml, options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        return appURL
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
