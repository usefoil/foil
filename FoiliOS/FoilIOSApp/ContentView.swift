import SwiftUI

struct ContentView: View {
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
                    Label("Containing app target builds", systemImage: "app.badge")
                    Label("Keyboard extension target builds", systemImage: "keyboard")
                    Label("Microphone handoff comes next", systemImage: "mic")
                }
                .font(.body)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Foil")
        }
    }
}

#Preview {
    ContentView()
}
