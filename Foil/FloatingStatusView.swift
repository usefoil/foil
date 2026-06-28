import Foundation
import SwiftUI

enum LiveAudioLevelScale {
    static let visualCompression: Double = 200

    static func visualLevel(for level: Float) -> Float {
        let boundedLevel = min(max(level.isFinite ? level : 0, 0), 1)
        let compressedLevel = log1p(Double(boundedLevel) * visualCompression) / log1p(visualCompression)
        return Float(compressedLevel)
    }
}

struct LiveAudioSignifierView: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            phaseIcon
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            LiveAudioLevelBars(
                levels: displayedLevels,
                phase: phase,
                barCount: 14,
                height: 22,
                tint: tint
            )
            .frame(width: 96, height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("liveAudioSignifier.capsule")
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch phase {
        case .idle:
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
        case .recording:
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
        case .processing:
            ProgressView()
                .controlSize(.small)
                .tint(tint)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var displayedLevels: [Float] {
        switch phase {
        case .recording:
            return appState.audioLevelHistory
        case .processing:
            let high: Float = appState.transcribingIconFrame == 0 ? 0.72 : 0.42
            let low: Float = appState.transcribingIconFrame == 0 ? 0.28 : 0.58
            return (0..<14).map { $0.isMultiple(of: 2) ? high : low }
        case .idle, .success, .error:
            return []
        }
    }

    private var phase: LiveAudioSignifierPhase {
        switch appState.status {
        case .idle:
            return appState.transientResult == nil ? .idle : .success
        case .recording:
            return .recording
        case .transcribing:
            return .processing
        case .error:
            return .error
        }
    }

    private var tint: Color {
        switch phase {
        case .idle:
            .secondary
        case .recording:
            .red
        case .processing:
            .blue
        case .success:
            .green
        case .error:
            .orange
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle:
            "Ready"
        case .recording:
            "Recording audio level"
        case .processing:
            "Processing recording"
        case .success:
            "Recording delivered"
        case .error:
            "Recording error"
        }
    }
}

enum LiveAudioSignifierPhase {
    case idle
    case recording
    case processing
    case success
    case error
}

struct LiveAudioLevelBars: View {
    let levels: [Float]
    let phase: LiveAudioSignifierPhase
    let barCount: Int
    let height: CGFloat
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: phase == .idle ? 2 : 3)
                    .fill(tint.opacity(opacity(at: index)))
                    .frame(width: phase == .idle ? 4 : 5, height: barHeight(at: index))
                    .animation(.easeOut(duration: 0.12), value: levels)
                    .animation(.easeInOut(duration: 0.2), value: phase)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func barHeight(at index: Int) -> CGFloat {
        switch phase {
        case .idle:
            return 4
        case .success, .error:
            return index.isMultiple(of: 2) ? 6 : 4
        case .recording, .processing:
            let floor: CGFloat = 5
            return floor + CGFloat(visualLevel(at: index)) * (height - floor)
        }
    }

    private func opacity(at index: Int) -> Double {
        switch phase {
        case .idle:
            return [0.35, 0.55, 0.35][index % 3]
        case .success, .error:
            return index < 5 || index > barCount - 6 ? 0.25 : 0.7
        case .recording, .processing:
            return 0.35 + Double(visualLevel(at: index)) * 0.65
        }
    }

    private func visualLevel(at index: Int) -> Float {
        LiveAudioLevelScale.visualLevel(for: level(at: index))
    }

    private func level(at index: Int) -> Float {
        guard !levels.isEmpty else { return 0 }
        let array = Array(levels.suffix(barCount))
        let offset = max(0, barCount - array.count)
        let levelIndex = index - offset
        guard array.indices.contains(levelIndex) else { return 0 }
        return min(max(array[levelIndex], 0), 1)
    }
}

struct FloatingStatusView: View {
    @Bindable var appState: AppState
    var onDismiss: (() -> Void)?

    private let dismissButtonSize: CGFloat = 28

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
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                        .accessibilityIdentifier("liveFeedback.title")

                    if let timerText = session.timerText {
                        Text(timerText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityIdentifier("liveFeedback.timer")
                    }

                    Spacer(minLength: 8)

                    if isDismissible {
                        dismissButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(session.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(allowsExpandedMessage ? 2 : 1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("liveFeedback.detail")

                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Transcribing")
                        .accessibilityIdentifier("liveFeedback.progress")
                }

                if let clipboard = appState.clipboardFeedback {
                    Label(clipboard, systemImage: "clipboard")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(allowsExpandedMessage ? 2 : 1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("liveFeedback.clipboard")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var dismissButton: some View {
        Button {
            onDismiss?()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: dismissButtonSize, height: dismissButtonSize)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Dismiss live feedback")
        .accessibilityIdentifier("liveFeedback.dismissButton")
        .accessibilitySortPriority(1)
        .keyboardShortcut(.cancelAction)
        .help("Dismiss live feedback")
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

    private var allowsExpandedMessage: Bool {
        switch session.tone {
        case .warning:
            true
        case .neutral, .active, .progress, .success:
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
        case .custom:
            appState.customHotkeyLabel.isEmpty ? "Custom" : appState.customHotkeyLabel
        }
    }
}
