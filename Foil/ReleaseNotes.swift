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
            title: "1.16.0",
            date: "October 29, 2026",
            highlights: [
                "Install and switch local model sizes directly in Settings.",
                "Medium English becomes the default for new English-only setups; existing selections stay intact."
            ]
        ),
        ReleaseNote(
            title: "1.15.1",
            date: "October 20, 2026",
            highlights: [
                "Catch up on every release since June with clear notes in What's New.",
                "Release checks now help keep these notes current with future app updates."
            ]
        ),
        ReleaseNote(
            title: "1.15.0",
            date: "October 18, 2026",
            highlights: [
                "Review and apply Vocabulary suggestions from paired agents in one place, with a clear record of what changed.",
                "Give agents permission for specific Vocabulary actions and apps, and review several suggested changes together.",
                "Save preferred spellings for all apps or a Cleanup Group, and organize corrections for individual apps.",
                "Enjoy smoother local transcription, including more natural text across speech segments and faster first starts for managed models."
            ]
        ),
        ReleaseNote(
            title: "1.14.3",
            date: "September 23, 2026",
            highlights: [
                "Connect a local Codex agent to Foil's Vocabulary through the new Agent Access settings.",
                "Review, edit, or reject an agent's suggested words and corrections before they change your Vocabulary.",
                "Vocabulary changes stay responsive even when you have many correction rules."
            ]
        ),
        ReleaseNote(
            title: "1.14.2",
            date: "September 20, 2026",
            highlights: [
                "Correct exact words and phrases in transcripts instantly, such as product names that speech recognition often gets wrong.",
                "Apply a correction everywhere or only in a Cleanup Group, so different apps can use different terminology.",
                "Preview, edit, pause, and delete corrections in Vocabulary settings."
            ]
        ),
        ReleaseNote(
            title: "1.14.1",
            date: "September 18, 2026",
            highlights: [
                "Fixed startup of advanced external whisper.cpp servers when Foil is opened outside Terminal, with clearer FFmpeg setup guidance."
            ]
        ),
        ReleaseNote(
            title: "1.14.0",
            date: "September 17, 2026",
            highlights: [
                "Set up private, on-device transcription in Foil: download a recommended Whisper model and let Foil run it for you.",
                "Follow a clearer first-run setup with a practice transcription, shortcut guidance, and a way to recover your last result.",
                "Keep History Off and retention choices across launches; your last result remains recoverable in memory when history is off.",
                "Switch local models more reliably and get clearer feedback when downloads or local servers need attention."
            ]
        ),
        ReleaseNote(
            title: "1.13.13",
            date: "July 22, 2026",
            highlights: [
                "Silent recordings and empty transcription results no longer create history entries or paste stray text.",
                "Very quiet speech and short words still go through transcription."
            ]
        ),
        ReleaseNote(
            title: "1.13.12",
            date: "July 19, 2026",
            highlights: [
                "Start and stop a local whisper.cpp server from Foil without keeping Terminal open.",
                "See clearer local model setup and startup status, including when a large model takes time to load.",
                "Microphone and Accessibility permission status now refreshes when you open the menu."
            ]
        ),
        ReleaseNote(
            title: "1.13.11",
            date: "July 6, 2026",
            highlights: [
                "See your dictated words, sessions, time saved, daily trends, and most-used apps in Usage Insights. These metrics stay on your Mac.",
                "Choose different transcript cleanup settings for different apps with Cleanup Groups."
            ]
        ),
        ReleaseNote(
            title: "1.13.10",
            date: "July 3, 2026",
            highlights: [
                "Explore the redesigned Foil Home and Vocabulary history views.",
                "Manage transcript cleanup through one simpler cleanup profile."
            ]
        ),
        ReleaseNote(
            title: "1.13.9",
            date: "June 28, 2026",
            highlights: [
                "Microphone setup now recovers when a macOS permission prompt gets stuck or times out.",
                "Recording shortcut changes take effect immediately, and the recording meter responds better to normal speech."
            ]
        ),
        ReleaseNote(
            title: "1.13.8",
            date: "June 26, 2026",
            highlights: [
                "See your installed version and check for updates from What's New.",
                "Cleanup connection checks now explain when a Groq or OpenAI API key is missing."
            ]
        ),
        ReleaseNote(
            title: "1.13.7",
            date: "June 25, 2026",
            highlights: [
                "Improved behind-the-scenes checks for future Apple Agent Kit support."
            ]
        ),
        ReleaseNote(
            title: "1.13.6",
            date: "June 25, 2026",
            highlights: [
                "Format dictated text with the new Cleanup settings tab, including an OpenAI cleanup option.",
                "See recording status and a live audio indicator while you dictate."
            ]
        ),
        ReleaseNote(
            title: "1.13.5",
            date: "June 12, 2026",
            highlights: [
                "Fixed in-app update verification so downloaded updates install reliably."
            ]
        )
    ]
}
