import SwiftUI

@main
struct GroqTalkApp: App {
    @State private var appState = AppState()

    private let hotkeyMonitor = HotkeyMonitor()
    private let audioRecorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
    private let textInserter = TextInserter()
    private let soundPlayer = SoundPlayer()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
                .task { await setup() }
        } label: {
            Image(systemName: appState.menuBarIcon)
        }

        Window("GroqTalk Setup", id: "api-key-setup") {
            ApiKeySetupView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    @MainActor
    private func setup() async {
        // Check accessibility permission
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        // Show API key window on first launch
        if !appState.hasApiKey {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "api-key-setup" }) {
                window.makeKeyAndOrderFront(nil)
            }
        }

        // Wire hotkey monitor
        hotkeyMonitor.onRecordingStarted = { [appState, audioRecorder, soundPlayer] in
            DispatchQueue.main.async {
                appState.setStatus(.recording)
                soundPlayer.playStartSound()
                audioRecorder.startRecording()
            }
        }
        hotkeyMonitor.onRecordingStopped = { [appState, audioRecorder, soundPlayer, transcriptionService, textInserter] in
            Task { @MainActor in
                guard let url = await audioRecorder.stopRecording() else {
                    appState.setStatus(.idle)
                    return
                }
                soundPlayer.playStopSound()
                appState.setStatus(.transcribing)

                guard let apiKey = KeychainHelper.readApiKey() else {
                    appState.showError("No API key")
                    return
                }

                do {
                    let text = try await transcriptionService.transcribe(
                        audioFileURL: url, apiKey: apiKey, model: appState.selectedModel
                    )
                    await textInserter.insert(text: text)
                    appState.setStatus(.idle)
                } catch TranscriptionService.TranscriptionError.invalidApiKey {
                    appState.showError("Invalid API key")
                } catch {
                    appState.showError("Transcription failed")
                }

                try? FileManager.default.removeItem(at: url)
            }
        }
        hotkeyMonitor.onRecordingCancelled = { [appState, audioRecorder] in
            DispatchQueue.main.async {
                audioRecorder.cancelRecording()
                appState.setStatus(.idle)
            }
        }
        hotkeyMonitor.start()
    }
}
