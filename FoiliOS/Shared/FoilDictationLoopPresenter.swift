import Foundation

enum FoilLoopTone: Equatable {
    case ready
    case live
    case working
    case success
    case attention
}

enum FoilAppPrimaryAction: Equatable {
    case record
    case stopRecording
    case createTranscript
    case retryTranscript
    case reset

    var title: String {
        switch self {
        case .record:
            "Record in Foil"
        case .stopRecording:
            "Finish recording"
        case .createTranscript:
            "Create transcript"
        case .retryTranscript:
            "Retry transcript"
        case .reset:
            "Reset dictation"
        }
    }

    var systemImage: String {
        switch self {
        case .record:
            "record.circle"
        case .stopRecording:
            "stop.circle"
        case .createTranscript:
            "text.bubble"
        case .retryTranscript:
            "arrow.clockwise"
        case .reset:
            "arrow.counterclockwise"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .record:
            "primary-record-dictation-button"
        case .stopRecording:
            "primary-finish-recording-button"
        case .createTranscript:
            "primary-create-transcript-button"
        case .retryTranscript:
            "primary-retry-transcript-button"
        case .reset:
            "primary-reset-dictation-button"
        }
    }
}

struct FoilAppLoopPresentation: Equatable {
    var title: String
    var badge: String
    var detail: String
    var systemImage: String
    var tone: FoilLoopTone
    var primaryAction: FoilAppPrimaryAction?
}

struct FoilKeyboardLoopPresentation: Equatable {
    var status: String
    var message: String
    var insertTitle: String
    var clearTitle: String
    var startTitle: String
}

struct FoilKeyboardHealthPresentation: Equatable {
    var detail: String
    var recoveryMessage: String?
    var recoverySteps: [String]
}

struct FoilTranscriptReviewPresentation: Equatable {
    var transcript: String
    var guidance: String
    var retryTitle: String
    var resetTitle: String
    var canRetryRecording: Bool
}

enum FoilDictationLoopPresenter {
    static func transcriptReviewPresentation(
        snapshot: FoilKeyboardSnapshot,
        hasSavedRecording: Bool
    ) -> FoilTranscriptReviewPresentation? {
        guard let transcript = snapshot.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty else {
            return nil
        }

        return FoilTranscriptReviewPresentation(
            transcript: transcript,
            guidance: "Review before inserting. If this looks wrong, retry the recording or reset and record again.",
            retryTitle: "Retry recording",
            resetTitle: "Reset and record again",
            canRetryRecording: hasSavedRecording
        )
    }

    static func keyboardHealthPresentation(
        report: FoilKeyboardHealthReport,
        now: Date = Date(),
        staleAfter: TimeInterval = 120
    ) -> FoilKeyboardHealthPresentation {
        switch report.fullAccessState {
        case .disabled:
            let message = "Allow Full Access is off. Enable it in Keyboard settings, then reopen Foil Keyboard."
            return FoilKeyboardHealthPresentation(
                detail: message,
                recoveryMessage: message,
                recoverySteps: [
                    "Open Settings > General > Keyboard > Keyboards.",
                    "Select Foil Keyboard and enable Allow Full Access.",
                    "Return to the target field and cycle back to Foil Keyboard."
                ]
            )
        case .unverified:
            let message = "Open Foil Keyboard in a text field to verify Full Access."
            return FoilKeyboardHealthPresentation(
                detail: message,
                recoveryMessage: message,
                recoverySteps: [
                    "Open a safe text field.",
                    "Switch to Foil Keyboard.",
                    "Return to Foil and check Keyboard health again."
                ]
            )
        case .enabled:
            if now.timeIntervalSince(report.updatedAt) > staleAfter {
                let message = "Foil Keyboard has not checked in recently. Tap the target field and cycle back to Foil Keyboard."
                return FoilKeyboardHealthPresentation(
                    detail: message,
                    recoveryMessage: message,
                    recoverySteps: [
                        "Tap the target text field.",
                        "Switch away from Foil Keyboard, then back.",
                        "Return here if Insert latest still looks stale."
                    ]
                )
            }

            let detail = report.snapshotHasTranscript
                ? "Full Access on, transcript waiting in keyboard."
                : "Full Access on, ready for dictation."
            return FoilKeyboardHealthPresentation(detail: detail, recoveryMessage: nil, recoverySteps: [])
        }
    }

    static func appPresentation(
        snapshot: FoilKeyboardSnapshot,
        isRecording: Bool,
        hasSavedRecording: Bool,
        isTranscribing: Bool,
        recoveryMessage: String?
    ) -> FoilAppLoopPresentation {
        if isRecording || snapshot.phase == .listening {
            return FoilAppLoopPresentation(
                title: "Recording in Foil",
                badge: "Live",
                detail: "Speak naturally. Finish recording here, then create a transcript for Foil Keyboard.",
                systemImage: "waveform.circle.fill",
                tone: .live,
                primaryAction: .stopRecording
            )
        }

        if snapshot.transcript?.isEmpty == false || snapshot.phase == .complete {
            return FoilAppLoopPresentation(
                title: "Ready for keyboard",
                badge: "Return",
                detail: "Return to the text field and tap Insert latest in Foil Keyboard.",
                systemImage: "keyboard.badge.ellipsis",
                tone: .success,
                primaryAction: nil
            )
        }

        if snapshot.phase == .processing || isTranscribing {
            return FoilAppLoopPresentation(
                title: "Creating transcript",
                badge: "Working",
                detail: "Foil is turning the latest recording into text for the keyboard.",
                systemImage: "text.bubble.fill",
                tone: .working,
                primaryAction: nil
            )
        }

        if snapshot.phase == .failed || recoveryMessage != nil {
            return FoilAppLoopPresentation(
                title: "Try again",
                badge: "Recover",
                detail: recoveryMessage ?? snapshot.message,
                systemImage: "exclamationmark.circle.fill",
                tone: .attention,
                primaryAction: hasSavedRecording ? .retryTranscript : .reset
            )
        }

        if hasSavedRecording {
            return FoilAppLoopPresentation(
                title: "Recording saved",
                badge: "Next",
                detail: "Create a transcript, then return to your keyboard to insert it.",
                systemImage: "waveform.badge.checkmark",
                tone: .working,
                primaryAction: .createTranscript
            )
        }

        return FoilAppLoopPresentation(
            title: "Record in Foil",
            badge: "Start",
            detail: "Record here. Return to your keyboard when the transcript is ready.",
            systemImage: "mic.circle.fill",
            tone: .ready,
            primaryAction: .record
        )
    }

    static func keyboardPresentation(
        snapshot: FoilKeyboardSnapshot,
        fullAccessEnabled: Bool
    ) -> FoilKeyboardLoopPresentation {
        guard fullAccessEnabled else {
            return FoilKeyboardLoopPresentation(
                status: "Open Foil",
                message: "Allow Full Access in Settings, then cycle back to Foil Keyboard.",
                insertTitle: "Insert unavailable",
                clearTitle: "Clear unavailable",
                startTitle: "Open Foil"
            )
        }

        let hasTranscript = snapshot.transcript?.isEmpty == false
        switch snapshot.phase {
        case .complete where hasTranscript:
            return FoilKeyboardLoopPresentation(
                status: "Transcript ready",
                message: "Tap Insert latest once, then keep typing.",
                insertTitle: "Insert latest",
                clearTitle: "Clear latest",
                startTitle: "Dictate again in Foil"
            )
        case .failed:
            return FoilKeyboardLoopPresentation(
                status: "Try again in Foil",
                message: "\(snapshot.message) Open Foil to recover or record again.",
                insertTitle: "No transcript yet",
                clearTitle: "Clear",
                startTitle: "Record again in Foil"
            )
        case .handoffRequested, .listening:
            return FoilKeyboardLoopPresentation(
                status: "Recording in Foil",
                message: "Finish recording in Foil, then return here when the transcript is ready.",
                insertTitle: "No transcript yet",
                clearTitle: "Clear",
                startTitle: "Open Foil"
            )
        case .processing:
            return FoilKeyboardLoopPresentation(
                status: "Creating transcript",
                message: "Foil is preparing text. Return here when Insert latest is ready.",
                insertTitle: "No transcript yet",
                clearTitle: "Clear",
                startTitle: "Open Foil"
            )
        case .idle, .complete:
            return FoilKeyboardLoopPresentation(
                status: "Ready to dictate",
                message: "Tap Dictate in Foil to record in the app, then return here.",
                insertTitle: "No transcript yet",
                clearTitle: "Clear",
                startTitle: "Dictate in Foil"
            )
        }
    }
}
