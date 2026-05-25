import XCTest
@testable import Foil

private final class StubBrowserMediaRunner: BrowserMediaScriptRunning {
    var result: BrowserMediaControlSummary = .browserNotRunning
    var error: Error?
    private(set) var pauseCallCount = 0

    func pausePlayingMedia() async throws -> BrowserMediaControlSummary {
        pauseCallCount += 1
        if let error {
            throw error
        }
        return result
    }
}

@MainActor
final class BrowserMediaControllerTests: XCTestCase {
    func testRecordingStartSkipsRunnerWhenDisabled() async {
        let runner = StubBrowserMediaRunner()
        let controller = BrowserMediaController(isEnabled: { false }, scriptRunner: runner)

        let summary = await controller.recordingDidStartAndPause()

        XCTAssertEqual(summary, .disabled)
        XCTAssertEqual(runner.pauseCallCount, 0)
        XCTAssertFalse(controller.hasActiveSession)
    }

    func testRecordingStartHandlesBrowserNotRunning() async {
        let runner = StubBrowserMediaRunner()
        runner.result = .browserNotRunning
        let controller = BrowserMediaController(isEnabled: { true }, scriptRunner: runner)

        let summary = await controller.recordingDidStartAndPause()

        XCTAssertEqual(summary, .browserNotRunning)
        XCTAssertEqual(runner.pauseCallCount, 1)
        XCTAssertTrue(controller.hasActiveSession)

        controller.recordingDidEnd(reason: .stopped)
        XCTAssertFalse(controller.hasActiveSession)
    }

    func testRecordingStartReturnsAttemptedSummary() async {
        let runner = StubBrowserMediaRunner()
        runner.result = .attempted(browser: "chrome", tabsChecked: 3, mediaPaused: 2, failures: 1)
        let controller = BrowserMediaController(isEnabled: { true }, scriptRunner: runner)

        let summary = await controller.recordingDidStartAndPause()

        XCTAssertEqual(
            summary,
            .attempted(browser: "chrome", tabsChecked: 3, mediaPaused: 2, failures: 1)
        )
        XCTAssertEqual(runner.pauseCallCount, 1)
        XCTAssertTrue(controller.hasActiveSession)
    }

    func testRecordingStartConvertsRunnerFailureToNonThrowingSummary() async {
        struct ExpectedError: Error {}

        let runner = StubBrowserMediaRunner()
        runner.error = ExpectedError()
        let controller = BrowserMediaController(isEnabled: { true }, scriptRunner: runner)

        let summary = await controller.recordingDidStartAndPause()

        XCTAssertEqual(summary, .failed(category: "commandFailed"))
        XCTAssertEqual(runner.pauseCallCount, 1)
        XCTAssertTrue(controller.hasActiveSession)
    }

    func testRecordingEndDoesNotRunBrowserCommandAgain() async {
        let runner = StubBrowserMediaRunner()
        runner.result = .attempted(browser: "chrome", tabsChecked: 1, mediaPaused: 1, failures: 0)
        let controller = BrowserMediaController(isEnabled: { true }, scriptRunner: runner)

        _ = await controller.recordingDidStartAndPause()
        controller.recordingDidEnd(reason: .cancelled)
        controller.recordingDidEnd(reason: .failed)

        XCTAssertEqual(runner.pauseCallCount, 1)
        XCTAssertFalse(controller.hasActiveSession)
    }

    func testRecordingEndBeforeAsyncAttemptPreventsBrowserCommand() async {
        let runner = StubBrowserMediaRunner()
        runner.result = .attempted(browser: "chrome", tabsChecked: 1, mediaPaused: 1, failures: 0)
        let controller = BrowserMediaController(isEnabled: { true }, scriptRunner: runner)

        let sessionID = controller.recordingDidStart()
        XCTAssertNotNil(sessionID)
        controller.recordingDidEnd(reason: .stopped)

        if let sessionID {
            _ = await controller.pausePlayingMedia(for: sessionID)
        }

        XCTAssertEqual(runner.pauseCallCount, 0)
        XCTAssertFalse(controller.hasActiveSession)
    }

    func testChromeAppleScriptSourceCompiles() {
        let source = ChromeBrowserMediaScriptRunner.appleScriptSource(
            applicationName: "Google Chrome",
            javascript: "(function(){return 0;})()"
        )
        let script = NSAppleScript(source: source)
        var errorInfo: NSDictionary?

        XCTAssertTrue(script?.compileAndReturnError(&errorInfo) == true, "\(errorInfo ?? [:])")
    }

    func testChromeScriptRunnerCombinesRunningBrowserSummaries() {
        let summary = ChromeBrowserMediaScriptRunner.combinedSummary(from: [
            .attempted(browser: "chrome", tabsChecked: 2, mediaPaused: 1, failures: 0),
            .attempted(browser: "chromium", tabsChecked: 3, mediaPaused: 2, failures: 1)
        ])

        XCTAssertEqual(
            summary,
            .attempted(browser: "chrome+chromium", tabsChecked: 5, mediaPaused: 3, failures: 1)
        )
    }

    func testChromeScriptRunnerCombinesAttemptWithScriptFailure() {
        let summary = ChromeBrowserMediaScriptRunner.combinedSummary(from: [
            .attempted(browser: "chrome", tabsChecked: 2, mediaPaused: 1, failures: 0),
            .failed(browser: "chromium", category: "scriptError")
        ])

        XCTAssertEqual(
            summary,
            .attempted(browser: "chrome", tabsChecked: 2, mediaPaused: 1, failures: 1)
        )
    }
}
