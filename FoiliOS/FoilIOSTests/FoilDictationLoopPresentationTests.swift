import XCTest
@testable import FoilIOS

final class FoilDictationLoopPresentationTests: XCTestCase {
    func testAppReadyStateTellsUserToRecordInFoilAndReturnToKeyboard() {
        let presentation = FoilDictationLoopPresenter.appPresentation(
            snapshot: .initial,
            isRecording: false,
            hasSavedRecording: false,
            isTranscribing: false,
            recoveryMessage: nil
        )

        XCTAssertEqual(presentation.title, "Record in Foil")
        XCTAssertEqual(presentation.primaryAction, .record)
        XCTAssertTrue(presentation.detail.contains("Return to your keyboard"))
    }

    func testAppCompleteStatePointsBackToTargetAppAndKeyboardInsert() {
        let presentation = FoilDictationLoopPresenter.appPresentation(
            snapshot: FoilKeyboardSnapshot(
                phase: .complete,
                transcript: "hello foil",
                message: "Groq transcript ready.",
                updatedAt: Date()
            ),
            isRecording: false,
            hasSavedRecording: true,
            isTranscribing: false,
            recoveryMessage: nil
        )

        XCTAssertEqual(presentation.title, "Ready for keyboard")
        XCTAssertNil(presentation.primaryAction)
        XCTAssertTrue(presentation.detail.contains("Return to the text field"))
        XCTAssertTrue(presentation.detail.contains("Insert latest"))
    }

    func testAppFailureStateOffersRetryWhenRecordingExists() {
        let presentation = FoilDictationLoopPresenter.appPresentation(
            snapshot: FoilKeyboardSnapshot(
                phase: .failed,
                transcript: nil,
                message: "No speech detected. Record again in Foil.",
                updatedAt: Date()
            ),
            isRecording: false,
            hasSavedRecording: true,
            isTranscribing: false,
            recoveryMessage: "No speech detected. Record again, then return to the keyboard."
        )

        XCTAssertEqual(presentation.title, "Try again")
        XCTAssertEqual(presentation.primaryAction, .retryTranscript)
        XCTAssertTrue(presentation.detail.contains("No speech detected"))
    }

    func testKeyboardIdleStateExplainsHandoffInsteadOfSayingNoTranscriptOnly() {
        let presentation = FoilDictationLoopPresenter.keyboardPresentation(
            snapshot: .initial,
            fullAccessEnabled: true
        )

        XCTAssertEqual(presentation.status, "Ready to dictate")
        XCTAssertEqual(presentation.insertTitle, "No transcript yet")
        XCTAssertEqual(presentation.startTitle, "Dictate in Foil")
        XCTAssertTrue(presentation.message.contains("record in the app"))
    }

    func testKeyboardFailureStatePointsBackToFoilForRecovery() {
        let presentation = FoilDictationLoopPresenter.keyboardPresentation(
            snapshot: FoilKeyboardSnapshot(
                phase: .failed,
                transcript: nil,
                message: "No speech detected. Record again in Foil.",
                updatedAt: Date()
            ),
            fullAccessEnabled: true
        )

        XCTAssertEqual(presentation.status, "Try again in Foil")
        XCTAssertEqual(presentation.startTitle, "Record again in Foil")
        XCTAssertTrue(presentation.message.contains("No speech detected"))
        XCTAssertTrue(presentation.message.contains("Open Foil"))
    }

    func testKeyboardFullAccessOffTellsUserToEnableAndCycleBack() {
        let presentation = FoilDictationLoopPresenter.keyboardPresentation(
            snapshot: .initial,
            fullAccessEnabled: false
        )

        XCTAssertEqual(presentation.status, "Open Foil")
        XCTAssertEqual(presentation.insertTitle, "Insert unavailable")
        XCTAssertTrue(presentation.message.contains("Allow Full Access"))
        XCTAssertTrue(presentation.message.contains("cycle back"))
    }

    func testKeyboardHealthPresentationDetectsUnverifiedState() {
        let presentation = FoilDictationLoopPresenter.keyboardHealthPresentation(
            report: .initial,
            now: Date(timeIntervalSince1970: 500)
        )

        XCTAssertTrue(presentation.detail.contains("Open Foil Keyboard"))
        XCTAssertEqual(presentation.recoveryMessage, presentation.detail)
    }

    func testKeyboardHealthPresentationPrioritizesFullAccessOff() {
        let report = FoilKeyboardHealthReport(
            fullAccessState: .disabled,
            snapshotPhase: .complete,
            snapshotHasTranscript: true,
            message: "Allow Full Access required",
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let presentation = FoilDictationLoopPresenter.keyboardHealthPresentation(
            report: report,
            now: Date(timeIntervalSince1970: 101)
        )

        XCTAssertTrue(presentation.detail.contains("Allow Full Access is off"))
        XCTAssertTrue(presentation.detail.contains("reopen Foil Keyboard"))
        XCTAssertEqual(presentation.recoveryMessage, presentation.detail)
    }

    func testKeyboardHealthPresentationDetectsStaleEnabledKeyboard() {
        let report = FoilKeyboardHealthReport(
            fullAccessState: .enabled,
            snapshotPhase: .idle,
            snapshotHasTranscript: false,
            message: "Foil Keyboard verified",
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let presentation = FoilDictationLoopPresenter.keyboardHealthPresentation(
            report: report,
            now: Date(timeIntervalSince1970: 300),
            staleAfter: 120
        )

        XCTAssertTrue(presentation.detail.contains("not checked in recently"))
        XCTAssertTrue(presentation.detail.contains("cycle back"))
        XCTAssertEqual(presentation.recoveryMessage, presentation.detail)
    }

    func testKeyboardHealthPresentationKeepsFreshEnabledStateQuiet() {
        let report = FoilKeyboardHealthReport(
            fullAccessState: .enabled,
            snapshotPhase: .complete,
            snapshotHasTranscript: true,
            message: "Foil Keyboard verified",
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let presentation = FoilDictationLoopPresenter.keyboardHealthPresentation(
            report: report,
            now: Date(timeIntervalSince1970: 110),
            staleAfter: 120
        )

        XCTAssertEqual(presentation.detail, "Full Access on, transcript waiting in keyboard.")
        XCTAssertNil(presentation.recoveryMessage)
    }
}
