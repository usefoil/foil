import XCTest
@testable import GroqTalk

final class DiagnosticLogTests: XCTestCase {
    private var logURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GroqTalkDiagnosticLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appendingPathComponent("groqtalk.log")
        DiagnosticLog.logURLOverride = logURL
        DiagnosticLog.isEnabledOverride = true
        DiagnosticLog.clearForTesting()
    }

    override func tearDownWithError() throws {
        DiagnosticLog.clearForTesting()
        DiagnosticLog.logURLOverride = nil
        DiagnosticLog.isEnabledOverride = nil
        logURL = nil
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
        XCTAssertTrue(url.path.contains("TestDiagnostics/groqtalk.log"))
        XCTAssertFalse(url.path.contains("/Library/Application Support/GroqTalk/Diagnostics/groqtalk.log"))
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
            architecture: "arm64"
        )

        let export = DiagnosticLog.exportText(appInfo: appInfo, recentLineLimit: 20)

        XCTAssertTrue(export.contains("GroqTalk Diagnostics"))
        XCTAssertTrue(export.contains("App Version: 1.2.3"))
        XCTAssertTrue(export.contains("Build: 456"))
        XCTAssertTrue(export.contains("macOS: macOS Test"))
        XCTAssertTrue(export.contains("Architecture: arm64"))
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
            architecture: "arm64"
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
}
