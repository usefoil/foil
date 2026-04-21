import SwiftUI

@main
struct GroqTalkApp: App {
    var body: some Scene {
        MenuBarExtra("GroqTalk", systemImage: "mic.fill") {
            Text("GroqTalk is running")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
