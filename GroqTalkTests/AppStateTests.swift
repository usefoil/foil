import XCTest
@testable import GroqTalk

@MainActor
final class AppStateTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "audioFormat")
        UserDefaults.standard.removeObject(forKey: "keepOnClipboard")
        UserDefaults.standard.removeObject(forKey: "recordingMode")
        UserDefaults.standard.removeObject(forKey: "hotkeyChoice")
    }

    func testInitialStatusIsIdle() {
        let state = AppState()
        XCTAssertEqual(state.status, .idle)
    }

    func testTransitionToRecording() {
        let state = AppState()
        state.setStatus(.recording)
        XCTAssertEqual(state.status, .recording)
    }

    func testTransitionToTranscribing() {
        let state = AppState()
        state.setStatus(.transcribing)
        XCTAssertEqual(state.status, .transcribing)
    }

    func testShowErrorSetsErrorStatus() {
        let state = AppState()
        state.showError("something broke")
        XCTAssertEqual(state.status, .error("something broke"))
    }

    func testErrorPersistsUntilCleared() {
        let state = AppState()
        state.showError("persistent error")
        XCTAssertEqual(state.status, .error("persistent error"))
    }

    func testClearErrorResetsToIdle() {
        let state = AppState()
        state.showError("will be cleared")
        state.clearError()
        XCTAssertEqual(state.status, .idle)
    }

    func testClearErrorNoOpWhenNotError() {
        let state = AppState()
        state.setStatus(.recording)
        state.clearError()
        XCTAssertEqual(state.status, .recording)
    }

    // MARK: - Audio format

    func testDefaultAudioFormat() {
        let state = AppState()
        XCTAssertEqual(state.selectedAudioFormat, "m4a")
    }

    func testSetAudioFormat() {
        let state = AppState()
        state.selectedAudioFormat = "wav"
        XCTAssertEqual(state.selectedAudioFormat, "wav")
    }

    // MARK: - Keep on clipboard

    func testDefaultKeepOnClipboard() {
        let state = AppState()
        XCTAssertFalse(state.keepOnClipboard)
    }

    func testSetKeepOnClipboard() {
        let state = AppState()
        state.keepOnClipboard = true
        XCTAssertTrue(state.keepOnClipboard)
    }

    // MARK: - Recording mode

    func testDefaultRecordingMode() {
        let state = AppState()
        XCTAssertEqual(state.recordingMode, "hold")
    }

    func testSetRecordingMode() {
        let state = AppState()
        state.recordingMode = "toggle"
        XCTAssertEqual(state.recordingMode, "toggle")
    }

    // MARK: - Hotkey choice

    func testDefaultHotkeyChoice() {
        let state = AppState()
        XCTAssertEqual(state.hotkeyChoice, "rightCommand")
    }

    func testSetHotkeyChoice() {
        let state = AppState()
        state.hotkeyChoice = "rightOption"
        XCTAssertEqual(state.hotkeyChoice, "rightOption")
    }

    // MARK: - Recording timer

    func testRecordingDurationStartsAtZero() {
        let state = AppState()
        XCTAssertEqual(state.recordingDuration, 0)
    }

    func testRecordingStartTimeNilWhenIdle() {
        let state = AppState()
        XCTAssertNil(state.recordingStartTime)
    }

    // MARK: - Menu bar icon

    func testMenuBarIconIdle() {
        let state = AppState()
        XCTAssertEqual(state.menuBarIcon, "waveform")
    }

    func testMenuBarIconRecording() {
        let state = AppState()
        state.setStatus(.recording)
        XCTAssertEqual(state.menuBarIcon, "waveform.circle.fill")
    }

    func testMenuBarIconTranscribingCycles() {
        let state = AppState()
        state.setStatus(.transcribing)
        state.transcribingIconFrame = 0
        XCTAssertEqual(state.menuBarIcon, "ellipsis.circle")
        state.transcribingIconFrame = 1
        XCTAssertEqual(state.menuBarIcon, "ellipsis.circle.fill")
    }

    func testMenuBarIconError() {
        let state = AppState()
        state.showError("fail")
        XCTAssertEqual(state.menuBarIcon, "exclamationmark.triangle.fill")
    }
}
