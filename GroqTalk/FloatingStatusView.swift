import SwiftUI

struct FloatingStatusView: View {
    @Bindable var appState: AppState
    var onDismiss: (() -> Void)?

    private var session: AppState.SessionPresentation {
        appState.sessionPresentation(
            hotkeyLabel: hotkeyLabel,
            hasRetryableFailure: false,
            hasLastSuccess: false
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(sessionColor.opacity(0.16))
                Image(systemName: session.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(sessionColor)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .accessibilityIdentifier("liveFeedback.title")

                    if let timerText = session.timerText {
                        Text(timerText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("liveFeedback.timer")
                    }

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

                Text(session.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("liveFeedback.detail")

                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityIdentifier("liveFeedback.progress")
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
        .padding(.vertical, 10)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(sessionColor.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liveFeedback.hud")
    }

    private var sessionColor: Color {
        switch session.tone {
        case .neutral:
            .accentColor
        case .active:
            .red
        case .progress:
            .blue
        case .success:
            .green
        case .warning:
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
