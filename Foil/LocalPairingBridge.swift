import Foundation
import Network

enum LocalBridgeProtocol {
    static let family = "foil.localBridge"
    static let version = 1
    static let serviceName = "Foil Local Bridge"
    static let bonjourType = "_foil-bridge._tcp.local"
    static let maxAudioBytes = 26_214_400
    static let acceptedAudioFormats = ["m4a", "wav", "flac"]
}

enum LocalBridgePairingState: String, Codable, Equatable {
    case unpaired
    case pairing
    case paired
    case revoked
}

enum LocalBridgeRequestState: String, Codable, Equatable {
    case queued
    case uploading
    case transcribingOnMac
    case complete
    case failed
    case cancelled
}

enum LocalBridgeRouteID: String, Codable, CaseIterable, Equatable, Identifiable {
    case macSelected = "mac-selected"
    case localWhisperCPP = "local-whisper-cpp"
    case groq
    case openAIWhisper = "openai-whisper"
    case customOpenAICompatible = "custom-openai-compatible"

    var id: String { rawValue }
}

enum LocalBridgeCleanupRouteID: String, Codable, Equatable {
    case none
    case macDefault = "mac-default"
    case groq
    case customOpenAICompatibleChat = "custom-openai-compatible-chat"
}

enum LocalBridgePrivacyClass: String, Codable, Equatable {
    case local
    case cloud
    case custom
}

enum LocalBridgeTranscriptionLocation: String, Codable, Equatable {
    case pairedMac
    case thisIPhone
}

enum LocalBridgeProviderLocation: String, Codable, Equatable {
    case localMac
    case cloudProvider
    case customEndpoint
}

enum LocalBridgeFailureCode: String, Codable, Equatable {
    case macUnavailable
    case pairingRevoked
    case noTranscriptionRoute
    case routeUnavailable
    case uploadInterrupted
    case transcriptionFailed
    case keyboardHandoffUnavailable
    case unsupportedProtocolVersion
}

struct LocalBridgeAdvertisement: Codable, Equatable {
    let serviceName: String
    let bonjourType: String
    let txt: [String: String]
}

@MainActor
protocol LocalBridgeTransporting: AnyObject {
    var isAdvertising: Bool { get }
    var isListening: Bool { get }
    var lastAdvertisement: LocalBridgeAdvertisement? { get }

    func start(advertisement: LocalBridgeAdvertisement) throws
    func stop()
}

final class NetworkLocalBridgeTransport: LocalBridgeTransporting {
    private let queue = DispatchQueue(label: "com.neonwatty.Foil.LocalBridgeTransport")
    private var listener: NWListener?

    private(set) var isAdvertising = false
    private(set) var isListening = false
    private(set) var lastAdvertisement: LocalBridgeAdvertisement?

    func start(advertisement: LocalBridgeAdvertisement) throws {
        stop()

        let listener = try NWListener(using: .tcp, on: .any)
        listener.service = NWListener.Service(
            name: advertisement.serviceName,
            type: advertisement.bonjourType,
            txtRecord: NWTXTRecord(advertisement.txt)
        )
        listener.newConnectionHandler = { connection in
            connection.cancel()
        }
        listener.start(queue: queue)

        self.listener = listener
        lastAdvertisement = advertisement
        isAdvertising = true
        isListening = true
        DiagnosticLog.write("LocalBridge: transport started service=\(advertisement.bonjourType) txtKeys=\(Self.redactedTXTKeys(advertisement.txt))")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lastAdvertisement = nil
        isAdvertising = false
        isListening = false
    }

    private static func redactedTXTKeys(_ txt: [String: String]) -> String {
        txt.keys.sorted().joined(separator: ",")
    }
}

struct LocalBridgePairingSession: Codable, Equatable {
    let `protocol`: String
    let version: Int
    let macPeerID: String
    let pairingNonce: String
    let host: String
    let port: Int
    let code: String
}

struct LocalBridgeTrustedPeer: Codable, Equatable {
    let peerID: String
    let displayName: String
    let pairedAt: String
}

protocol LocalBridgeTrustedPeerStoring {
    func loadTrustedPeer() -> LocalBridgeTrustedPeer?
    func saveTrustedPeer(_ peer: LocalBridgeTrustedPeer) throws
    func deleteTrustedPeer()
}

struct KeychainLocalBridgeTrustedPeerStore: LocalBridgeTrustedPeerStoring {
    func loadTrustedPeer() -> LocalBridgeTrustedPeer? {
        KeychainHelper.readLocalBridgeTrustedPeer()
    }

    func saveTrustedPeer(_ peer: LocalBridgeTrustedPeer) throws {
        try KeychainHelper.saveLocalBridgeTrustedPeer(peer)
    }

    func deleteTrustedPeer() {
        KeychainHelper.deleteLocalBridgeTrustedPeer()
    }
}

struct LocalBridgeCapabilitiesRequest: Codable, Equatable {
    let type: String
    let `protocol`: String
    let version: Int
    let iosAppVersion: String
    let requestID: String

    init(
        iosAppVersion: String,
        requestID: String = UUID().uuidString,
        version: Int = LocalBridgeProtocol.version
    ) {
        self.type = "CapabilitiesRequest"
        self.protocol = LocalBridgeProtocol.family
        self.version = version
        self.iosAppVersion = iosAppVersion
        self.requestID = requestID
    }
}

struct LocalBridgeRouteCapability: Codable, Equatable, Identifiable {
    let routeID: LocalBridgeRouteID
    let displayName: String
    let available: Bool
    let privacyClass: LocalBridgePrivacyClass

    var id: String { routeID.rawValue }
}

struct LocalBridgeCapabilitiesResponse: Codable, Equatable {
    let type: String
    let `protocol`: String
    let version: Int
    let requestID: String
    let macAppVersion: String
    let routes: [LocalBridgeRouteCapability]
    let selectedRouteID: LocalBridgeRouteID
    let maxAudioBytes: Int
    let acceptedAudioFormats: [String]
}

struct LocalBridgeAudioDescriptor: Codable, Equatable {
    let format: String
    let durationMilliseconds: Int
    let byteCount: Int
}

struct LocalBridgeTranscriptionStart: Codable, Equatable {
    let type: String
    let `protocol`: String
    let version: Int
    let requestID: String
    let audio: LocalBridgeAudioDescriptor
    let requestedRouteID: LocalBridgeRouteID
    let languageHint: String?
    let cleanupRouteID: LocalBridgeCleanupRouteID

    init(
        requestID: String = UUID().uuidString,
        audio: LocalBridgeAudioDescriptor,
        requestedRouteID: LocalBridgeRouteID = .macSelected,
        languageHint: String? = nil,
        cleanupRouteID: LocalBridgeCleanupRouteID = .macDefault,
        version: Int = LocalBridgeProtocol.version
    ) {
        self.type = "TranscriptionStart"
        self.protocol = LocalBridgeProtocol.family
        self.version = version
        self.requestID = requestID
        self.audio = audio
        self.requestedRouteID = requestedRouteID
        self.languageHint = languageHint
        self.cleanupRouteID = cleanupRouteID
    }
}

struct RouteReceipt: Codable, Equatable {
    let routeID: LocalBridgeRouteID
    let routeDisplayName: String
    let transcriptionLocation: LocalBridgeTranscriptionLocation
    let providerLocation: LocalBridgeProviderLocation
    let cleanupRouteID: LocalBridgeCleanupRouteID
    let audioLeftIPhone: Bool
    let audioReachedMac: Bool
    let audioReachedCloudProvider: Bool
    let textReachedCloudProvider: Bool
    let macDeviceName: String?
    let completedAt: String?
}

struct LocalBridgeTranscriptionComplete: Codable, Equatable {
    let type: String
    let requestID: String
    let transcript: String
    let routeReceipt: RouteReceipt
}

struct LocalBridgeFailureDetail: Codable, Equatable {
    let code: LocalBridgeFailureCode
    let displayMessage: String
    let retryable: Bool
}

struct LocalBridgeTranscriptionFailed: Codable, Equatable {
    let type: String
    let requestID: String
    let error: LocalBridgeFailureDetail
    let routeReceipt: RouteReceipt?
}

enum LocalBridgeTranscriptionResponse: Equatable {
    case complete(LocalBridgeTranscriptionComplete)
    case failed(LocalBridgeTranscriptionFailed)
}

enum LocalPairingBridgeServiceError: Error, Equatable {
    case disabled
    case pairingRequired
    case unsupportedProtocolVersion
    case unsupportedAudioFormat
    case audioTooLarge
}

@MainActor
final class LocalPairingBridgeService {
    private(set) var isEnabled = false
    private(set) var pairingState: LocalBridgePairingState = .unpaired
    private(set) var activePairingSession: LocalBridgePairingSession?
    private(set) var trustedPeer: LocalBridgeTrustedPeer?
    private(set) var transportErrorMessage: String?
    private let transport: LocalBridgeTransporting
    private let trustedPeerStore: LocalBridgeTrustedPeerStoring

    var isAdvertising: Bool { transport.isAdvertising }
    var isListening: Bool { transport.isListening }
    var lastAdvertisement: LocalBridgeAdvertisement? { transport.lastAdvertisement }

    init(
        transport: LocalBridgeTransporting? = nil,
        trustedPeerStore: LocalBridgeTrustedPeerStoring? = nil
    ) {
        self.transport = transport ?? NetworkLocalBridgeTransport()
        self.trustedPeerStore = trustedPeerStore ?? KeychainLocalBridgeTrustedPeerStore()
    }

    func setEnabled(_ enabled: Bool, appState: AppState? = nil, deviceName: String = "This Mac") {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            transportErrorMessage = nil
            restoreTrustedPeer()
            if let appState {
                do {
                    try transport.start(advertisement: advertisement(deviceName: deviceName, appState: appState))
                } catch {
                    transport.stop()
                    transportErrorMessage = "Local bridge transport unavailable"
                    DiagnosticLog.write("LocalBridge: transport failed error=\(String(describing: error))")
                }
            }
            DiagnosticLog.write("LocalBridge: enabled advertising=\(transport.isAdvertising)")
        } else {
            transport.stop()
            transportErrorMessage = nil
            activePairingSession = nil
            trustedPeer = nil
            pairingState = .unpaired
            DiagnosticLog.write("LocalBridge: disabled advertising=false")
        }
    }

    func advertisement(deviceName: String, appState: AppState) throws -> LocalBridgeAdvertisement {
        guard isEnabled else { throw LocalPairingBridgeServiceError.disabled }
        return LocalBridgeAdvertisement(
            serviceName: LocalBridgeProtocol.serviceName,
            bonjourType: LocalBridgeProtocol.bonjourType,
            txt: [
                "protocol": LocalBridgeProtocol.family,
                "version": String(LocalBridgeProtocol.version),
                "deviceName": deviceName,
                "supportsLocalTranscription": String(supportsLocalTranscription(appState: appState)),
                "supportsCloudTranscription": String(supportsCloudTranscription(appState: appState)),
                "supportsCredentialOffer": "false"
            ]
        )
    }

    func beginPairing(
        macPeerID: String = "mac-peer-public-id",
        host: String = "mac.local",
        port: Int = 49_321,
        code: String? = nil,
        pairingNonce: String? = nil
    ) throws -> LocalBridgePairingSession {
        guard isEnabled else { throw LocalPairingBridgeServiceError.disabled }
        let session = LocalBridgePairingSession(
            protocol: LocalBridgeProtocol.family,
            version: LocalBridgeProtocol.version,
            macPeerID: macPeerID,
            pairingNonce: pairingNonce ?? Self.makeNonce(),
            host: host,
            port: port,
            code: code ?? Self.makePairingCode()
        )
        activePairingSession = session
        pairingState = .pairing
        DiagnosticLog.write("LocalBridge: pairing started port=\(port)")
        return session
    }

    func approvePairing(
        iphonePeerID: String,
        displayName: String,
        now: Date = Date()
    ) throws -> LocalBridgeTrustedPeer {
        guard isEnabled else { throw LocalPairingBridgeServiceError.disabled }
        guard activePairingSession != nil else { throw LocalPairingBridgeServiceError.pairingRequired }
        let peer = LocalBridgeTrustedPeer(
            peerID: iphonePeerID,
            displayName: displayName,
            pairedAt: Self.isoString(from: now)
        )
        try trustedPeerStore.saveTrustedPeer(peer)
        trustedPeer = peer
        activePairingSession = nil
        pairingState = .paired
        DiagnosticLog.write("LocalBridge: pairing approved peer=\(displayName)")
        return peer
    }

    func revokePairing() {
        activePairingSession = nil
        trustedPeer = nil
        trustedPeerStore.deleteTrustedPeer()
        pairingState = isEnabled ? .revoked : .unpaired
        DiagnosticLog.write("LocalBridge: pairing revoked")
    }

    func capabilities(
        for request: LocalBridgeCapabilitiesRequest,
        appState: AppState,
        appVersion: String = DiagnosticAppInfo.current.appVersion
    ) throws -> LocalBridgeCapabilitiesResponse {
        guard isEnabled else { throw LocalPairingBridgeServiceError.disabled }
        guard request.protocol == LocalBridgeProtocol.family,
              request.version == LocalBridgeProtocol.version else {
            throw LocalPairingBridgeServiceError.unsupportedProtocolVersion
        }
        DiagnosticLog.write("LocalBridge: capabilities requestID=\(request.requestID)")
        return LocalBridgeCapabilitiesResponse(
            type: "CapabilitiesResponse",
            protocol: LocalBridgeProtocol.family,
            version: LocalBridgeProtocol.version,
            requestID: request.requestID,
            macAppVersion: appVersion,
            routes: Self.routeCapabilities(selectedRouteID: Self.routeID(for: appState.selectedTranscriptionProviderPresetID)),
            selectedRouteID: Self.routeID(for: appState.selectedTranscriptionProviderPresetID),
            maxAudioBytes: LocalBridgeProtocol.maxAudioBytes,
            acceptedAudioFormats: LocalBridgeProtocol.acceptedAudioFormats
        )
    }

    func handleMockTranscription(
        _ start: LocalBridgeTranscriptionStart,
        appState: AppState,
        macDeviceName: String,
        now: Date = Date()
    ) throws -> LocalBridgeTranscriptionResponse {
        guard isEnabled else { throw LocalPairingBridgeServiceError.disabled }
        guard trustedPeer != nil else { throw LocalPairingBridgeServiceError.pairingRequired }
        guard start.protocol == LocalBridgeProtocol.family,
              start.version == LocalBridgeProtocol.version else {
            let failure = LocalBridgeTranscriptionFailed(
                type: "TranscriptionFailed",
                requestID: start.requestID,
                error: LocalBridgeFailureDetail(
                    code: .unsupportedProtocolVersion,
                    displayMessage: "This iPhone needs a newer local bridge protocol.",
                    retryable: false
                ),
                routeReceipt: nil
            )
            return .failed(failure)
        }
        guard LocalBridgeProtocol.acceptedAudioFormats.contains(start.audio.format) else {
            throw LocalPairingBridgeServiceError.unsupportedAudioFormat
        }
        guard start.audio.byteCount <= LocalBridgeProtocol.maxAudioBytes else {
            throw LocalPairingBridgeServiceError.audioTooLarge
        }

        let receipt = Self.routeReceipt(
            requestedRouteID: start.requestedRouteID,
            requestedCleanupRouteID: start.cleanupRouteID,
            appState: appState,
            macDeviceName: macDeviceName,
            completedAt: Self.isoString(from: now)
        )
        DiagnosticLog.write(
            "LocalBridge: mock transcription requestID=\(start.requestID) route=\(receipt.routeID.rawValue) bytes=\(start.audio.byteCount) durationMs=\(start.audio.durationMilliseconds)"
        )
        return .complete(LocalBridgeTranscriptionComplete(
            type: "TranscriptionComplete",
            requestID: start.requestID,
            transcript: "Mock local bridge transcription",
            routeReceipt: receipt
        ))
    }

    static func routeReceipt(
        requestedRouteID: LocalBridgeRouteID = .macSelected,
        requestedCleanupRouteID: LocalBridgeCleanupRouteID = .macDefault,
        appState: AppState,
        macDeviceName: String,
        completedAt: String?
    ) -> RouteReceipt {
        let routeID = resolvedRouteID(requestedRouteID, appState: appState)
        let cleanupRouteID = resolvedCleanupRouteID(requestedCleanupRouteID, appState: appState)
        let providerLocation = providerLocation(for: routeID)
        return RouteReceipt(
            routeID: routeID,
            routeDisplayName: displayName(for: routeID),
            transcriptionLocation: .pairedMac,
            providerLocation: providerLocation,
            cleanupRouteID: cleanupRouteID,
            audioLeftIPhone: true,
            audioReachedMac: true,
            audioReachedCloudProvider: providerLocation == .cloudProvider,
            textReachedCloudProvider: cleanupRouteID == .groq,
            macDeviceName: macDeviceName,
            completedAt: completedAt
        )
    }

    static func routeID(for presetID: TranscriptionProviderPresetID) -> LocalBridgeRouteID {
        switch presetID {
        case .localWhisperCPP:
            .localWhisperCPP
        case .groq:
            .groq
        case .openAIWhisper:
            .openAIWhisper
        case .customOpenAICompatible:
            .customOpenAICompatible
        }
    }

    static func displayName(for routeID: LocalBridgeRouteID) -> String {
        switch routeID {
        case .macSelected:
            "Mac selected"
        case .localWhisperCPP:
            "Local whisper.cpp"
        case .groq:
            "Groq"
        case .openAIWhisper:
            "OpenAI Whisper"
        case .customOpenAICompatible:
            "Custom OpenAI-compatible"
        }
    }

    private static func resolvedRouteID(_ requestedRouteID: LocalBridgeRouteID, appState: AppState) -> LocalBridgeRouteID {
        requestedRouteID == .macSelected ? routeID(for: appState.selectedTranscriptionProviderPresetID) : requestedRouteID
    }

    private static func resolvedCleanupRouteID(
        _ requestedCleanupRouteID: LocalBridgeCleanupRouteID,
        appState: AppState
    ) -> LocalBridgeCleanupRouteID {
        if requestedCleanupRouteID != .macDefault {
            return requestedCleanupRouteID
        }
        switch appState.selectedTranscriptCleanupProvider.id {
        case .none:
            return .none
        case .groq:
            return .groq
        case .customOpenAICompatibleChat:
            return .customOpenAICompatibleChat
        }
    }

    private static func providerLocation(for routeID: LocalBridgeRouteID) -> LocalBridgeProviderLocation {
        switch routeID {
        case .localWhisperCPP:
            .localMac
        case .groq, .openAIWhisper:
            .cloudProvider
        case .customOpenAICompatible:
            .customEndpoint
        case .macSelected:
            .localMac
        }
    }

    private static func routeCapabilities(selectedRouteID: LocalBridgeRouteID) -> [LocalBridgeRouteCapability] {
        [
            LocalBridgeRouteCapability(
                routeID: .localWhisperCPP,
                displayName: displayName(for: .localWhisperCPP),
                available: selectedRouteID == .localWhisperCPP,
                privacyClass: .local
            ),
            LocalBridgeRouteCapability(
                routeID: .groq,
                displayName: displayName(for: .groq),
                available: selectedRouteID == .groq,
                privacyClass: .cloud
            ),
            LocalBridgeRouteCapability(
                routeID: .openAIWhisper,
                displayName: displayName(for: .openAIWhisper),
                available: selectedRouteID == .openAIWhisper,
                privacyClass: .cloud
            ),
            LocalBridgeRouteCapability(
                routeID: .customOpenAICompatible,
                displayName: displayName(for: .customOpenAICompatible),
                available: selectedRouteID == .customOpenAICompatible,
                privacyClass: .custom
            )
        ]
    }

    private func supportsLocalTranscription(appState: AppState) -> Bool {
        Self.routeID(for: appState.selectedTranscriptionProviderPresetID) == .localWhisperCPP
    }

    private func supportsCloudTranscription(appState: AppState) -> Bool {
        switch Self.routeID(for: appState.selectedTranscriptionProviderPresetID) {
        case .groq, .openAIWhisper:
            return true
        case .customOpenAICompatible:
            return appState.customTranscriptionBaseURLValue?.host != "127.0.0.1"
        case .localWhisperCPP, .macSelected:
            return false
        }
    }

    private static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private static func makeNonce() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func restoreTrustedPeer() {
        trustedPeer = trustedPeerStore.loadTrustedPeer()
        pairingState = trustedPeer == nil ? .unpaired : .paired
    }
}
