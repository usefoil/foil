import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    var history: TranscriptionHistory
    var onRetry: (() -> Void)?
    var onHotkeyChanged: (() -> Void)?

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(appState.statusText)
            .foregroundStyle(appState.isError ? .red : .secondary)

        Divider()

        Toggle("Sound Effects", isOn: $appState.soundEffectsEnabled)
        Toggle("Keep on Clipboard", isOn: $appState.keepOnClipboard)

        Divider()

        Picker("Whisper Model", selection: $appState.selectedModel) {
            Text("Large V3 Turbo (fast)").tag("whisper-large-v3-turbo")
            Text("Large V3 (accurate)").tag("whisper-large-v3")
        }

        Picker("Audio Format", selection: $appState.selectedAudioFormat) {
            Text("M4A (smaller)").tag(AudioFormat.m4a)
            Text("WAV (lossless)").tag(AudioFormat.wav)
            Text("FLAC (lossless, smaller)").tag(AudioFormat.flac)
        }

        Picker("Language", selection: $appState.selectedLanguage) {
            ForEach(Language.allCases, id: \.self) { lang in
                Text(lang.displayName).tag(lang)
            }
        }

        Menu("Hotkey") {
            // Hotkey choices
            Button {
                appState.hotkeyChoice = .rightCommand
                onHotkeyChanged?()
            } label: {
                HStack {
                    Text("Right Command")
                    if appState.hotkeyChoice == .rightCommand { Image(systemName: "checkmark") }
                }
            }

            Button {
                appState.hotkeyChoice = .rightOption
                onHotkeyChanged?()
            } label: {
                HStack {
                    Text("Right Option")
                    if appState.hotkeyChoice == .rightOption { Image(systemName: "checkmark") }
                }
            }

            Button {
                appState.hotkeyChoice = .globeFn
                onHotkeyChanged?()
            } label: {
                HStack {
                    Text("Globe / Fn")
                    if appState.hotkeyChoice == .globeFn { Image(systemName: "checkmark") }
                }
            }

            Divider()

            Button {
                appState.recordingMode = .hold
                onHotkeyChanged?()
            } label: {
                HStack {
                    Text("Hold to record")
                    if appState.recordingMode == .hold { Image(systemName: "checkmark") }
                }
            }

            Button {
                appState.recordingMode = .toggle
                onHotkeyChanged?()
            } label: {
                HStack {
                    Text("Toggle mode")
                    if appState.recordingMode == .toggle { Image(systemName: "checkmark") }
                }
            }
        }

        Divider()

        Button("Show History...") {
            NotificationCenter.default.post(name: .showHistoryPopover, object: nil)
        }

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

extension Notification.Name {
    static let showHistoryPopover = Notification.Name("showHistoryPopover")
}
