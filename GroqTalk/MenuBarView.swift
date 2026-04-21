import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(appState.statusText)
            .foregroundStyle(appState.status == .error("") ? .red : .secondary)

        Divider()

        Toggle("Sound Effects", isOn: $appState.soundEffectsEnabled)

        Picker("Whisper Model", selection: $appState.selectedModel) {
            Text("Large V3 Turbo (fast)").tag("whisper-large-v3-turbo")
            Text("Large V3 (accurate)").tag("whisper-large-v3")
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
