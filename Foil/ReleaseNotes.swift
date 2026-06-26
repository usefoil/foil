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
            title: "1.13.7",
            date: "June 25, 2026",
            highlights: [
                "Added a macOS CI eligibility check for Apple Agent Kit support.",
                "Kept Apple Agent adapter validation separate from product build, install, UI, microphone, and live transcription automation."
            ]
        ),
        ReleaseNote(
            title: "1.13.6",
            date: "June 25, 2026",
            highlights: [
                "Added transcript cleanup formatting with a dedicated Cleanup settings tab.",
                "Added OpenAI cleanup provider support using the Responses API.",
                "Showed the recording floating status by default and added the live audio signifier."
            ]
        ),
        ReleaseNote(
            title: "1.13.5",
            date: "June 12, 2026",
            highlights: [
                "Fixed Sparkle update signing for release DMGs so in-app updates can validate downloaded updates."
            ]
        )
    ]
}
