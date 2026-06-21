import AppKit
import SwiftUI

#if DEBUG
@MainActor
struct AudioUXSnapshotRenderer {
    static let renderFlag = "--render-audio-ux-snapshots"
    static let outputFlag = "--snapshot-output"

    struct LaunchRequest: Equatable {
        let outputDirectory: URL
    }

    enum SnapshotViewKind: String, CaseIterable {
        case signifier
        case floatingStatus = "floating-status"
    }

    enum Scenario: String, CaseIterable {
        case idle
        case recording
        case processing
        case success
        case warning
        case error

        var displayName: String {
            switch self {
            case .idle: "Idle"
            case .recording: "Recording"
            case .processing: "Processing"
            case .success: "Success"
            case .warning: "Warning"
            case .error: "Error"
            }
        }
    }

    struct RenderedArtifact: Codable, Equatable {
        let scenario: String
        let view: String
        let file: String
        let pixelWidth: Int
        let pixelHeight: Int
        let byteCount: Int
    }

    struct Receipt: Codable, Equatable {
        let schemaVersion: Int
        let rendererBackend: String
        let sourceViews: [String]
        let forbiddenCaptureDependenciesUsed: Bool
        let artifacts: [RenderedArtifact]
    }

    private let outputDirectory: URL
    private let fileManager: FileManager

    init(outputDirectory: URL, fileManager: FileManager = .default) {
        self.outputDirectory = outputDirectory
        self.fileManager = fileManager
    }

    static func launchRequest(arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchRequest? {
        guard arguments.contains(renderFlag) else { return nil }
        guard let output = value(for: outputFlag, in: arguments), !output.isEmpty else {
            return nil
        }
        return LaunchRequest(outputDirectory: URL(fileURLWithPath: output))
    }

    static func value(for flag: String, in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == flag, arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
            if argument.hasPrefix("\(flag)=") {
                return String(argument.dropFirst(flag.count + 1))
            }
        }
        return nil
    }

    func renderAll() throws -> Receipt {
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)

        var artifacts: [RenderedArtifact] = []
        for scenario in Scenario.allCases {
            let signifierState = Self.appState(for: scenario)
            artifacts.append(
                try render(
                    LiveAudioSignifierView(appState: signifierState),
                    scenario: scenario,
                    viewKind: .signifier,
                    size: CGSize(width: 160, height: 48)
                )
            )

            let floatingState = Self.appState(for: scenario)
            artifacts.append(
                try render(
                    FloatingStatusView(appState: floatingState, onDismiss: {}),
                    scenario: scenario,
                    viewKind: .floatingStatus,
                    size: CGSize(width: 340, height: 96)
                )
            )
        }

        let receipt = Receipt(
            schemaVersion: 1,
            rendererBackend: "NSHostingView.cacheDisplay.bitmapImageRep",
            sourceViews: [
                "LiveAudioSignifierView",
                "LiveAudioLevelBars",
                "FloatingStatusView"
            ],
            forbiddenCaptureDependenciesUsed: false,
            artifacts: artifacts
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let receiptData = try encoder.encode(receipt)
        try receiptData.write(to: outputDirectory.appendingPathComponent("receipt.json"), options: .atomic)
        return receipt
    }

    private static func appState(for scenario: Scenario) -> AppState {
        let state = AppState()
        state.updateAccessibilityState(isTrusted: true)
        state.updateMicrophoneState(isReady: true)
        state.apiKeyState = .ready
        state.asyncPasteEnabled = true
        state.queuedPasteEnabled = false
        state.showFloatingStatus = true
        state.hotkeyChoice = .rightCommand
        state.capturedTargetName = "Notes"

        switch scenario {
        case .idle:
            state.setStatus(.idle)
        case .recording:
            state.setStatus(.recording)
            state.recordingDuration = 8.3
            [0.08, 0.22, 0.37, 0.61, 0.48, 0.77, 0.56, 0.91, 0.62, 0.43, 0.70, 0.51, 0.29, 0.64].forEach {
                state.recordAudioLevel(Float($0))
            }
        case .processing:
            state.setStatus(.transcribing)
            state.transcriptionStage = .cleaningTranscript
            state.transcribingIconFrame = 0
        case .success:
            state.recordPaste(.currentAppCommandPosted)
        case .warning:
            state.recordNoAudioCaptured()
        case .error:
            state.showError("Microphone unavailable")
        }

        return state
    }

    private func render<V: View>(
        _ view: V,
        scenario: Scenario,
        viewKind: SnapshotViewKind,
        size: CGSize
    ) throws -> RenderedArtifact {
        let fileName = "\(scenario.rawValue)-\(viewKind.rawValue).png"
        let fileURL = outputDirectory.appendingPathComponent(fileName)
        let hostingView = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw NSError(
                domain: "AudioUXSnapshotRenderer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap for \(fileName)"]
            )
        }
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "AudioUXSnapshotRenderer",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG for \(fileName)"]
            )
        }
        try pngData.write(to: fileURL, options: .atomic)

        return RenderedArtifact(
            scenario: scenario.rawValue,
            view: viewKind.rawValue,
            file: fileURL.path,
            pixelWidth: bitmap.pixelsWide,
            pixelHeight: bitmap.pixelsHigh,
            byteCount: pngData.count
        )
    }
}
#endif
