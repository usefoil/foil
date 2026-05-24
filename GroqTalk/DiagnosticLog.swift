import Foundation

struct DiagnosticAppInfo: Equatable {
    var appVersion: String
    var buildNumber: String
    var macOSVersion: String
    var architecture: String
    var bundlePath: String

    static var current: DiagnosticAppInfo {
        let bundle = Bundle.main
        return DiagnosticAppInfo(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture,
            bundlePath: bundle.bundlePath
        )
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

enum DiagnosticLog {
    static var logURLOverride: URL?
    static var isEnabledOverride: Bool?

    private static let maxLogBytes = 1_000_000
    private static let queue = DispatchQueue(label: "com.groqtalk.diagnostic-log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    static func write(_ message: String) {
        guard isEnabled else { return }
        let redactedMessage = redacted(message)
        let line = "\(formatter.string(from: Date())) \(redactedMessage)\n"
        NSLog("[GroqTalk] %@", redactedMessage)
        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            let url = logURL
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                FileManager.default.createFile(atPath: url.path, contents: data)
            }
            trimLogIfNeeded(at: url)
        }
    }

    static func recentLines(limit: Int = 400) -> [String] {
        flushForTesting()
        guard limit > 0,
              let text = try? String(contentsOf: logURL, encoding: .utf8) else {
            return []
        }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(limit)
            .map { redacted(String($0)) }
    }

    static func exportText(
        appInfo: DiagnosticAppInfo = .current,
        recentLineLimit: Int = 400
    ) -> String {
        let generatedAt = formatter.string(from: Date())
        let lines = recentLines(limit: recentLineLimit)
        return [
            "GroqTalk Diagnostics",
            "Generated: \(generatedAt)",
            "App Version: \(appInfo.appVersion)",
            "Build: \(appInfo.buildNumber)",
            "macOS: \(appInfo.macOSVersion)",
            "Architecture: \(appInfo.architecture)",
            "Bundle Path: \(redacted(appInfo.bundlePath))",
            "",
            "Recent Logs:",
            lines.isEmpty ? "(no diagnostic log entries)" : lines.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    @MainActor
    static func exportText(
        appState: AppState,
        appInfo: DiagnosticAppInfo = .current,
        recentLineLimit: Int = 400
    ) -> String {
        let generatedAt = formatter.string(from: Date())
        let lines = recentLines(limit: recentLineLimit)
        let setupSummary = [
            "Status: \(diagnosticDescription(for: appState.status))",
            "Accessibility: \(diagnosticDescription(for: appState.accessibilityState))",
            "Microphone: \(diagnosticDescription(for: appState.microphoneState))",
            "API Key: \(diagnosticDescription(for: appState.apiKeyState))",
            "Setup Check: \(diagnosticDescription(for: appState.setupCheckState))"
        ]
        let preferenceSummary = [
            "Provider: \(appState.selectedTranscriptionProvider.displayName) (\(appState.selectedTranscriptionProvider.id.rawValue))",
            "Transcription Model: \(appState.selectedTranscriptionModel)",
            "Transcript Processing: \(appState.effectiveTranscriptProcessingMode.rawValue)",
            "Cleanup Model: \(appState.transcriptCleanupModel)",
            "Audio Format: \(appState.selectedAudioFormat.rawValue)",
            "Recording Mode: \(appState.recordingMode.rawValue)",
            "Async Paste: \(appState.asyncPasteEnabled)",
            "Keep Final Text On Clipboard: \(appState.keepOnClipboard)",
            "Floating Status: \(appState.shouldShowFloatingStatus)",
            "Sound Effects: \(appState.soundEffectsEnabled)"
        ]

        return [
            "GroqTalk Diagnostics",
            "Generated: \(generatedAt)",
            "App Version: \(appInfo.appVersion)",
            "Build: \(appInfo.buildNumber)",
            "macOS: \(appInfo.macOSVersion)",
            "Architecture: \(appInfo.architecture)",
            "Bundle Path: \(redacted(appInfo.bundlePath))",
            "",
            "Setup State:",
            setupSummary.joined(separator: "\n"),
            "",
            "Configuration:",
            preferenceSummary.joined(separator: "\n"),
            "",
            "Recent Logs:",
            lines.isEmpty ? "(no diagnostic log entries)" : lines.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    @MainActor
    static func setupReportText(
        appState: AppState,
        appInfo: DiagnosticAppInfo = .current,
        recentLineLimit: Int = 80
    ) -> String {
        let generatedAt = formatter.string(from: Date())
        let provider = appState.selectedTranscriptionProvider
        let preset = appState.selectedTranscriptionProviderPreset
        let lines = recentLines(limit: recentLineLimit)
        let lastIssue = [
            diagnosticIssueDescription(for: appState.status),
            diagnosticIssueDescription(for: appState.setupCheckState),
            diagnosticIssueDescription(for: appState.providerConnectionTestState)
        ].compactMap { $0 }.first ?? "None recorded"

        return [
            "# GroqTalk Setup Report",
            "",
            "- Generated: \(generatedAt)",
            "- App Version: \(appInfo.appVersion) (\(appInfo.buildNumber))",
            "- macOS: \(appInfo.macOSVersion)",
            "- Architecture: \(appInfo.architecture)",
            "- Bundle Path: \(redacted(appInfo.bundlePath))",
            "",
            "## Provider",
            "",
            "- Selected Provider: \(provider.displayName)",
            "- Provider ID: \(provider.id.rawValue)",
            "- Provider Preset: \(preset.id.rawValue)",
            "- Base URL: \(redacted(provider.baseURL.absoluteString))",
            "- Transcription Model: \(provider.transcriptionModel)",
            "- API Key Required: \(provider.requiresAPIKey ? "yes" : "no")",
            "- API Key Stored: \(appState.hasApiKey ? "yes" : "no")",
            "- Local Model Path: \(localModelPathDescription(for: appState))",
            "",
            "## Setup State",
            "",
            "- App Status: \(diagnosticDescription(for: appState.status))",
            "- Accessibility: \(diagnosticDescription(for: appState.accessibilityState))",
            "- Microphone: \(diagnosticDescription(for: appState.microphoneState))",
            "- Input Monitoring: not directly detectable by GroqTalk; check macOS Privacy & Security if hotkeys do not arrive.",
            "- API Key State: \(diagnosticDescription(for: appState.apiKeyState))",
            "- Setup Check: \(diagnosticDescription(for: appState.setupCheckState))",
            "- Provider Connection Test: \(diagnosticDescription(for: appState.providerConnectionTestState))",
            "- Last Setup/Transcription Issue: \(lastIssue)",
            "",
            "## Recording And Paste",
            "",
            "- Recording Mode: \(appState.recordingMode.rawValue)",
            "- Hotkey: \(appState.hotkeyChoice.label)",
            "- Audio Format: \(appState.selectedAudioFormat.rawValue)",
            "- Input Device UID: \(redacted(appState.selectedInputDeviceUID ?? "System Default"))",
            "- Transcript Processing: \(appState.effectiveTranscriptProcessingMode.rawValue)",
            "- Cleanup Model: \(appState.transcriptCleanupModel)",
            "- Async Paste: \(appState.asyncPasteEnabled ? "enabled" : "disabled")",
            "- Keep Final Text On Clipboard: \(appState.keepOnClipboard ? "enabled" : "disabled")",
            "- Floating Status: \(appState.shouldShowFloatingStatus ? "enabled" : "disabled")",
            "",
            "## Recent Diagnostics",
            "",
            lines.isEmpty ? "(no diagnostic log entries)" : lines.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    static func redacted(_ text: String) -> String {
        var output = text
        let replacements: [(pattern: String, template: String)] = [
            (#"(?i)(?<![A-Za-z0-9_])(api[_ -]?key\s*[=:]\s*)[^\s,;]+"#, "$1<redacted>"),
            (#"(?i)(authorization\s*:\s*bearer\s+)[A-Za-z0-9._\-]+"#, "$1<redacted>"),
            (#"gsk_[A-Za-z0-9_\-]+"#, "<redacted-api-key>"),
            (#"sk-[A-Za-z0-9_\-]{12,}"#, "<redacted-api-key>"),
            (#"(?i)(/Users/)[^/\s]+/"#, "$1<user>/")
        ]
        for replacement in replacements {
            output = output.replacingMatches(
                pattern: replacement.pattern,
                with: replacement.template
            )
        }
        return output
    }

    static func clearForTesting() {
        flushForTesting()
        try? FileManager.default.removeItem(at: logURL)
    }

    static func flushForTesting() {
        queue.sync {}
    }

    static var currentLogURLForTesting: URL {
        logURL
    }

    static func trimForTesting(at url: URL) {
        trimLogIfNeeded(at: url)
    }

    private static var isEnabled: Bool {
        if let isEnabledOverride { return isEnabledOverride }
        return ProcessInfo.processInfo.environment["GROQTALK_DIAGNOSTICS"] != "0"
    }

    private static var logURL: URL {
        if let logURLOverride { return logURLOverride }
        if isTestProcess {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("GroqTalk", isDirectory: true)
                .appendingPathComponent("TestDiagnostics", isDirectory: true)
                .appendingPathComponent("groqtalk.log", isDirectory: false)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("GroqTalk", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("groqtalk.log", isDirectory: false)
    }

    private static var isTestProcess: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return processInfo.arguments.contains { argument in
            argument == "--ui-testing" || argument.localizedCaseInsensitiveContains(".xctest")
        }
    }

    private static func trimLogIfNeeded(at url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > maxLogBytes,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return
        }
        defer { try? handle.close() }
        do {
            let data = handle.readDataToEndOfFile()
            let retained = utf8LineAlignedSuffix(of: data, maxBytes: maxLogBytes)
            try retained.write(to: url, options: .atomic)
        } catch {
            DiagnosticLog.write("DiagnosticLog: failed to trim log \(error)")
        }
    }

    private static func utf8LineAlignedSuffix(of data: Data, maxBytes: Int) -> Data {
        guard data.count > maxBytes else { return data }
        var suffix = data.suffix(maxBytes)
        while !suffix.isEmpty && String(data: Data(suffix), encoding: .utf8) == nil {
            suffix = suffix.dropFirst()
        }
        guard let newline = suffix.firstIndex(of: 0x0A),
              newline < suffix.index(before: suffix.endIndex) else {
            return Data(suffix)
        }
        return Data(suffix[suffix.index(after: newline)...])
    }

    private static func diagnosticDescription(for status: AppState.Status) -> String {
        switch status {
        case .idle:
            return "idle"
        case .recording:
            return "recording"
        case .transcribing:
            return "transcribing"
        case .error(let message):
            return "error(\(redacted(message)))"
        }
    }

    private static func diagnosticDescription(for state: AppState.PermissionState) -> String {
        switch state {
        case .unknown:
            return "unknown"
        case .ready:
            return "ready"
        case .needsAction(let message):
            return "needsAction(\(redacted(message)))"
        }
    }

    private static func diagnosticDescription(for state: AppState.SetupCheckState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .running:
            return "running"
        case .passed:
            return "passed"
        case .failed(let message):
            return "failed(\(redacted(message)))"
        }
    }

    private static func diagnosticDescription(for state: AppState.ProviderConnectionTestState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .running:
            return "running"
        case .succeeded(let message):
            return "succeeded(\(redacted(message)))"
        case .warning(let message):
            return "warning(\(redacted(message)))"
        case .failed(let message):
            return "failed(\(redacted(message)))"
        }
    }

    @MainActor
    private static func localModelPathDescription(for appState: AppState) -> String {
        guard appState.selectedTranscriptionProviderPresetID == .localWhisperCPP else {
            return "Not applicable"
        }
        return "Not stored by GroqTalk; whisper.cpp model files are managed by the local server."
    }

    private static func diagnosticIssueDescription(for status: AppState.Status) -> String? {
        if case .error(let message) = status {
            return redacted(message)
        }
        return nil
    }

    private static func diagnosticIssueDescription(for state: AppState.SetupCheckState) -> String? {
        if case .failed(let message) = state {
            return redacted(message)
        }
        return nil
    }

    private static func diagnosticIssueDescription(for state: AppState.ProviderConnectionTestState) -> String? {
        switch state {
        case .failed(let message), .warning(let message):
            return redacted(message)
        case .idle, .running, .succeeded:
            return nil
        }
    }
}

private extension String {
    func replacingMatches(pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: template)
    }
}
