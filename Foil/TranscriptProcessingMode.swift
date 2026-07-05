import Foundation

enum TranscriptProcessingMode: String, CaseIterable, Codable, Identifiable {
    case raw
    case cleanUp
    case rewriteClearly
    case bulletize
    case numbered
    case summarize

    static var allCases: [TranscriptProcessingMode] {
        [.raw, .cleanUp]
    }

    var id: String { rawValue }

    var normalizedActiveMode: TranscriptProcessingMode {
        self == .raw ? .raw : .cleanUp
    }

    var displayName: String {
        switch self {
        case .raw:
            "Raw transcript"
        case .cleanUp, .rewriteClearly, .bulletize, .numbered, .summarize:
            "Cleanup profile"
        }
    }

    var activeModeDescription: String {
        switch self {
        case .raw:
            "Paste the transcript exactly as returned by transcription."
        case .cleanUp, .rewriteClearly, .bulletize, .numbered, .summarize:
            "Fix punctuation, capitalization, filler, stutters, false starts, paragraph breaks, and obvious list structure while preserving meaning."
        }
    }

    var usesCleanupProvider: Bool {
        self != .raw
    }

    var defaultPrompt: String {
        switch self {
        case .raw:
            ""
        case .cleanUp, .rewriteClearly, .bulletize, .numbered, .summarize:
            """
            Clean up the transcript while preserving the speaker's meaning, facts, voice, and intent.
            Correct punctuation and capitalization.
            Add paragraph breaks where they improve readability.
            Turn clearly enumerated spoken points into numbered or bulleted lists when that structure is obvious from the transcript.
            Remove obvious filler, stutters, repeated words, and false starts only when doing so does not change meaning.
            Preserve names, numbers, technical terms, code-like strings, URLs, and intent.
            """
        }
    }

    var promptInstruction: String {
        guard self != .raw else { return "" }
        return defaultPrompt + "\nReturn only the final processed transcript."
    }
}

enum HistoryTransformKind: String, CaseIterable, Codable, Identifiable {
    case polish
    case bulletize
    case summarize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .polish:
            "Polish"
        case .bulletize:
            "Bulletize"
        case .summarize:
            "Summarize"
        }
    }

    var systemImage: String {
        switch self {
        case .polish:
            "sparkles"
        case .bulletize:
            "list.bullet"
        case .summarize:
            "text.justify.left"
        }
    }

    var prompt: String {
        switch self {
        case .polish:
            """
            Polish this transcript into clear, natural writing.
            Preserve the speaker's meaning, facts, names, numbers, technical terms, and intent.
            Fix punctuation, capitalization, filler, and awkward phrasing only when doing so does not change meaning.
            """
        case .bulletize:
            """
            Convert this transcript into concise bullet points.
            Preserve every important fact, name, number, task, and decision.
            Group related ideas together and avoid adding information that was not in the transcript.
            """
        case .summarize:
            """
            Summarize this transcript briefly.
            Preserve the key facts, decisions, names, numbers, and next actions.
            Do not add information that was not in the transcript.
            """
        }
    }
}
