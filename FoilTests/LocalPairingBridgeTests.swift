import XCTest
@testable import Foil

@MainActor
final class LocalPairingBridgeTests: XCTestCase {
    private var logURL: URL!

    override func setUpWithError() throws {
        clearDefaults()
        logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilLocalBridgeTests-\(UUID().uuidString).log")
        DiagnosticLog.logURLOverride = logURL
        DiagnosticLog.isEnabledOverride = true
        DiagnosticLog.clearForTesting()
    }

    override func tearDown() {
        DiagnosticLog.clearForTesting()
        DiagnosticLog.logURLOverride = nil
        DiagnosticLog.isEnabledOverride = nil
        try? FileManager.default.removeItem(at: logURL)
        logURL = nil
        clearDefaults()
    }

    func testBridgeIsOffByDefaultAndDoesNotAdvertise() {
        let state = AppState()
        let service = state.localPairingBridgeService

        XCTAssertFalse(state.localBridgeEnabled)
        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(service.isAdvertising)
        XCTAssertThrowsError(try service.beginPairing()) { error in
            XCTAssertEqual(error as? LocalPairingBridgeServiceError, .disabled)
        }
    }

    func testPairingSessionUsesContractShapeWhenEnabled() throws {
        let state = AppState()
        state.localBridgeEnabled = true

        let session = try state.localPairingBridgeService.beginPairing(
            macPeerID: "mac-peer-public-id",
            host: "mac.local",
            port: 49_321,
            code: "123456",
            pairingNonce: "base64url-random"
        )

        XCTAssertEqual(session.protocol, "foil.localBridge")
        XCTAssertEqual(session.version, 1)
        XCTAssertEqual(session.macPeerID, "mac-peer-public-id")
        XCTAssertEqual(session.pairingNonce, "base64url-random")
        XCTAssertEqual(session.host, "mac.local")
        XCTAssertEqual(session.port, 49_321)
        XCTAssertEqual(session.code, "123456")
        XCTAssertEqual(state.localPairingBridgeService.pairingState, .pairing)
    }

    func testCapabilitiesHandshakeUsesSelectedMacRouteAndNoCredentialOffer() throws {
        let state = AppState()
        state.localBridgeEnabled = true
        state.selectedTranscriptionProviderPresetID = .localWhisperCPP

        let advertisement = try state.localPairingBridgeService.advertisement(
            deviceName: "Test Mac",
            appState: state
        )
        XCTAssertEqual(advertisement.bonjourType, "_foil-bridge._tcp.local")
        XCTAssertEqual(advertisement.txt["protocol"], "foil.localBridge")
        XCTAssertEqual(advertisement.txt["version"], "1")
        XCTAssertEqual(advertisement.txt["supportsLocalTranscription"], "true")
        XCTAssertEqual(advertisement.txt["supportsCredentialOffer"], "false")

        let response = try state.localPairingBridgeService.capabilities(
            for: LocalBridgeCapabilitiesRequest(iosAppVersion: "0.1.0", requestID: "request-1"),
            appState: state,
            appVersion: "1.13.4"
        )

        XCTAssertEqual(response.type, "CapabilitiesResponse")
        XCTAssertEqual(response.protocol, "foil.localBridge")
        XCTAssertEqual(response.version, 1)
        XCTAssertEqual(response.requestID, "request-1")
        XCTAssertEqual(response.macAppVersion, "1.13.4")
        XCTAssertEqual(response.selectedRouteID, .localWhisperCPP)
        XCTAssertEqual(response.maxAudioBytes, 26_214_400)
        XCTAssertEqual(response.acceptedAudioFormats, ["m4a", "wav", "flac"])
        XCTAssertTrue(response.routes.contains(LocalBridgeRouteCapability(
            routeID: .localWhisperCPP,
            displayName: "Local whisper.cpp",
            available: true,
            privacyClass: .local
        )))
    }

    func testRouteReceiptResolvesMacDefaultCleanupAndKeepsLocalAudioOutOfCloud() {
        let state = AppState()
        state.selectedTranscriptionProviderPresetID = .localWhisperCPP
        state.transcriptCleanupProviderID = .none

        let receipt = LocalPairingBridgeService.routeReceipt(
            requestedRouteID: .macSelected,
            requestedCleanupRouteID: .macDefault,
            appState: state,
            macDeviceName: "Test Mac",
            completedAt: "2026-06-09T19:00:00Z"
        )

        XCTAssertEqual(receipt.routeID, .localWhisperCPP)
        XCTAssertEqual(receipt.routeDisplayName, "Local whisper.cpp")
        XCTAssertEqual(receipt.transcriptionLocation, .pairedMac)
        XCTAssertEqual(receipt.providerLocation, .localMac)
        XCTAssertEqual(receipt.cleanupRouteID, .none)
        XCTAssertTrue(receipt.audioLeftIPhone)
        XCTAssertTrue(receipt.audioReachedMac)
        XCTAssertFalse(receipt.audioReachedCloudProvider)
        XCTAssertFalse(receipt.textReachedCloudProvider)
        XCTAssertEqual(receipt.macDeviceName, "Test Mac")
        XCTAssertEqual(receipt.completedAt, "2026-06-09T19:00:00Z")
    }

    func testCapabilityAndReceiptJSONUseContractKeysAndValues() throws {
        let state = AppState()
        state.localBridgeEnabled = true
        state.selectedTranscriptionProviderPresetID = .localWhisperCPP
        state.transcriptCleanupProviderID = .none

        let capabilities = try state.localPairingBridgeService.capabilities(
            for: LocalBridgeCapabilitiesRequest(iosAppVersion: "0.1.0", requestID: "json-request"),
            appState: state,
            appVersion: "1.13.4"
        )
        let capabilitiesJSON = try jsonObject(from: capabilities)

        XCTAssertEqual(capabilitiesJSON["type"] as? String, "CapabilitiesResponse")
        XCTAssertEqual(capabilitiesJSON["protocol"] as? String, "foil.localBridge")
        XCTAssertEqual(capabilitiesJSON["version"] as? Int, 1)
        XCTAssertEqual(capabilitiesJSON["selectedRouteID"] as? String, "local-whisper-cpp")
        XCTAssertEqual(capabilitiesJSON["acceptedAudioFormats"] as? [String], ["m4a", "wav", "flac"])

        let receipt = LocalPairingBridgeService.routeReceipt(
            requestedRouteID: .macSelected,
            requestedCleanupRouteID: .macDefault,
            appState: state,
            macDeviceName: "Test Mac",
            completedAt: "2026-06-09T19:00:00Z"
        )
        let receiptJSON = try jsonObject(from: receipt)

        XCTAssertEqual(receiptJSON["routeID"] as? String, "local-whisper-cpp")
        XCTAssertEqual(receiptJSON["transcriptionLocation"] as? String, "pairedMac")
        XCTAssertEqual(receiptJSON["providerLocation"] as? String, "localMac")
        XCTAssertEqual(receiptJSON["cleanupRouteID"] as? String, "none")
        XCTAssertEqual(receiptJSON["audioReachedCloudProvider"] as? Bool, false)
        XCTAssertFalse(receiptJSON.values.contains { "\($0)" == "mac-default" })
    }

    func testMockTranscriptionRequiresPairingAndDoesNotMutateDictationState() throws {
        let state = AppState()
        state.localBridgeEnabled = true
        state.selectedTranscriptionProviderPresetID = .localWhisperCPP
        state.transcriptCleanupProviderID = .none
        state.setStatus(.idle)

        let request = LocalBridgeTranscriptionStart(
            requestID: "request-2",
            audio: LocalBridgeAudioDescriptor(format: "m4a", durationMilliseconds: 8400, byteCount: 248_112),
            requestedRouteID: .macSelected,
            languageHint: "en",
            cleanupRouteID: .macDefault
        )

        XCTAssertThrowsError(try state.localPairingBridgeService.handleMockTranscription(
            request,
            appState: state,
            macDeviceName: "Test Mac",
            now: Date(timeIntervalSince1970: 0)
        )) { error in
            XCTAssertEqual(error as? LocalPairingBridgeServiceError, .pairingRequired)
        }

        _ = try state.localPairingBridgeService.beginPairing(code: "123456")
        _ = try state.localPairingBridgeService.approvePairing(
            iphonePeerID: "fixture-iphone-public-id",
            displayName: "Fixture iPhone",
            now: Date(timeIntervalSince1970: 0)
        )

        let beforeProvider = state.selectedTranscriptionProviderPresetID
        let beforeStatus = state.status
        let beforeAudioFormat = state.selectedAudioFormat
        let response = try state.localPairingBridgeService.handleMockTranscription(
            request,
            appState: state,
            macDeviceName: "Test Mac",
            now: Date(timeIntervalSince1970: 0)
        )

        guard case .complete(let complete) = response else {
            return XCTFail("Expected mock transcription completion")
        }
        XCTAssertEqual(complete.type, "TranscriptionComplete")
        XCTAssertEqual(complete.requestID, "request-2")
        XCTAssertEqual(complete.transcript, "Mock local bridge transcription")
        XCTAssertEqual(complete.routeReceipt.routeID, .localWhisperCPP)

        XCTAssertEqual(state.status, beforeStatus)
        XCTAssertEqual(state.selectedTranscriptionProviderPresetID, beforeProvider)
        XCTAssertEqual(state.selectedAudioFormat, beforeAudioFormat)
    }

    func testBridgeLogsRedactTranscriptAudioAndCredentials() throws {
        let state = AppState()
        state.localBridgeEnabled = true
        state.selectedTranscriptionProviderPresetID = .localWhisperCPP
        state.transcriptCleanupProviderID = .none
        _ = try state.localPairingBridgeService.beginPairing(code: "123456")
        _ = try state.localPairingBridgeService.approvePairing(
            iphonePeerID: "fixture-iphone-public-id",
            displayName: "Fixture iPhone"
        )

        let request = LocalBridgeTranscriptionStart(
            requestID: "redaction-request",
            audio: LocalBridgeAudioDescriptor(format: "m4a", durationMilliseconds: 2_500, byteCount: 1_024),
            requestedRouteID: .macSelected,
            cleanupRouteID: .macDefault
        )
        _ = try state.localPairingBridgeService.handleMockTranscription(
            request,
            appState: state,
            macDeviceName: "Test Mac"
        )

        let logText = DiagnosticLog.recentLines(limit: 20).joined(separator: "\n")
        XCTAssertTrue(logText.contains("redaction-request"))
        XCTAssertTrue(logText.contains("bytes=1024"))
        XCTAssertFalse(logText.contains("Mock local bridge transcription"))
        XCTAssertFalse(logText.contains("transcript="))
        XCTAssertFalse(logText.contains("audioData"))
        XCTAssertFalse(logText.contains("apiKey"))
        XCTAssertFalse(logText.contains("gsk_"))
        XCTAssertFalse(logText.contains("Fixture iPhone token"))
    }

    private func clearDefaults() {
        UserDefaults.standard.removeObject(forKey: "localBridgeEnabled")
        UserDefaults.standard.removeObject(forKey: "transcriptionProvider")
        UserDefaults.standard.removeObject(forKey: "transcriptionProviderPreset")
        UserDefaults.standard.removeObject(forKey: "transcriptCleanupProvider")
    }

    private func jsonObject<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
