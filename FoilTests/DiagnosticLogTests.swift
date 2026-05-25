import XCTest
@testable import Foil

final class DiagnosticLogTests: XCTestCase {
    private var logURL: URL!

    override func setUpWithError() throws {
        clearPersistedAppStateDefaults()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilDiagnosticLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appendingPathComponent("foil.log")
        DiagnosticLog.logURLOverride = logURL
        DiagnosticLog.isEnabledOverride = true
        DiagnosticLog.clearForTesting()
    }

    override func tearDownWithError() throws {
        DiagnosticLog.clearForTesting()
        DiagnosticLog.logURLOverride = nil
        DiagnosticLog.isEnabledOverride = nil
        logURL = nil
        clearPersistedAppStateDefaults()
    }

    private func clearPersistedAppStateDefaults() {
        UserDefaults.standard.removeObject(forKey: "audioFormat")
        UserDefaults.standard.removeObject(forKey: "keepOnClipboard")
        UserDefaults.standard.removeObject(forKey: "recordingMode")
        UserDefaults.standard.removeObject(forKey: "hotkeyChoice")
        UserDefaults.standard.removeObject(forKey: "language")
        UserDefaults.standard.removeObject(forKey: "asyncPasteEnabled")
        UserDefaults.standard.removeObject(forKey: "experimentalSkyLightPasteEnabled")
        UserDefaults.standard.removeObject(forKey: "showLiveFeedbackHUD")
        UserDefaults.standard.removeObject(forKey: "showFloatingStatus")
        UserDefaults.standard.removeObject(forKey: "mockTranscriptionEnabled")
        UserDefaults.standard.removeObject(forKey: "transcriptProcessingMode")
        UserDefaults.standard.removeObject(forKey: "transcriptCleanupModel")
        UserDefaults.standard.removeObject(forKey: "selectedInputDeviceUID")
        UserDefaults.standard.removeObject(forKey: "transcriptionProvider")
        UserDefaults.standard.removeObject(forKey: "transcriptionProviderPreset")
        UserDefaults.standard.removeObject(forKey: "customTranscriptionBaseURL")
        UserDefaults.standard.removeObject(forKey: "customTranscriptionModel")
    }

    func testRedactedRemovesAPIKeysAndBearerTokens() {
        let text = "apiKey=gsk_secret123 Authorization: Bearer sk-testsecret123456789"

        let redacted = DiagnosticLog.redacted(text)

        XCTAssertFalse(redacted.contains("gsk_secret123"))
        XCTAssertFalse(redacted.contains("sk-testsecret123456789"))
        XCTAssertTrue(redacted.contains("apiKey=<redacted>"))
        XCTAssertTrue(redacted.contains("Authorization: Bearer <redacted>"))
    }

    func testRedactedPreservesDiagnosticMethodNames() {
        let text = "validateApiKey: checking provider=groq requiredModels=2"

        let redacted = DiagnosticLog.redacted(text)

        XCTAssertEqual(redacted, text)
    }

    func testRedactedMasksUserHomePath() {
        let text = "E2E: using WAV from environment at /Users/alice/Desktop/audio.wav"

        let redacted = DiagnosticLog.redacted(text)

        XCTAssertEqual(redacted, "E2E: using WAV from environment at /Users/<user>/Desktop/audio.wav")
    }

    func testRecentLinesReturnsBoundedRedactedEntries() {
        DiagnosticLog.write("first apiKey=gsk_old")
        DiagnosticLog.write("second")
        DiagnosticLog.write("third")

        let lines = DiagnosticLog.recentLines(limit: 2)

        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("second"))
        XCTAssertTrue(lines[1].contains("third"))
        XCTAssertFalse(lines.joined(separator: "\n").contains("gsk_old"))
    }

    func testDefaultLogURLUsesTemporaryDirectoryDuringTests() {
        DiagnosticLog.logURLOverride = nil

        let url = DiagnosticLog.currentLogURLForTesting

        XCTAssertTrue(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertTrue(url.path.contains("TestDiagnostics/foil.log"))
        XCTAssertFalse(url.path.contains("/Library/Application Support/Foil/Diagnostics/foil.log"))
    }

    func testTrimPreservesUTF8ReadableRecentLogs() throws {
        var text = String(repeating: "prefix\n", count: 40_000)
        for index in 0..<40_000 {
            text += "línea \(index) café 😀\n"
        }
        try text.write(to: logURL, atomically: true, encoding: .utf8)

        DiagnosticLog.trimForTesting(at: logURL)

        let trimmed = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(trimmed.contains("línea 39999 café 😀"))
        XCTAssertFalse(trimmed.hasPrefix("�"))
    }

    func testExportTextIncludesAppInfoAndRedactedLogs() {
        DiagnosticLog.write("transcribe failed apiKey=gsk_secret")
        let appInfo = DiagnosticAppInfo(
            appVersion: "1.2.3",
            buildNumber: "456",
            macOSVersion: "macOS Test",
            architecture: "arm64",
            bundlePath: "/Users/alice/Applications/Foil.app"
        )

        let export = DiagnosticLog.exportText(appInfo: appInfo, recentLineLimit: 20)

        XCTAssertTrue(export.contains("Foil Diagnostics"))
        XCTAssertTrue(export.contains("App Version: 1.2.3"))
        XCTAssertTrue(export.contains("Build: 456"))
        XCTAssertTrue(export.contains("macOS: macOS Test"))
        XCTAssertTrue(export.contains("Architecture: arm64"))
        XCTAssertTrue(export.contains("Bundle Path: /Users/<user>/Applications/Foil.app"))
        XCTAssertTrue(export.contains("transcribe failed apiKey=<redacted>"))
        XCTAssertFalse(export.contains("gsk_secret"))
    }

    @MainActor
    func testExportTextWithAppStateIncludesSetupAndConfigurationSummary() {
        let appState = AppState()
        appState.updateAccessibilityState(isTrusted: true)
        appState.updateMicrophoneState(isReady: false, message: "Allow microphone access")
        appState.apiKeyState = .needsAction("Add Groq API key")
        appState.failSetupCheck("Enable Accessibility")
        appState.asyncPasteEnabled = true
        appState.keepOnClipboard = true
        DiagnosticLog.write("provider failed apiKey=gsk_secret")
        let appInfo = DiagnosticAppInfo(
            appVersion: "1.2.3",
            buildNumber: "456",
            macOSVersion: "macOS Test",
            architecture: "arm64",
            bundlePath: "/Users/alice/Applications/Foil.app"
        )

        let export = DiagnosticLog.exportText(appState: appState, appInfo: appInfo, recentLineLimit: 20)

        XCTAssertTrue(export.contains("Setup State:"))
        XCTAssertTrue(export.contains("Accessibility: ready"))
        XCTAssertTrue(export.contains("Microphone: needsAction(Allow microphone access)"))
        XCTAssertTrue(export.contains("API Key: needsAction(Add Groq API key)"))
        XCTAssertTrue(export.contains("Setup Check: failed(Enable Accessibility)"))
        XCTAssertTrue(export.contains("Configuration:"))
        XCTAssertTrue(export.contains("Provider: Groq"))
        XCTAssertTrue(export.contains("Async Paste: true"))
        XCTAssertTrue(export.contains("Keep Final Text On Clipboard: true"))
        XCTAssertTrue(export.contains("provider failed apiKey=<redacted>"))
        XCTAssertFalse(export.contains("gsk_secret"))
    }

    @MainActor
    func testSetupReportIncludesProviderStateAndRedactsSecrets() {
        let appState = AppState()
        appState.selectedTranscriptionProviderPresetID = .customOpenAICompatible
        appState.customTranscriptionBaseURL = "http://127.0.0.1:8080/v1"
        appState.customTranscriptionModel = "whisper-custom"
        appState.updateAccessibilityState(isTrusted: true)
        appState.updateMicrophoneState(isReady: false, message: "Allow microphone")
        appState.apiKeyState = .needsAction("Add API key")
        appState.providerConnectionTestState = .failed("Server rejected apiKey=gsk_secret")
        appState.setStatus(.error("Transcription failed Authorization: Bearer sk-secret123456789"))
        DiagnosticLog.write("validate failed apiKey=gsk_secret")
        let appInfo = DiagnosticAppInfo(
            appVersion: "1.2.3",
            buildNumber: "456",
            macOSVersion: "macOS Test",
            architecture: "arm64",
            bundlePath: "/Users/alice/Applications/Foil.app"
        )

        let report = DiagnosticLog.setupReportText(appState: appState, appInfo: appInfo, recentLineLimit: 20)

        XCTAssertTrue(report.contains("# Foil Setup Report"))
        XCTAssertTrue(report.contains("- App Version: 1.2.3 (456)"))
        XCTAssertTrue(report.contains("- Bundle Path: /Users/<user>/Applications/Foil.app"))
        XCTAssertTrue(report.contains("- Selected Provider: Custom OpenAI-compatible"))
        XCTAssertTrue(report.contains("- Base URL: http://127.0.0.1:8080/v1"))
        XCTAssertTrue(report.contains("- Transcription Model: whisper-custom"))
        XCTAssertTrue(report.contains("- API Key Stored: no"))
        XCTAssertTrue(report.contains("- Input Monitoring: not directly detectable by Foil"))
        XCTAssertTrue(report.contains("- Provider Connection Test: failed(Server rejected apiKey=<redacted>)"))
        XCTAssertTrue(report.contains("validate failed apiKey=<redacted>"))
        XCTAssertFalse(report.contains("gsk_secret"))
        XCTAssertFalse(report.contains("sk-secret123456789"))
    }

    @MainActor
    func testSetupReportDescribesLocalWhisperModelPathBoundary() {
        let appState = AppState()
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        let appInfo = DiagnosticAppInfo(
            appVersion: "1.2.3",
            buildNumber: "456",
            macOSVersion: "macOS Test",
            architecture: "arm64",
            bundlePath: "/Applications/Foil.app"
        )

        let report = DiagnosticLog.setupReportText(appState: appState, appInfo: appInfo, recentLineLimit: 0)

        XCTAssertTrue(report.contains("- Selected Provider: Local whisper.cpp"))
        XCTAssertTrue(report.contains("- API Key Required: no"))
        XCTAssertTrue(report.contains("- Local Model Path: Not stored by Foil; whisper.cpp model files are managed by the local server."))
    }
}
