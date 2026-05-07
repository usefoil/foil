import Foundation

enum TranscriptProcessingMode: String, CaseIterable, Identifiable {
    case raw
    case cleanUp
    case rewriteClearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw:
            "Raw transcript"
        case .cleanUp:
            "Clean up"
        case .rewriteClearly:
            "Rewrite clearly"
        }
    }

    var promptInstruction: String {
        switch self {
        case .raw:
            ""
        case .cleanUp:
            "Clean up the transcript lightly. Fix obvious speech recognition errors, punctuation, capitalization, and filler words. Preserve the speaker's meaning and wording as much as possible. Return only the cleaned text."
        case .rewriteClearly:
            "Rewrite the transcript into clear, concise prose. Preserve all concrete facts, names, numbers, and intent. Do not add new information. Return only the rewritten text."
        }
    }
}
