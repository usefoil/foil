import SwiftUI

struct FloatingStatusView: View {
    @Bindable var appState: AppState
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                Image(systemName: statusIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(statusColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityIdentifier("liveFeedback.title")

                    Spacer(minLength: 8)

                    if isDismissible {
                        Button {
                            onDismiss?()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Dismiss live feedback")
                        .accessibilityIdentifier("liveFeedback.dismissButton")
                    }
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("liveFeedback.detail")

                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityIdentifier("liveFeedback.progress")
                }

                if let target = appState.capturedTargetName {
                    Label("Target: \(target)", systemImage: "scope")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("liveFeedback.target")
                }

                if let clipboard = appState.clipboardFeedback {
                    Label(clipboard, systemImage: "clipboard")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("liveFeedback.clipboard")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liveFeedback.hud")
    }

    private var title: String {
        switch appState.status {
        case .idle:
            if appState.clipboardFeedback == "Text is on the clipboard" {
                return "Copied to clipboard"
            }
            return "Done"
        case .recording:
            return "Recording \(appState.formattedRecordingDuration)"
        case .transcribing:
            return "Transcribing"
        case .error:
            return "Needs attention"
        }
    }

    private var detail: String {
        switch appState.status {
        case .idle:
            return appState.feedbackMessage ?? appState.lastPasteSummary ?? "Ready"
        case .recording:
            switch appState.recordingMode {
            case .hold:
                return "Release \(hotkeyLabel) to transcribe."
            case .toggle:
                return "Press \(hotkeyLabel) again to stop."
            }
        case .transcribing:
            if appState.transcriptProcessingMode == .raw {
                return "Sending audio to Groq. The result will paste automatically."
            }
            return "Sending audio to Groq. Cleanup may run before paste."
        case .error(let message):
            return message
        }
    }

    private var statusIcon: String {
        switch appState.status {
        case .idle:
            appState.clipboardFeedback == "Text is on the clipboard"
                ? "clipboard"
                : "checkmark.circle.fill"
        case .recording:
            "record.circle"
        case .transcribing:
            "arrow.triangle.2.circlepath"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle:
            appState.clipboardFeedback == "Text is on the clipboard" ? .orange : .green
        case .recording:
            .red
        case .transcribing:
            .blue
        case .error:
            .orange
        }
    }

    private var showsProgress: Bool {
        switch appState.status {
        case .transcribing:
            true
        default:
            false
        }
    }

    private var isDismissible: Bool {
        switch appState.status {
        case .idle, .error:
            true
        case .recording, .transcribing:
            false
        }
    }

    private var hotkeyLabel: String {
        switch appState.hotkeyChoice {
        case .rightCommand:
            "Right Command"
        case .rightOption:
            "Right Option"
        case .globeFn:
            "Globe/Fn"
        }
    }
}
