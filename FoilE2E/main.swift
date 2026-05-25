import Foundation

struct FoilE2EConfig {
    var audioPath = "Foil/e2e-test-audio.wav"
    var expected = "the quick brown fox jumps over the lazy dog"
    var maxMissingWords = 1
    var model = ProcessInfo.processInfo.environment["E2E_TRANSCRIPTION_MODEL"] ?? "whisper-large-v3-turbo"
    var provider = ProcessInfo.processInfo.environment["E2E_TRANSCRIPTION_PROVIDER"] ?? "groq"
    var baseURL = ProcessInfo.processInfo.environment["E2E_TRANSCRIPTION_BASE_URL"] ?? "https://api.groq.com/openai/v1"
    var apiKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"]
        ?? ProcessInfo.processInfo.environment["E2E_API_KEY"]
    var timeoutSeconds = TimeInterval(ProcessInfo.processInfo.environment["E2E_TRANSCRIPTION_TIMEOUT_SECONDS"] ?? "") ?? 90
}

enum FoilE2EError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)
    case invalidAudioPath(String)
    case invalidFormat(String)
    case missingAPIKey
    case invalidBaseURL(String)
    case timedOut(TimeInterval)
    case transcriptMismatch(transcript: String, missingWords: [String])

    var description: String {
        switch self {
        case .missingValue(let argument):
            "Missing value for \(argument)"
        case .unknownArgument(let argument):
            "Unknown argument: \(argument)"
        case .invalidAudioPath(let path):
            "Audio file does not exist: \(path)"
        case .invalidFormat(let path):
            "Unsupported audio format for file: \(path)"
        case .missingAPIKey:
            "GROQ_API_KEY or E2E_API_KEY is required"
        case .invalidBaseURL(let value):
            "Invalid E2E_TRANSCRIPTION_BASE_URL: \(value)"
        case .timedOut(let seconds):
            "Timed out after \(Int(seconds)) seconds"
        case .transcriptMismatch(let transcript, let missingWords):
            "Transcript '\(transcript)' missing words: \(missingWords.joined(separator: ", "))"
        }
    }
}

enum FoilE2E {
    static func main() async {
        do {
            let config = try parseConfig()
            let transcript = try await run(config: config)
            print("status=pass")
            print("transcript=\(transcript)")
        } catch {
            print("status=fail")
            print("error=\(error)")
            exit(1)
        }
    }

    private static func parseConfig() throws -> FoilE2EConfig {
        var config = FoilE2EConfig()
        var arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())

        while let argument = arguments.first {
            arguments.removeFirst()
            switch argument {
            case "--audio":
                guard let value = arguments.first else { throw FoilE2EError.missingValue(argument) }
                arguments.removeFirst()
                config.audioPath = value
            case "--expected":
                guard let value = arguments.first else { throw FoilE2EError.missingValue(argument) }
                arguments.removeFirst()
                config.expected = value
            case "--max-missing-words":
                guard let value = arguments.first else { throw FoilE2EError.missingValue(argument) }
                arguments.removeFirst()
                config.maxMissingWords = Int(value) ?? config.maxMissingWords
            case "--model":
                guard let value = arguments.first else { throw FoilE2EError.missingValue(argument) }
                arguments.removeFirst()
                config.model = value
            case "--timeout":
                guard let value = arguments.first else { throw FoilE2EError.missingValue(argument) }
                arguments.removeFirst()
                config.timeoutSeconds = TimeInterval(value) ?? config.timeoutSeconds
            default:
                throw FoilE2EError.unknownArgument(argument)
            }
        }

        return config
    }

    private static func run(config: FoilE2EConfig) async throws -> String {
        guard let apiKey = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw FoilE2EError.missingAPIKey
        }

        let audioURL = URL(fileURLWithPath: config.audioPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw FoilE2EError.invalidAudioPath(config.audioPath)
        }
        guard let format = AudioFormat(rawValue: audioURL.pathExtension.lowercased()) else {
            throw FoilE2EError.invalidFormat(config.audioPath)
        }

        let provider: TranscriptionProvider
        if config.provider == "openai-compatible" {
            guard let baseURL = URL(string: config.baseURL) else {
                throw FoilE2EError.invalidBaseURL(config.baseURL)
            }
            provider = .openAICompatible(baseURL: baseURL, model: config.model)
        } else {
            provider = .groq
        }

        let service = TranscriptionService(provider: provider)
        let transcript = try await withTimeout(seconds: config.timeoutSeconds) {
            try await service.transcribe(
                audioFileURL: audioURL,
                apiKey: apiKey,
                model: config.model,
                format: format,
                language: .en
            )
        }

        let missingWords = missingExpectedWords(expected: config.expected, transcript: transcript)
        guard missingWords.count <= config.maxMissingWords else {
            throw FoilE2EError.transcriptMismatch(transcript: transcript, missingWords: missingWords)
        }

        return transcript
    }

    private static func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw FoilE2EError.timedOut(seconds)
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    private static func missingExpectedWords(expected: String, transcript: String) -> [String] {
        let expectedWords = Set(words(in: expected))
        let transcriptWords = Set(words(in: transcript))
        return expectedWords.subtracting(transcriptWords).sorted()
    }

    private static func words(in text: String) -> [String] {
        String(text.lowercased().map { character in
            character.isLetter || character.isWhitespace ? character : " "
        })
        .split(separator: " ")
        .map(String.init)
    }
}

await FoilE2E.main()
