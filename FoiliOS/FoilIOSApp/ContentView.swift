import SwiftUI

struct ContentView: View {
    private let bridge = FoilKeyboardBridge()

    @State private var snapshot = FoilKeyboardSnapshot.initial
    private let refreshTimer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
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
                    if let transcript = snapshot.transcript {
                        Label(transcript, systemImage: "text.quote")
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

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
