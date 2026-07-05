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
        UserDefaults.standard.removeObject(forKey: "pauseBrowserMediaWhileRecording")
        UserDefaults.standard.removeObject(forKey: "showLiveFeedbackHUD")
        UserDefaults.standard.removeObject(forKey: "showFloatingStatus")
        UserDefaults.standard.removeObject(forKey: "mockTranscriptionEnabled")
        UserDefaults.standard.removeObject(forKey: "transcriptProcessingMode")
        UserDefaults.standard.removeObject(forKey: "transcriptCleanupModel")
        UserDefaults.standard.removeObject(forKey: "transcriptCleanupProvider")
        UserDefaults.standard.removeObject(forKey: "customTranscriptCleanupBaseURL")
        UserDefaults.standard.removeObject(forKey: "customTranscriptCleanupModel")
        UserDefaults.standard.removeObject(forKey: "customCleanupPrompt.cleanUp")
        UserDefaults.standard.removeObject(forKey: "customCleanupPrompt.rewriteClearly")
        UserDefaults.standard.removeObject(forKey: "cleanupGroups")
        UserDefaults.standard.removeObject(forKey: "transcriptCleanupPreferredTerms")
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

    func testRedactedRemovesLabeledCleanupPromptTermsAndTranscriptText() {
        let text = """
        cleanup prompt=SECRET PROMPT SENTINEL, preferredTerms=SECRET TERM SENTINEL
        vocabularyCorrection=SECRET CORRECTION SENTINEL, vocabularyNote=SECRET NOTE SENTINEL
        rawTranscript=raw transcript sentinel; cleanedText=cleaned transcript sentinel
        """

        let redacted = DiagnosticLog.redacted(text)

        XCTAssertFalse(redacted.contains("SECRET PROMPT SENTINEL"))
        XCTAssertFalse(redacted.contains("SECRET TERM SENTINEL"))
        XCTAssertFalse(redacted.contains("SECRET CORRECTION SENTINEL"))
        XCTAssertFalse(redacted.contains("SECRET NOTE SENTINEL"))
        XCTAssertFalse(redacted.contains("raw transcript sentinel"))
        XCTAssertFalse(redacted.contains("cleaned transcript sentinel"))
        XCTAssertTrue(redacted.contains("cleanup prompt=<redacted>"))
        XCTAssertTrue(redacted.contains("preferredTerms=<redacted>"))
        XCTAssertTrue(redacted.contains("vocabularyCorrection=<redacted>"))
        XCTAssertTrue(redacted.contains("vocabularyNote=<redacted>"))
        XCTAssertTrue(redacted.contains("rawTranscript=<redacted>"))
        XCTAssertTrue(redacted.contains("cleanedText=<redacted>"))
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
        appState.selectedInputDeviceUID = "missing-input-\(UUID().uuidString)"
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
        XCTAssertTrue(export.contains("Cleanup Provider: Groq (groq)"))
        XCTAssertTrue(export.contains("Async Paste: true"))
        XCTAssertTrue(export.contains("Input Device Transport: Unknown"))
        XCTAssertTrue(export.contains("Queued Paste Delivery Shortcut: Control-Shift-V"))
        XCTAssertTrue(export.contains("Keep Final Text On Clipboard: true"))
        XCTAssertTrue(export.contains("Other Audio While Recording: unaffected"))
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
        appState.pauseBrowserMediaWhileRecording = true
        appState.selectedInputDeviceUID = "missing-input-\(UUID().uuidString)"
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
        XCTAssertTrue(report.contains("- Input Device Transport: Unknown"))
        XCTAssertTrue(report.contains("- Other Audio While Recording: pause supported browser media"))
        XCTAssertTrue(report.contains("- Queued Paste Delivery Shortcut: Control-Shift-V"))
        XCTAssertTrue(report.contains("- Provider Connection Test: failed(Server rejected apiKey=<redacted>)"))
        XCTAssertTrue(report.contains("validate failed apiKey=<redacted>"))
        XCTAssertFalse(report.contains("gsk_secret"))
        XCTAssertFalse(report.contains("sk-secret123456789"))
    }

    @MainActor
    func testSetupReportIncludesCleanupProviderWithoutSecrets() {
        let appState = AppState()
        appState.selectedTranscriptionProviderPresetID = .localWhisperCPP
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "https://cleanup.example/v1?api_key=cleanup-secret"
        appState.customTranscriptCleanupModel = "llama3.1:8b"

        let report = DiagnosticLog.setupReportText(appState: appState)

        XCTAssertTrue(report.contains("- Cleanup Provider: Custom OpenAI-compatible chat"))
        XCTAssertTrue(report.contains("- Cleanup Base URL: https://cleanup.example/v1?api_key=<redacted>"))
        XCTAssertTrue(report.contains("- Cleanup Model: llama3.1:8b"))
        XCTAssertFalse(report.contains("cleanup-secret"))
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

    @MainActor
    func testDiagnosticsDoNotIncludeCleanupPromptPreferredTermsOrTranscriptText() {
        let appState = AppState()
        appState.transcriptProcessingMode = .cleanUp
        appState.transcriptCleanupProviderID = .customOpenAICompatibleChat
        appState.customTranscriptCleanupBaseURL = "http://127.0.0.1:11434/v1"
        appState.customTranscriptCleanupModel = "qwen2.5:7b"
        appState.setCustomPrompt("SECRET PROMPT SENTINEL", for: .cleanUp)
        appState.preferredTermsText = "SECRET TERM SENTINEL"
        appState.addVocabularyCorrection(
            writtenAs: "SECRET WRONG SENTINEL",
            correctVersion: "SECRET CORRECT SENTINEL",
            note: "SECRET NOTE SENTINEL"
        )

        DiagnosticLog.write("processTranscript: cleanupProvider=custom-openai-compatible-chat mode=cleanUp model=qwen2.5:7b inputLength=29 outputLength=25 cleanupFailed=false")

        let export = DiagnosticLog.exportText(appState: appState, recentLineLimit: 20)
        let setup = DiagnosticLog.setupReportText(appState: appState, recentLineLimit: 20)
        let combined = export + "\n" + setup

        XCTAssertTrue(combined.contains("Transcript Processing: cleanUp"))
        XCTAssertTrue(combined.contains("Cleanup Provider: Custom OpenAI-compatible chat"))
        XCTAssertTrue(combined.contains("Cleanup Model: qwen2.5:7b"))
        XCTAssertTrue(combined.contains("inputLength=29"))
        XCTAssertTrue(combined.contains("outputLength=25"))
        XCTAssertTrue(combined.contains("cleanupFailed=false"))
        XCTAssertFalse(combined.contains("SECRET PROMPT SENTINEL"))
        XCTAssertFalse(combined.contains("SECRET TERM SENTINEL"))
        XCTAssertFalse(combined.contains("SECRET WRONG SENTINEL"))
        XCTAssertFalse(combined.contains("SECRET CORRECT SENTINEL"))
        XCTAssertFalse(combined.contains("SECRET NOTE SENTINEL"))
        XCTAssertFalse(combined.contains("raw transcript sentinel"))
        XCTAssertFalse(combined.contains("cleaned transcript sentinel"))
    }
}
