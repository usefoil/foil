import Foundation

struct ReleaseNote: Equatable, Identifiable {
    let id: String
    let title: String
    let date: String
    let highlights: [String]

    init(title: String, date: String, highlights: [String]) {
        self.id = title
        self.title = title
        self.date = date
        self.highlights = highlights
    }
}

enum ReleaseNotes {
    static let recent: [ReleaseNote] = [
        ReleaseNote(
            title: "This Build",
            date: "OpenAI Whisper",
            highlights: [
                "OpenAI Whisper is available as a cloud transcription provider.",
                "OpenAI, Groq, local whisper.cpp, and custom OpenAI-compatible providers can be selected from Transcription settings.",
                "Cloud transcription QA now includes opt-in OpenAI live tests with secrets kept out of normal PR logs."
            ]
        ),
        ReleaseNote(
            title: "1.13.4",
            date: "May 31, 2026",
            highlights: [
                "Installed-app automation smoke launches no longer get diverted into an already-running Foil process.",
                "Production cask QA validates release artifacts without moving an existing Applications install."
            ]
        ),
        ReleaseNote(
            title: "1.13.0",
            date: "May 28, 2026",
            highlights: [
                "Queued paste can collect multiple transcripts before delivery.",
                "Foil Dev now uses separate preferences, Keychain storage, diagnostics, and TCC identity.",
                "Custom OpenAI-compatible chat cleanup can route transcript cleanup to a selected endpoint."
            ]
        )
    ]
}
