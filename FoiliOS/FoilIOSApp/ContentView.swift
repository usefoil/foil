import SwiftUI

struct ContentView: View {
    private let bridge = FoilKeyboardBridge()
    private let actionColumns = [
        GridItem(.flexible(minimum: 118), spacing: 10),
        GridItem(.flexible(minimum: 118), spacing: 10)
    ]

    @StateObject private var audioCapture = AudioCaptureController()
    @StateObject private var transcription = TranscriptionController()
    @State private var snapshot = FoilKeyboardSnapshot.initial
    @State private var storageReport = FoilKeyboardStorageReport.initial
    @State private var keyboardHealth = FoilKeyboardHealthReport.initial
    @State private var secureEntry = ""
    private let refreshTimer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Foil iOS")
                            .font(.title.weight(.semibold))
                        Text("Keyboard shell ready")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        statusRow(snapshot.phase.displayName, systemImage: "waveform")
                        statusRow(snapshot.message, systemImage: "keyboard")
                        statusRow(audioCapture.status, systemImage: "mic")
                        statusRow(transcription.status, systemImage: "text.bubble")
                        statusRow(storageReportSummary, systemImage: "externaldrive")
                            .accessibilityIdentifier("keyboard-storage-report-summary")
                        if let transcript = snapshot.transcript {
                            statusRow(transcript, systemImage: "text.quote")
                        }
                        if let lastRecordingURL = audioCapture.lastRecordingURL {
                            statusRow(lastRecordingURL.lastPathComponent, systemImage: "waveform.path")
                                .font(.caption.monospaced())
                        }
                    }
                    .font(.callout)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Keyboard setup")
                            .font(.headline)

                        setupRow(
                            title: "Add Foil Keyboard",
                            detail: "Settings > General > Keyboard > Keyboards",
                            systemImage: "keyboard"
                        )
                        setupRow(
                            title: "Allow Full Access",
                            detail: "Required so Foil Keyboard can read and clear dictation state",
                            systemImage: "checkmark.shield"
                        )
                        setupRow(
                            title: "Keyboard health",
                            detail: keyboardHealthSummary,
                            systemImage: keyboardHealth.fullAccessState == .enabled ? "checkmark.circle" : "exclamationmark.circle"
                        )
                        setupRow(
                            title: "Shared state",
                            detail: storageHealthSummary,
                            systemImage: "externaldrive"
                        )

                        Button {
                            bridge.reset()
                            refresh()
                        } label: {
                            Label("Reset shared state", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("setup-reset-shared-state-button")
                    }
                    .font(.callout)

                    SecureField("Secure field rejection test", text: $secureEntry)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("secure-rejection-field")
                        .textFieldStyle(.roundedBorder)

                    LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 10) {
                        Button {
                            bridge.markListening()
                            refresh()
                        } label: {
                            Label("Listening", systemImage: "waveform")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("mark-listening-button")

                        Button {
                            bridge.completeFakeTranscript()
                            refresh()
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("complete-fake-transcript-button")

                        Button {
                            bridge.reset()
                            refresh()
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("reset-keyboard-state-button")

                        Button {
                            Task { await audioCapture.startRecording() }
                        } label: {
                            Label("Record", systemImage: "record.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(audioCapture.isRecording)
                        .accessibilityIdentifier("start-recording-button")

                        Button {
                            audioCapture.stopRecording()
                            refresh()
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!audioCapture.isRecording)
                        .accessibilityIdentifier("stop-recording-button")

                        Button {
                            Task { await transcription.transcribeLatestRecording(audioCapture.lastRecordingURL) }
                        } label: {
                            Label("Transcribe", systemImage: "text.bubble")
                        }
                        .buttonStyle(.bordered)
                        .disabled(audioCapture.lastRecordingURL == nil || audioCapture.isRecording)
                        .accessibilityIdentifier("transcribe-latest-button")
                    }
                    .controlSize(.large)
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.roundedRectangle(radius: 8))

                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Foil")
            .onAppear(perform: refresh)
            .onReceive(refreshTimer) { _ in refresh() }
            .onOpenURL { url in
                guard url.scheme == FoilIOSConstants.appURLScheme else { return }
                switch url.host {
                case "keyboard-health":
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let fullAccessValue = components?.queryItems?.first { $0.name == "fullAccess" }?.value
                    bridge.recordKeyboardHealth(fullAccessEnabled: fullAccessValue == "on", snapshot: bridge.load())
                case "complete":
                    bridge.completeFakeTranscript()
                case "reset":
                    bridge.reset()
                case "start":
                    bridge.markListening()
                    Task { await audioCapture.startRecording() }
                case "stop":
                    audioCapture.stopRecording()
                case "transcribe":
                    Task { await transcription.transcribeLatestRecording(audioCapture.lastRecordingURL) }
                default:
                    bridge.markListening()
                }
                refresh()
            }
        }
    }

    private func refresh() {
        snapshot = bridge.load()
        storageReport = bridge.storageReport()
        keyboardHealth = bridge.keyboardHealthReport()
    }

    private var storageReportSummary: String {
        let file = storageReport.canonicalWriteSucceeded ? "file ok" : "file failed"
        let verifiedPhase = storageReport.canonicalVerificationPhase?.displayName ?? "unverified"
        let verifiedTranscript = storageReport.canonicalVerificationHasTranscript == true ? "has transcript" : "no transcript"
        let defaults = storageReport.defaultsWriteAttempted ? "defaults written" : "defaults not written"
        return "Storage \(storageReport.operation): \(file), \(defaults), verified \(verifiedPhase) \(verifiedTranscript)"
    }

    private var keyboardHealthSummary: String {
        switch keyboardHealth.fullAccessState {
        case .unverified:
            "Open Foil Keyboard in a text field to verify"
        case .disabled:
            "Last verified by keyboard: Full Access off"
        case .enabled:
            keyboardHealth.snapshotHasTranscript ? "Last verified by keyboard: Full Access on, transcript waiting" : "Last verified by keyboard: Full Access on, ready for dictation"
        }
    }

    private var storageHealthSummary: String {
        if snapshot.transcript?.isEmpty == false {
            return "Transcript pending"
        }
        if snapshot.phase == .idle {
            return "Ready, no transcript"
        }
        return snapshot.phase.displayName
    }

    private func statusRow(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        } icon: {
            Image(systemName: systemImage)
        }
    }

    private func setupRow(title: String, detail: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

#Preview {
    ContentView()
}
