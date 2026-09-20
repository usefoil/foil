import XCTest
@testable import Foil

final class ManagedLocalProviderMigrationTests: XCTestCase {
    @MainActor
    func testManagedIntentNeverStartsLegacyFixedPortServer() {
        XCTAssertFalse(AppDelegate.shouldStartLegacyLocalWhisperServer(
            isTesting: false,
            isE2ESmoke: false,
            effectiveMode: .managedLocal,
            autoStart: true
        ))
        XCTAssertTrue(AppDelegate.shouldStartLegacyLocalWhisperServer(
            isTesting: false,
            isE2ESmoke: false,
            effectiveMode: .externalLocal,
            autoStart: true
        ))
    }

    @MainActor
    func testReturningToManagedModeRefreshesMissingSelectionRecoveryWithoutStartingOrDownloading() async throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
            try? FileManager.default.removeItem(at: root)
        }
        defaults.removePersistentDomain(forName: domain)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"installed":["base.en"],"selectedID":"base.en"}"#.utf8)
            .write(to: root.appendingPathComponent("inventory.json"))
        let store = try ManagedLocalModelStore(root: root)
        let state = AppState(managedModelStore: store)
        XCTAssertNil(state.managedLocalModels?.selectedID)

        state.selectTranscriptionMode(.externalLocal)
        state.selectTranscriptionMode(.managedLocal)
        for _ in 0..<100 where state.managedLocalModels?.selectedID == nil {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(state.managedLocalModels?.selectedID, "base.en")
        XCTAssertTrue(state.managedLocalModels?.installed.isEmpty == true)
        XCTAssertFalse(state.managedLocalModels?.recovery.isEmpty ?? true)
        XCTAssertNil(state.managedLocalRuntime.session)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["inventory.json"])
    }

    @MainActor
    func testReselectingRequestedManagedModeDoesNotCancelInFlightOperation() async throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
            try? FileManager.default.removeItem(at: root)
        }
        defaults.removePersistentDomain(forName: domain)
        let state = AppState(managedModelRoot: root)
        state.managedLocalRequested = true
        state.managedLocalModels?.configureForUITesting(
            state: .downloading("base.en", 1_048_576, 147_964_211),
            candidateID: "base.en"
        )

        state.selectTranscriptionMode(.managedLocal)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(state.managedLocalModels?.state,
                       .downloading("base.en", 1_048_576, 147_964_211))
        XCTAssertEqual(state.managedLocalModels?.candidateID, "base.en")
    }

    @MainActor
    func testFirstRunManagedRecommendationPreservesUnderlyingProviderAndStaysUnready() throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        defer {
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
        }
        defaults.removePersistentDomain(forName: domain)

        let state = AppState()
        XCTAssertEqual(state.selectedTranscriptionProviderPresetID, .groq)

        state.recommendLocalForFirstRun()

        XCTAssertEqual(state.selectedTranscriptionProviderPresetID, .groq,
            "Managed-first onboarding must preserve the underlying legacy provider")
        XCTAssertTrue(state.selectedTranscriptionProvider.isManagedLocal,
            "The effective provider must be managed even before a model is installed")
        XCTAssertFalse(state.managedLocalEnabled,
            "Recommendation is intent, not a completed activation")
        XCTAssertFalse(state.isSetupReady,
            "Managed intent without an owned session must not advance setup")
    }

    @MainActor
    func testEffectiveModeSelectionIsCoherentAndLeavesManagedModeExplicitly() throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        defer {
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
        }
        defaults.removePersistentDomain(forName: domain)
        let state = AppState()

        state.selectTranscriptionMode(.managedLocal)
        XCTAssertEqual(state.effectiveTranscriptionMode, .managedLocal)
        XCTAssertEqual(state.selectedTranscriptionProviderPresetID, .groq)
        XCTAssertTrue(state.selectedTranscriptionProvider.isManagedLocal)

        state.selectTranscriptionMode(.externalLocal)
        XCTAssertEqual(state.effectiveTranscriptionMode, .externalLocal)
        XCTAssertEqual(state.selectedTranscriptionProviderPresetID, .localWhisperCPP)
        XCTAssertFalse(state.managedLocalRequested)
        XCTAssertFalse(state.selectedTranscriptionProvider.isManagedLocal)

        state.selectTranscriptionMode(.openAI)
        XCTAssertEqual(state.effectiveTranscriptionMode, .openAI)
        XCTAssertEqual(state.selectedTranscriptionProviderPresetID, .openAIWhisper)
    }

    @MainActor
    func testAcceptanceConfigurationIsExplicitAndKeepsProductionExecution() throws {
        let root = "/tmp/foil-managed-gui-fixture"
        let configuration = try XCTUnwrap(AppDelegate.managedLocalAcceptanceConfiguration(
            arguments: ["Foil Dev", "--managed-local-gui-acceptance"],
            environment: ["FOIL_MANAGED_LOCAL_ACCEPTANCE_ROOT": root]
        ))
        XCTAssertEqual(configuration.modelRoot.path, root + "/ManagedModels")
        XCTAssertEqual(configuration.historyRoot.path, root + "/History")
        XCTAssertEqual(configuration.credentialsRoot.path, root + "/Credentials")
        XCTAssertEqual(
            configuration.localCorrectionsFile.path,
            root + "/LocalCorrections/" + LocalCorrectionStore.fileName
        )
        XCTAssertFalse(AppDelegate.isTestingProcess(
            arguments: ["Foil Dev", "--managed-local-gui-acceptance"], environment: [:]
        ), "Acceptance must retain production permission, microphone, installer, and restoration behavior")
        XCTAssertNil(AppDelegate.managedLocalAcceptanceConfiguration(
            arguments: ["Foil Dev"], environment: ["FOIL_MANAGED_LOCAL_ACCEPTANCE_ROOT": root]
        ), "The isolated configuration must require an explicit DEBUG launch argument")
    }

    @MainActor
    func testManagedConnectionIgnoresInvalidPreservedCustomURL() async throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        defer {
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
        }
        let state = AppState()
        defer { state.managedLocalRuntime.stop() }
        state.selectedTranscriptionProviderPresetID = .customOpenAICompatible
        state.customTranscriptionBaseURL = "not a URL"
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ggml-tiny.en", withExtension: "bin"))
        let model = try ManagedLocalModel.verify(url: url, id: "tiny.en", size: 77_704_715,
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f")
        _ = try await state.managedLocalRuntime.start(model: model)
        state.activateManagedLocalModel(model)
        let transport = RejectingTransport()
        await state.testSelectedProviderConnection(service: TranscriptionService(transport: transport))
        guard case .succeeded(let message) = state.providerConnectionTestState else {
            return XCTFail("Owned managed session must validate despite preserved invalid external URL: \(state.providerConnectionTestState)")
        }
        XCTAssertTrue(message.contains("tiny.en"), message)
        XCTAssertFalse(message.contains("whisper-1"), message)
        XCTAssertFalse(message.contains("token"), message)
        XCTAssertEqual(transport.calls, 0)
        XCTAssertEqual(state.customTranscriptionBaseURL, "not a URL")
    }

    @MainActor
    func testManagedConnectionSuccessExpiresWhenSessionStopsOrIsReplaced() async throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        defaults.removePersistentDomain(forName: domain)
        let state = AppState()
        defer {
            state.managedLocalRuntime.stop()
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ggml-tiny.en", withExtension: "bin"))
        let model = try ManagedLocalModel.verify(url: url, id: "tiny.en", size: 77_704_715,
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f")
        _ = try await state.managedLocalRuntime.start(model: model)
        state.activateManagedLocalModel(model)
        state.providerConnectionTestState = .succeeded("Owned local session ready")

        state.managedLocalRuntime.stop()
        XCTAssertEqual(state.providerConnectionTestState, .idle)

        _ = try await state.managedLocalRuntime.start(model: model)
        state.providerConnectionTestState = .succeeded("Owned local session ready")
        _ = try await state.managedLocalRuntime.start(model: model)
        XCTAssertEqual(state.providerConnectionTestState, .idle,
            "Success from a prior owned session must not describe its replacement")
    }

    @MainActor
    func testManagedValidationCompletionWithoutActiveModelNeverPublishesGenericSuccess() async throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        defaults.removePersistentDomain(forName: domain)
        let state = AppState()
        defer {
            state.managedLocalRuntime.stop()
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ggml-tiny.en", withExtension: "bin"))
        let model = try ManagedLocalModel.verify(url: url, id: "tiny.en", size: 77_704_715,
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f")
        _ = try await state.managedLocalRuntime.start(model: model)
        state.activateManagedLocalModel(model)
        state.providerConnectionValidationDidComplete = { state.managedLocalRuntime.stop() }

        await state.testSelectedProviderConnection()
        XCTAssertNotEqual(state.providerConnectionTestState,
                          .succeeded("Server reachable. Model tiny.en is available."))
        XCTAssertEqual(state.providerConnectionTestState, .idle)
    }

    @MainActor
    func testConnectionResultIsDiscardedWhenProviderIdentityChanges() async throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        defer {
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
        }
        defaults.removePersistentDomain(forName: domain)
        let state = AppState()
        state.selectTranscriptionMode(.externalLocal)
        let transport = SuspendedValidationTransport()
        let task = Task { await state.testSelectedProviderConnection(
            service: TranscriptionService(transport: transport)
        ) }
        await transport.waitUntilRequested()
        state.selectTranscriptionMode(.custom)
        transport.resume(status: 200)
        await task.value
        XCTAssertEqual(state.providerConnectionTestState, .idle,
            "A response for the prior provider must not overwrite the current provider state")
    }

    @MainActor
    func testConnectionFailureIsDiscardedWhenProviderIdentityChanges() async throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        defer {
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
        }
        defaults.removePersistentDomain(forName: domain)
        let state = AppState()
        state.selectTranscriptionMode(.externalLocal)
        let transport = SuspendedValidationTransport()
        let task = Task { await state.testSelectedProviderConnection(
            service: TranscriptionService(transport: transport)
        ) }
        await transport.waitUntilRequested()
        state.selectTranscriptionMode(.openAI)
        transport.fail(URLError(.cannotConnectToHost))
        await task.value
        XCTAssertEqual(state.providerConnectionTestState, .idle,
            "A failure for the prior provider must not overwrite the current provider state")
    }

    @MainActor
    func testExplicitRestorePersistsManagedEligibilityAndCloudSelectionStopsOwnedChild() async throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        let root = try copyVerifiedAcceptanceModels()
        defer {
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
            try? FileManager.default.removeItem(at: root)
        }
        defaults.removePersistentDomain(forName: domain)
        let state = AppState(managedModelStore: try ManagedLocalModelStore(root: root))
        defer { state.managedLocalRuntime.stop() }
        state.selectTranscriptionMode(.externalLocal)
        state.selectTranscriptionMode(.managedLocal)

        try await state.restoreManagedLocalModel()
        XCTAssertTrue(state.managedLocalEnabled)
        XCTAssertTrue(state.managedLocalRequested)
        XCTAssertTrue(defaults.bool(forKey: "managedLocalEnabled"))
        XCTAssertTrue(defaults.bool(forKey: "managedLocalRequested"))
        XCTAssertEqual(state.selectedTranscriptionProviderPresetID, .localWhisperCPP,
            "Restore must preserve the underlying external provider choice")
        XCTAssertEqual(state.managedLocalModels?.activeID, "base")

        state.selectTranscriptionMode(.openAI)
        XCTAssertNil(state.managedLocalRuntime.session)
        XCTAssertFalse(state.managedLocalEnabled)
        XCTAssertFalse(state.managedLocalRequested)
        XCTAssertEqual(state.effectiveTranscriptionMode, .openAI)
    }

    private func copyVerifiedAcceptanceModels() throws -> URL {
        guard let fixture = ProcessInfo.processInfo.environment["FOIL_MANAGED_REVIEW_FIXTURE_ROOT"],
              !fixture.isEmpty else {
            throw XCTSkip("Non-live provisioned model review skipped: TEST_RUNNER_FOIL_MANAGED_REVIEW_FIXTURE_ROOT is absent")
        }
        let sourceRoot = URL(fileURLWithPath: fixture)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let catalog = try ManagedLocalModelCatalog.bundled()
        for id in ["base.en", "base"] {
            let entry = try catalog.model(id)
            let filename = "5359861c739e955e79d9a303bcbc70fb988958b1-\(entry.sha256)-\(id).bin"
            let source = sourceRoot.appendingPathComponent(filename)
            _ = try ManagedLocalModel.verify(url: source, id: id, size: entry.bytes, sha256: entry.sha256)
            let destination = root.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: source, to: destination)
            _ = try ManagedLocalModel.verify(url: destination, id: id, size: entry.bytes, sha256: entry.sha256)
        }
        try FileManager.default.copyItem(at: sourceRoot.appendingPathComponent("inventory.json"),
                                         to: root.appendingPathComponent("inventory.json"))
        return root
    }

    @MainActor
    func testManagedModeWithoutAnActiveSessionIsNotSetupReady() throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        defer {
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
        }
        let state = AppState()
        state.managedLocalEnabled = true
        state.accessibilityState = .ready
        state.microphoneState = .ready
        state.refreshApiKeyState()
        XCTAssertFalse(state.isSetupReady, "A missing/offline-corrupt managed model must not claim Ready")
    }

    @MainActor
    func testProviderChangeCancelsInitialDownloadBeforeManagedModeIsEnabled() async throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
            try? FileManager.default.removeItem(at: root)
            PendingModelDownload.started = nil
        }
        defaults.set(false, forKey: "managedLocalEnabled")
        let started = expectation(description: "Production downloader received response")
        PendingModelDownload.started = { started.fulfill() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingModelDownload.self]
        let store = try ManagedLocalModelStore(root: root, capacity: { _ in 1_000_000_000 }, configuration: configuration)
        let state = AppState(managedModelStore: store)
        let task = Task { try await state.installAndSelectManagedLocalModel("base.en") }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertFalse(state.managedLocalEnabled)
        state.selectedTranscriptionProviderPresetID = .openAIWhisper
        XCTAssertEqual(state.managedLocalModels?.state, .cancelled,
            "A provider choice must invalidate an initial candidate even before managed mode is enabled")
        task.cancel()
        _ = try? await task.value
        XCTAssertFalse(state.managedLocalEnabled)
        XCTAssertNil(state.managedLocalRuntime.session)
        XCTAssertEqual(state.selectedTranscriptionProviderPresetID, .openAIWhisper)
        let recovered = try await store.reconstruct()
        XCTAssertTrue(recovered.installed.isEmpty)
        XCTAssertNil(recovered.selectedID)
        XCTAssertFalse(recovered.recovery.isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("partial-") })
        let inactive = store.installationURL(try store.catalog.model("base"))
        try Data("corrupt inactive model".utf8).write(to: inactive)
        try await state.removeManagedLocalModel("base")
        XCTAssertFalse(FileManager.default.fileExists(atPath: inactive.path),
            "A completed cancellation must release the operation before explicit inactive-file removal")
    }

    @MainActor
    func testLegacyManagedMetadataCannotAuthorizeArbitraryModelFile() throws {
        let defaults = UserDefaults.standard
        let prior = defaults.object(forKey: "managedLocalModel")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            if let prior { defaults.set(prior, forKey: "managedLocalModel") }
            else { defaults.removeObject(forKey: "managedLocalModel") }
            try? FileManager.default.removeItem(at: url)
        }
        try Data("abc".utf8).write(to: url)
        defaults.set(["path": url.path, "id": "base.en", "size": "3",
            "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"], forKey: "managedLocalModel")
        XCTAssertThrowsError(try AppState().savedManagedLocalModel(),
            "Preference-provided metadata must not authorize a file outside the managed catalog/store")
    }

    @MainActor
    func testManagedActivationRefreshesReadinessAndDeactivationRestoresCloudRequirements() async throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        let previousStorage = KeychainHelper.storageDirectoryOverride
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)
        KeychainHelper.storageDirectoryOverride = storage
        defer {
            KeychainHelper.storageDirectoryOverride = previousStorage
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
            try? FileManager.default.removeItem(at: storage)
        }
        defaults.set(false, forKey: "managedLocalEnabled")
        let state = AppState()
        defer { state.managedLocalRuntime.stop() }
        state.selectedTranscriptionProviderPresetID = .groq
        state.accessibilityState = .ready
        state.microphoneState = .ready
        state.refreshApiKeyState()
        guard case .needsAction = state.apiKeyState else { return XCTFail("Missing cloud key should need action") }
        XCTAssertFalse(state.isSetupReady)
        state.providerConnectionTestState = .failed("Old provider failed")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ggml-tiny.en", withExtension: "bin"))
        let model = try ManagedLocalModel.verify(url: url, id: "tiny.en", size: 77_704_715,
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f")
        _ = try await state.managedLocalRuntime.start(model: model)
        state.activateManagedLocalModel(model)
        XCTAssertEqual(state.apiKeyState, .ready)
        XCTAssertTrue(state.isSetupReady)
        XCTAssertEqual(state.providerConnectionTestState, .idle)
        XCTAssertNil(state.selectedProviderApiKey)
        state.providerConnectionTestState = .succeeded("Managed session ready")
        state.deactivateManagedLocalModel()
        guard case .needsAction = state.apiKeyState else { return XCTFail("Deactivation must restore missing cloud key requirement") }
        XCTAssertFalse(state.isSetupReady)
        XCTAssertEqual(state.providerConnectionTestState, .idle)
        XCTAssertEqual(state.selectedTranscriptionProviderPresetID, .groq)
    }

    @MainActor
    func testExplicitLegacyProviderSelectionLeavesManagedModeAndPreservesCustomChoices() throws {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let prior = defaults.persistentDomain(forName: domain)
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)
        let previousStorage = KeychainHelper.storageDirectoryOverride
        let previousService = KeychainHelper.serviceOverride
        let previousAccount = KeychainHelper.accountOverride
        KeychainHelper.storageDirectoryOverride = storage
        KeychainHelper.serviceOverride = "com.usefoil.managed-migration.\(UUID().uuidString)"
        KeychainHelper.accountOverride = "managed-migration"
        defer {
            KeychainHelper.storageDirectoryOverride = previousStorage
            KeychainHelper.serviceOverride = previousService
            KeychainHelper.accountOverride = previousAccount
            if let prior { defaults.setPersistentDomain(prior, forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
            try? FileManager.default.removeItem(at: storage)
        }
        defaults.removeObject(forKey: "managedLocalEnabled")
        let state = AppState()
        XCTAssertFalse(state.managedLocalEnabled)
        state.customTranscriptionBaseURL = "http://127.0.0.1:9876/v1"
        state.customTranscriptionModel = "my-existing-model"
        for preset in TranscriptionProviderPresetID.allCases {
            state.managedLocalEnabled = true
            XCTAssertFalse(state.selectedProviderUsesSharedApiKey)
            state.selectedTranscriptionProviderPresetID = preset
            XCTAssertFalse(state.managedLocalEnabled)
            XCTAssertFalse(state.selectedTranscriptionProvider.isManagedLocal)
            XCTAssertEqual(state.customTranscriptionBaseURL, "http://127.0.0.1:9876/v1")
            XCTAssertEqual(state.customTranscriptionModel, "my-existing-model")
        }
    }

    func testUnreadyManagedProviderCannotUseInjectedExternalTransport() async throws {
        let provider = TranscriptionProvider.managedLocal(session: nil)
        let transport = RejectingTransport()
        let service = TranscriptionService(provider: provider, transport: transport)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data([1, 2, 3]).write(to: file)
        do {
            _ = try await service.transcribe(audioFileURL: file, apiKey: nil, model: "whisper-1")
            XCTFail("Unready managed provider accepted transcription")
        } catch {
            XCTAssertEqual(error as? ManagedLocalError, .notReady)
        }
        XCTAssertEqual(transport.calls, 0)
    }

    func testManagedValidationRejectsMissingSessionWithoutGenericHTTPFallback() async throws {
        for status in [200, 404, 405] {
            let transport = ValidationTransport(status: status)
            let service = TranscriptionService(provider: .managedLocal(session: nil), transport: transport)
            do {
                _ = try await service.validateProviderConfiguration(apiKey: "must-not-send")
                XCTFail("Missing managed session accepted generic HTTP \(status)")
            } catch { XCTAssertEqual(error as? ManagedLocalError, .notReady) }
            XCTAssertEqual(transport.calls, 0)
        }
    }

    private final class ValidationTransport: TranscriptionTransport {
        let status: Int
        var calls = 0
        init(status: Int) { self.status = status }
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            calls += 1
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private final class RejectingTransport: TranscriptionTransport {
        var calls = 0
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            calls += 1
            throw URLError(.cannotConnectToHost)
        }
    }

    private final class SuspendedValidationTransport: TranscriptionTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var requested = false
        private var waiter: CheckedContinuation<Void, Never>?
        private var response: CheckedContinuation<(Data, URLResponse), Error>?

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lock.lock(); requested = true
            let waiter = self.waiter; self.waiter = nil
            lock.unlock(); waiter?.resume()
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock(); response = continuation; lock.unlock()
            }
        }

        func waitUntilRequested() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if requested { lock.unlock(); continuation.resume() }
                else { waiter = continuation; lock.unlock() }
            }
        }

        func resume(status: Int) {
            lock.lock(); let continuation = response; response = nil; lock.unlock()
            let url = URL(string: "http://127.0.0.1:8080/v1/models")!
            continuation?.resume(returning: (Data(#"{"data":[]}"#.utf8),
                HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!))
        }

        func fail(_ error: Error) {
            lock.lock(); let continuation = response; response = nil; lock.unlock()
            continuation?.resume(throwing: error)
        }
    }
}

private final class PendingModelDownload: URLProtocol {
    static var started: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "147964211"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([0]))
        Self.started?()
    }
    override func stopLoading() {}
}
