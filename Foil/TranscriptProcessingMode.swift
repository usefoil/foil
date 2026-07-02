import Foundation

enum TranscriptProcessingMode: String, CaseIterable, Identifiable {
    case raw
    case cleanUp
    case rewriteClearly
    case bulletize
    case numbered
    case summarize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw:
            "Raw transcript"
        case .cleanUp:
            "Clean up transcript formatting"
        case .rewriteClearly:
            "Rewrite clearly"
        case .bulletize:
            "Bullets"
        case .numbered:
            "Numbered list"
        case .summarize:
            "Summary"
        }
    }

    var activeModeDescription: String {
        switch self {
        case .raw:
            "Paste the transcript exactly as returned by transcription."
        case .cleanUp:
            "Fix punctuation, capitalization, filler, and paragraph breaks while preserving the wording."
        case .rewriteClearly:
            "Rewrite the transcript into concise prose."
        case .bulletize:
            "Paste the transcript as concise bullet points."
        case .numbered:
            "Paste the transcript as a numbered list."
        case .summarize:
            "Paste a short summary of the transcript."
        }
    }

    var usesCleanupProvider: Bool {
        self != .raw
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
        case .bulletize:
            """
            Convert the transcript into concise bullet points.
            Preserve every important fact, name, number, task, decision, and next action.
            Use one bullet per important idea.
            Start every bullet line with "- ".
            Do not add information that was not in the transcript.
            """
        case .numbered:
            """
            Convert the transcript into a concise numbered list.
            Preserve every important fact, name, number, task, decision, and next action.
            Use one numbered item per important idea.
            Start each item with "1. ", "2. ", "3. ", and so on.
            Do not add information that was not in the transcript.
            """
        case .summarize:
            """
            Summarize the transcript briefly as one short paragraph.
            Preserve the key facts, decisions, names, numbers, and next actions.
            Keep the summary concise and readable.
            Do not use bullet points, numbered lists, headings, or labels.
            Do not add information that was not in the transcript.
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
