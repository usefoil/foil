import XCTest
@testable import GroqTalk

@MainActor
final class AppStateTests: XCTestCase {
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

    func testErrorAutoClearsAfterDelay() async throws {
        let state = AppState()
        state.showError("transient")
        XCTAssertEqual(state.status, .error("transient"))
        try await Task.sleep(for: .seconds(4))
        XCTAssertEqual(state.status, .idle)
    }

    func testErrorDoesNotClearIfStatusChanged() async throws {
        let state = AppState()
        state.showError("transient")
        state.setStatus(.recording)
        try await Task.sleep(for: .seconds(4))
        XCTAssertEqual(state.status, .recording)
    }
}
