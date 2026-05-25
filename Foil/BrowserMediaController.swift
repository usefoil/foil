import AppKit
import Foundation

struct BrowserMediaControlSummary: Equatable {
    enum Outcome: String, Equatable {
        case skippedDisabled
        case browserNotRunning
        case attempted
        case failed
    }

    var outcome: Outcome
    var browser: String
    var tabsChecked: Int
    var mediaPaused: Int
    var failures: Int
    var category: String

    static let disabled = BrowserMediaControlSummary(
        outcome: .skippedDisabled,
        browser: "none",
        tabsChecked: 0,
        mediaPaused: 0,
        failures: 0,
        category: "disabled"
    )

    static let browserNotRunning = BrowserMediaControlSummary(
        outcome: .browserNotRunning,
        browser: "chrome",
        tabsChecked: 0,
        mediaPaused: 0,
        failures: 0,
        category: "browserNotRunning"
    )

    static func attempted(browser: String, tabsChecked: Int, mediaPaused: Int, failures: Int) -> Self {
        BrowserMediaControlSummary(
            outcome: .attempted,
            browser: browser,
            tabsChecked: tabsChecked,
            mediaPaused: mediaPaused,
            failures: failures,
            category: "attempted"
        )
    }

    static func failed(browser: String = "chrome", category: String) -> Self {
        BrowserMediaControlSummary(
            outcome: .failed,
            browser: browser,
            tabsChecked: 0,
            mediaPaused: 0,
            failures: 1,
            category: category
        )
    }

    var diagnosticMessage: String {
        switch outcome {
        case .skippedDisabled:
            return "browserMediaControl: skipped disabled"
        case .browserNotRunning:
            return "browserMediaControl: skipped browserNotRunning"
        case .attempted:
            return "browserMediaControl: attempted browser=\(browser) tabs=\(tabsChecked) paused=\(mediaPaused) failures=\(failures)"
        case .failed:
            return "browserMediaControl: failed category=\(category)"
        }
    }
}

protocol BrowserMediaScriptRunning {
    func pausePlayingMedia() async throws -> BrowserMediaControlSummary
}

@MainActor
final class BrowserMediaController {
    enum EndReason: String {
        case stopped
        case cancelled
        case failed
        case noAudio
    }

    private let isEnabled: () -> Bool
    private let scriptRunner: BrowserMediaScriptRunning
    private var activeSessionID: UUID?

    init(
        isEnabled: @escaping () -> Bool,
        scriptRunner: BrowserMediaScriptRunning = ChromeBrowserMediaScriptRunner()
    ) {
        self.isEnabled = isEnabled
        self.scriptRunner = scriptRunner
    }

    var hasActiveSession: Bool {
        activeSessionID != nil
    }

    @discardableResult
    func recordingDidStart() -> UUID? {
        guard isEnabled() else {
            activeSessionID = nil
            DiagnosticLog.write(BrowserMediaControlSummary.disabled.diagnosticMessage)
            return nil
        }

        activeSessionID = UUID()
        return activeSessionID
    }

    @discardableResult
    func pausePlayingMedia(for sessionID: UUID) async -> BrowserMediaControlSummary {
        guard activeSessionID == sessionID else {
            return .failed(category: "sessionEnded")
        }
        do {
            let summary = try await scriptRunner.pausePlayingMedia()
            DiagnosticLog.write(summary.diagnosticMessage)
            return summary
        } catch {
            let summary = BrowserMediaControlSummary.failed(category: "commandFailed")
            DiagnosticLog.write(summary.diagnosticMessage)
            return summary
        }
    }

    @discardableResult
    func recordingDidStartAndPause() async -> BrowserMediaControlSummary {
        guard let sessionID = recordingDidStart() else {
            return .disabled
        }
        return await pausePlayingMedia(for: sessionID)
    }

    func recordingDidEnd(reason: EndReason) {
        guard activeSessionID != nil else { return }
        activeSessionID = nil
        DiagnosticLog.write("browserMediaControl: session ended reason=\(reason.rawValue) action=noResume")
    }
}

struct ChromeBrowserMediaScriptRunner: BrowserMediaScriptRunning {
    private struct BrowserCandidate {
        let bundleIdentifier: String
        let appleScriptName: String
        let diagnosticName: String
    }

    private let candidates = [
        BrowserCandidate(
            bundleIdentifier: "com.google.Chrome",
            appleScriptName: "Google Chrome",
            diagnosticName: "chrome"
        ),
        BrowserCandidate(
            bundleIdentifier: "org.chromium.Chromium",
            appleScriptName: "Chromium",
            diagnosticName: "chromium"
        )
    ]

    func pausePlayingMedia() async throws -> BrowserMediaControlSummary {
        let runningBrowsers = candidates.filter { isRunning(bundleIdentifier: $0.bundleIdentifier) }
        guard !runningBrowsers.isEmpty else {
            return .browserNotRunning
        }

        let summaries = runningBrowsers.map(runPauseScript)
        return Self.combinedSummary(from: summaries)
    }

    private func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private func runPauseScript(in browser: BrowserCandidate) -> BrowserMediaControlSummary {
        let source = Self.appleScriptSource(
            applicationName: browser.appleScriptName,
            javascript: Self.pauseJavaScript
        )
        var errorInfo: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo),
              let result = descriptor.stringValue else {
            return .failed(browser: browser.diagnosticName, category: "scriptError")
        }
        let fields = result.split(separator: ",").compactMap { Int($0) }
        guard fields.count == 3 else {
            return .failed(browser: browser.diagnosticName, category: "unexpectedResult")
        }
        return .attempted(
            browser: browser.diagnosticName,
            tabsChecked: fields[0],
            mediaPaused: fields[1],
            failures: fields[2]
        )
    }

    static func combinedSummary(from summaries: [BrowserMediaControlSummary]) -> BrowserMediaControlSummary {
        let attempted = summaries.filter { $0.outcome == .attempted }
        guard !attempted.isEmpty else {
            return summaries.first ?? .browserNotRunning
        }

        return .attempted(
            browser: attempted.map(\.browser).joined(separator: "+"),
            tabsChecked: attempted.reduce(0) { $0 + $1.tabsChecked },
            mediaPaused: attempted.reduce(0) { $0 + $1.mediaPaused },
            failures: summaries.reduce(0) { $0 + $1.failures }
        )
    }

    static func appleScriptSource(applicationName: String, javascript: String) -> String {
        """
        tell application "\(applicationName)"
            set pauseScript to "\(javascript)"
            set tabCount to 0
            set pausedCount to 0
            set failureCount to 0
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabCount to tabCount + 1
                    try
                        set jsResult to execute browserTab javascript pauseScript
                        set pausedCount to pausedCount + (jsResult as integer)
                    on error
                        set failureCount to failureCount + 1
                    end try
                end repeat
            end repeat
            return (tabCount as text) & "," & (pausedCount as text) & "," & (failureCount as text)
        end tell
        """
    }

    private static let pauseJavaScript = """
    (function(){var paused=0;var media=document.querySelectorAll('audio,video');for(var i=0;i<media.length;i++){var item=media[i];if(!item.paused&&!item.ended){item.pause();paused++;}}return paused;})()
    """
}
