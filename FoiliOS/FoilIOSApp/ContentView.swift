import SwiftUI

struct ContentView: View {
    private let bridge = FoilKeyboardBridge()

    @StateObject private var audioCapture = AudioCaptureController()
    @StateObject private var transcription = TranscriptionController()
    @State private var snapshot = FoilKeyboardSnapshot.initial
    private let refreshTimer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Foil iOS")
                            .font(.largeTitle.weight(.semibold))
                        Text("Keyboard shell ready")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label(snapshot.phase.displayName, systemImage: "waveform")
                        Label(snapshot.message, systemImage: "keyboard")
                        Label(audioCapture.status, systemImage: "mic")
                        Label(transcription.status, systemImage: "text.bubble")
                        if let transcript = snapshot.transcript {
                            Label(transcript, systemImage: "text.quote")
                        }
                        if let lastRecordingURL = audioCapture.lastRecordingURL {
                            Label(lastRecordingURL.lastPathComponent, systemImage: "waveform.path")
                        }
                    }
                    .font(.body)

                    HStack(spacing: 12) {
                        Button("Listening") {
                            bridge.markListening()
                            refresh()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("mark-listening-button")

                        Button("Complete") {
                            bridge.completeFakeTranscript()
                            refresh()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("complete-fake-transcript-button")

                        Button("Reset") {
                            bridge.reset()
                            refresh()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("reset-keyboard-state-button")
                    }

                    HStack(spacing: 12) {
                        Button("Record") {
                            Task { await audioCapture.startRecording() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(audioCapture.isRecording)
                        .accessibilityIdentifier("start-recording-button")

                        Button("Stop") {
                            audioCapture.stopRecording()
                            refresh()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!audioCapture.isRecording)
                        .accessibilityIdentifier("stop-recording-button")

                        Button("Transcribe") {
                            Task { await transcription.transcribeLatestRecording(audioCapture.lastRecordingURL) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(audioCapture.lastRecordingURL == nil || audioCapture.isRecording)
                        .accessibilityIdentifier("transcribe-latest-button")
                    }

                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Foil")
            .onAppear(perform: refresh)
            .onReceive(refreshTimer) { _ in refresh() }
            .onOpenURL { url in
                guard url.scheme == FoilIOSConstants.appURLScheme else { return }
                switch url.host {
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
    }
}

#Preview {
    ContentView()
}
