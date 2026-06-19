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
            "Clean up transcript formatting"
        case .rewriteClearly:
            "Rewrite clearly"
        }
    }

    var defaultPrompt: String {
        switch self {
        case .raw:
            ""
        case .cleanUp:
            """
            Clean up transcript formatting while preserving the speaker's meaning, facts, voice, and intent.
            Add punctuation and capitalization.
            Add paragraph breaks where they improve readability.
            Turn clearly enumerated spoken points into numbered or bulleted lists.
            Remove obvious filler and false starts only when doing so does not change meaning.
            Preserve names, numbers, technical terms, code-like strings, URLs, and intent.
            """
        case .rewriteClearly:
            "Rewrite the transcript into clear, concise prose. Preserve all concrete facts, names, numbers, and intent. Do not add new information."
        }
    }

    var promptInstruction: String {
        guard self != .raw else { return "" }
        return defaultPrompt + "\nReturn only the final processed transcript."
    }
}
