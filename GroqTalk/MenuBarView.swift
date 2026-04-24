import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    var history: TranscriptionHistory
    var onRetry: (() -> Void)?
    var onHotkeyChanged: (() -> Void)?

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status
        Text(appState.statusText)
            .foregroundStyle(appState.isError ? .red : .secondary)

        Divider()

        // Toggles
        Toggle("Sound Effects", isOn: $appState.soundEffectsEnabled)
        Toggle("Keep on Clipboard", isOn: $appState.keepOnClipboard)

        Divider()

        // Whisper Model picker
        Picker("Whisper Model", selection: $appState.selectedModel) {
            Text("Large V3 Turbo (fast)").tag("whisper-large-v3-turbo")
            Text("Large V3 (accurate)").tag("whisper-large-v3")
        }

        // Audio Format picker
        Picker("Audio Format", selection: $appState.selectedAudioFormat) {
            Text("M4A (smaller)").tag("m4a")
            Text("WAV (lossless)").tag("wav")
            Text("MP3 (smallest)").tag("mp3")
        }

        // Hotkey submenu
        Menu("Hotkey") {
            // Key presets
            Button {
                appState.hotkeyChoice = "rightCommand"
                onHotkeyChanged?()
            } label: {
                HStack {
                    Text("Right Command")
                    if appState.hotkeyChoice == "rightCommand" { Image(systemName: "checkmark") }
                }
            }

            Button {
                appState.hotkeyChoice = "rightOption"
                onHotkeyChanged?()
            } label: {
                HStack {
                    Text("Right Option")
                    if appState.hotkeyChoice == "rightOption" { Image(systemName: "checkmark") }
                }
            }

            Button {
                appState.hotkeyChoice = "globeFn"
                onHotkeyChanged?()
            } label: {
                HStack {
                    Text("Globe / Fn")
                    if appState.hotkeyChoice == "globeFn" { Image(systemName: "checkmark") }
                }
            }

            Divider()

            // Recording mode
            Button {
                appState.recordingMode = "hold"
                onHotkeyChanged?()
            } label: {
                HStack {
                    Text("Hold to record")
                    if appState.recordingMode == "hold" { Image(systemName: "checkmark") }
                }
            }

            Button {
                appState.recordingMode = "toggle"
                onHotkeyChanged?()
            } label: {
                HStack {
                    Text("Toggle mode")
                    if appState.recordingMode == "toggle" { Image(systemName: "checkmark") }
                }
            }
        }

        Divider()

        // Transcription history submenu
        Menu("Recent Transcriptions") {
            if history.records.isEmpty {
                Text("No transcriptions yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history.records) { record in
                    Button {
                        if let text = record.text {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    } label: {
                        HStack {
                            if record.isFailure {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                            }
                            Text(record.previewText)
                            Spacer()
                            Text(record.relativeTimestamp)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(record.text == nil)
                }
            }
        }

        // Retry button (only when most recent transcription failed)
        if history.retryableRecord != nil {
            Button("Retry Last") {
                onRetry?()
            }
        }

        Divider()

        Button("Change API Key...") {
            openWindow(id: "api-key-setup")
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
