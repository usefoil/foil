#!/usr/bin/env swift

import Foundation

struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxCompletionTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
    }
}

struct Message: Encodable, Decodable {
    let role: String
    let content: String
}

struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }
}

struct ResponsesRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let maxOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case maxOutputTokens = "max_output_tokens"
    }
}

struct ResponsesResponse: Decodable {
    let outputText: String?
    let output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var resolvedText: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }
        return output?
            .compactMap { item in
                item.content?
                    .compactMap(\.text)
                    .joined(separator: "\n")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    struct OutputItem: Decodable {
        let content: [Content]?
    }

    struct Content: Decodable {
        let text: String?
    }
}

struct Fixture: Codable {
    let id: String
    let sourceText: String
    let expectedTranscriptionText: String
    let dryRunCleanedText: String
    let requiredTerms: [String]
    let forbiddenTerms: [String]
    let requiresStructure: Bool
}

struct AssertionResult: Codable {
    let name: String
    let passed: Bool
    let detail: String
}

struct FixtureArtifact: Codable {
    let fixtureID: String
    let sourceText: String
    let audioPath: String
    let rawTranscript: String
    let cleanedTranscript: String
    let transcriptionProvider: String
    let transcriptionModel: String
    let cleanupProvider: String
    let cleanupModel: String
    let assertions: [AssertionResult]
    let status: String
}

enum HarnessError: Error, CustomStringConvertible {
    case commandFailed(String, Int32, String)
    case missingAudioTool(String)
    case missingProviderKey(String)
    case invalidWAV(String)
    case missingTranscript(String)
    case invalidResponse(String)
    case timedOut(String, TimeInterval)

    var description: String {
        switch self {
        case .commandFailed(let command, let status, let output):
            "\(command) failed with status \(status): \(output)"
        case .missingAudioTool(let tool):
            "Missing required audio tool: \(tool)"
        case .missingProviderKey(let provider):
            "Missing API key for \(provider)"
        case .invalidWAV(let path):
            "Generated file is not a RIFF/WAVE file: \(path)"
        case .missingTranscript(let path):
            "Could not find transcript in output: \(path)"
        case .invalidResponse(let message):
            message
        case .timedOut(let operation, let seconds):
            "\(operation) timed out after \(Int(seconds)) seconds"
        }
    }
}

enum CleanupProfile {
    static let instruction = """
    Clean up the transcript while preserving the speaker's meaning, facts, voice, and intent.
    Correct punctuation and capitalization.
    Add paragraph breaks where they improve readability.
    Turn clearly enumerated spoken points into ordered or unordered lists when that structure is obvious from the transcript.
    Remove obvious filler, stutters, repeated words, and false starts only when doing so does not change meaning.
    Keep the result concise; do not add introductions, explanations, commentary, inferred background, or extra details.
    Preserve names, numbers, technical terms, code-like strings, URLs, and intent.
    Use these preferred terms when the transcript contains a clear near miss: async paste, TextEdit, Foil, Supabase, LaunchDarkly, Chrome, Terminal.
    Apply these vocabulary corrections when context supports them: "a sync-pasted", "a sync paste", or "sync pasted" means "async paste"; "text edit" means "TextEdit"; "foil" means "Foil".
    Return only the final processed transcript.
    """
}

enum LiveAudioCleanupQuality {
    static let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let defaultArtifactDir = root.appendingPathComponent("tests/fixtures/audio-cleanup-quality/generated", isDirectory: true)
    static let fixtures = [
        Fixture(
            id: "filler-stutter",
            sourceText: "um I I think tomorrow before the demo we should maybe test async paste in Chrome Terminal and TextEdit and then record a short video for Foil",
            expectedTranscriptionText: "tomorrow demo Chrome Terminal video Foil",
            dryRunCleanedText: "Tomorrow before the demo, we should test async paste in Chrome, Terminal, and TextEdit, then record a short video for Foil.",
            requiredTerms: ["tomorrow", "demo", "async paste", "Chrome", "Terminal", "TextEdit", "video", "Foil"],
            forbiddenTerms: ["um", "i i"],
            requiresStructure: false
        ),
        Fixture(
            id: "false-start",
            sourceText: "send the recap to Sarah no sorry send it to Priya and include the launch checklist by Friday",
            expectedTranscriptionText: "recap Priya launch checklist Friday",
            dryRunCleanedText: "Send the recap to Priya and include the launch checklist by Friday.",
            requiredTerms: ["recap", "Priya", "launch checklist", "Friday"],
            forbiddenTerms: ["Sarah"],
            requiresStructure: false
        ),
        Fixture(
            id: "obvious-structure",
            sourceText: "first confirm the launch checklist second assign follow ups for Chrome Terminal and TextEdit third record the Foil demo",
            expectedTranscriptionText: "launch checklist follow ups Chrome Terminal Foil demo",
            dryRunCleanedText: """
            1. Confirm the launch checklist.
            2. Assign follow-ups for Chrome, Terminal, and TextEdit.
            3. Record the Foil demo.
            """,
            requiredTerms: ["launch checklist", "follow up", "Chrome", "Terminal", "TextEdit", "Foil demo"],
            forbiddenTerms: [],
            requiresStructure: true
        ),
        Fixture(
            id: "vocabulary",
            sourceText: "for the Foil cleanup demo mention Supabase LaunchDarkly TextEdit Chrome and Terminal and keep the URL example dot com slash launch",
            expectedTranscriptionText: "Foil cleanup demo Chrome Terminal",
            dryRunCleanedText: "For the Foil cleanup demo, mention Supabase, LaunchDarkly, TextEdit, Chrome, and Terminal, and keep the URL example.com/launch.",
            requiredTerms: ["Foil", "cleanup demo", "Supabase", "LaunchDarkly", "TextEdit", "Chrome", "Terminal"],
            forbiddenTerms: [],
            requiresStructure: false
        )
    ]

    static func main() async -> Int32 {
        do {
            let args = Set(ProcessInfo.processInfo.arguments.dropFirst())
            let artifactDir = artifactDirectory()
            try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

            let voice = try selectedVoice()
            let audioPaths = try generateFixtures(voice: voice, artifactDir: artifactDir)
            try writeManifest(voice: voice, audioPaths: audioPaths, artifactDir: artifactDir)

            if args.contains("--generate-fixtures-only") {
                print("status=pass")
                print("mode=generate-fixtures-only")
                print("voice=\(voice)")
                print("artifact_dir=\(artifactDir.path)")
                return 0
            }

            if args.contains("--dry-run") {
                try runDryRun(audioPaths: audioPaths, artifactDir: artifactDir)
                print("status=pass")
                print("mode=dry-run")
                print("artifact_dir=\(artifactDir.path)")
                return 0
            }

            try await runLive(audioPaths: audioPaths, artifactDir: artifactDir)
            print("status=pass")
            print("mode=live")
            print("artifact_dir=\(artifactDir.path)")
            return 0
        } catch {
            print("status=fail")
            print("error=\(error)")
            return 1
        }
    }

    static func artifactDirectory() -> URL {
        if let value = ProcessInfo.processInfo.environment["E2E_ARTIFACT_DIR"], !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return defaultArtifactDir
    }

    static func selectedVoice() throws -> String {
        if let override = ProcessInfo.processInfo.environment["E2E_APPLE_VOICE"], !override.isEmpty {
            return override
        }

        let voices = try runProcess("/usr/bin/say", ["-v", "?"]).output
            .split(separator: "\n")
            .map(String.init)

        let preferred = ["Eddy (English (US))", "Samantha", "Alex", "Ava", "Nicky", "Albert"]
        for candidate in preferred where voices.contains(where: { $0.hasPrefix(candidate + " ") }) {
            return candidate
        }

        if let firstUSVoice = voices.compactMap(usEnglishVoiceName(from:)).first {
            return firstUSVoice
        }
        return "Alex"
    }

    static func usEnglishVoiceName(from line: String) -> String? {
        guard let range = line.range(of: " en_US ") else { return nil }
        return String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    static func generateFixtures(voice: String, artifactDir: URL) throws -> [String: URL] {
        try ensureExecutable("/usr/bin/say")
        try ensureExecutable("/usr/bin/afconvert")

        let audioDir = artifactDir.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        var paths: [String: URL] = [:]
        for fixture in fixtures {
            let aiff = audioDir.appendingPathComponent("\(fixture.id).aiff")
            let wav = audioDir.appendingPathComponent("\(fixture.id).wav")
            _ = try runProcess("/usr/bin/say", ["-v", voice, "-o", aiff.path, fixture.sourceText])
            _ = try runProcess("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", aiff.path, wav.path])
            try validateWAV(wav)
            paths[fixture.id] = wav
        }
        return paths
    }

    static func writeManifest(voice: String, audioPaths: [String: URL], artifactDir: URL) throws {
        let manifest = fixtures.map { fixture in
            [
                "id": fixture.id,
                "voice": voice,
                "source_text": fixture.sourceText,
                "audio_path": audioPaths[fixture.id]?.path ?? ""
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: artifactDir.appendingPathComponent("manifest.json"))
    }

    static func runDryRun(audioPaths: [String: URL], artifactDir: URL) throws {
        for fixture in fixtures {
            guard let audioPath = audioPaths[fixture.id] else {
                throw HarnessError.invalidWAV(fixture.id)
            }
            let assertions = assertionsFor(cleaned: fixture.dryRunCleanedText, raw: fixture.sourceText, fixture: fixture)
            let artifact = FixtureArtifact(
                fixtureID: fixture.id,
                sourceText: fixture.sourceText,
                audioPath: audioPath.path,
                rawTranscript: fixture.sourceText,
                cleanedTranscript: fixture.dryRunCleanedText,
                transcriptionProvider: "dry-run",
                transcriptionModel: "dry-run",
                cleanupProvider: "dry-run",
                cleanupModel: "dry-run",
                assertions: assertions,
                status: assertions.allSatisfy(\.passed) ? "pass" : "fail"
            )
            try writeArtifact(artifact, artifactDir: artifactDir)
            guard artifact.status == "pass" else {
                throw HarnessError.invalidResponse("Dry-run assertions failed for \(fixture.id)")
            }
        }
    }

    static func runLive(audioPaths: [String: URL], artifactDir: URL) async throws {
        for fixture in fixtures {
            guard let audioPath = audioPaths[fixture.id] else {
                throw HarnessError.invalidWAV(fixture.id)
            }

            let rawTranscript = try transcribe(fixture: fixture, audioPath: audioPath, artifactDir: artifactDir)
            let cleanup = try await withTimeout(seconds: cleanupTimeoutSeconds(), operation: "cleanup \(fixture.id)") {
                try await cleanupTranscript(rawTranscript)
            }
            let assertions = assertionsFor(cleaned: cleanup.text, raw: rawTranscript, fixture: fixture)
            let artifact = FixtureArtifact(
                fixtureID: fixture.id,
                sourceText: fixture.sourceText,
                audioPath: audioPath.path,
                rawTranscript: rawTranscript,
                cleanedTranscript: cleanup.text,
                transcriptionProvider: transcriptionProvider(),
                transcriptionModel: transcriptionModel(),
                cleanupProvider: cleanup.provider,
                cleanupModel: cleanup.model,
                assertions: assertions,
                status: assertions.allSatisfy(\.passed) ? "pass" : "fail"
            )
            try writeArtifact(artifact, artifactDir: artifactDir)
            guard artifact.status == "pass" else {
                throw HarnessError.invalidResponse("Live assertions failed for \(fixture.id)")
            }
        }
    }

    static func transcribe(fixture: Fixture, audioPath: URL, artifactDir: URL) throws -> String {
        let outputPath = artifactDir.appendingPathComponent("\(fixture.id)-transcription.txt")
        var env = ProcessInfo.processInfo.environment
        env["E2E_WAV_PATH"] = audioPath.path
        env["E2E_EXPECTED_TEXT"] = fixture.expectedTranscriptionText
        env["E2E_OUTPUT_PATH"] = outputPath.path

        let result = try runProcess("/usr/bin/env", ["bash", "scripts/run-live-transcription-e2e-cli.sh"], environment: env)
        try result.output.write(to: outputPath, atomically: true, encoding: .utf8)

        let lines = result.output.split(separator: "\n").map(String.init)
        guard let transcriptLine = lines.last(where: { $0.hasPrefix("transcript=") }) else {
            throw HarnessError.missingTranscript(outputPath.path)
        }
        return String(transcriptLine.dropFirst("transcript=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanupTranscript(_ transcript: String) async throws -> (text: String, provider: String, model: String) {
        let provider = cleanupProvider()
        switch provider {
        case "openai":
            let apiKey = try apiKey(primary: "E2E_CLEANUP_API_KEY", fallback: "OPENAI_API_KEY", provider: provider)
            let model = cleanupModel(defaultValue: "gpt-5.4-mini")
            let text = try await processResponses(endpoint: URL(string: "https://api.openai.com/v1/responses")!, apiKey: apiKey, model: model, transcript: transcript)
            return (text, provider, model)
        default:
            let apiKey = try apiKey(primary: "E2E_CLEANUP_API_KEY", fallback: "GROQ_API_KEY", provider: provider)
            let model = cleanupModel(defaultValue: "llama-3.3-70b-versatile")
            let text = try await processChat(endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!, apiKey: apiKey, model: model, transcript: transcript)
            return (text, "groq", model)
        }
    }

    static func cleanupProvider() -> String {
        let env = ProcessInfo.processInfo.environment
        if let value = env["E2E_CLEANUP_PROVIDER"], !value.isEmpty {
            return value.lowercased()
        }
        if env["OPENAI_API_KEY"]?.isEmpty == false {
            return "openai"
        }
        if env["GROQ_API_KEY"]?.isEmpty == false || env["E2E_API_KEY"]?.isEmpty == false {
            return "groq"
        }
        return "groq"
    }

    static func cleanupModel(defaultValue: String) -> String {
        let env = ProcessInfo.processInfo.environment
        return env["E2E_CLEANUP_MODEL"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultValue
    }

    static func transcriptionProvider() -> String {
        ProcessInfo.processInfo.environment["E2E_TRANSCRIPTION_PROVIDER"].flatMap { $0.isEmpty ? nil : $0 } ?? "groq"
    }

    static func transcriptionModel() -> String {
        ProcessInfo.processInfo.environment["E2E_TRANSCRIPTION_MODEL"].flatMap { $0.isEmpty ? nil : $0 } ?? "whisper-large-v3-turbo"
    }

    static func apiKey(primary: String, fallback: String, provider: String) throws -> String {
        let env = ProcessInfo.processInfo.environment
        if let value = env[primary], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        if let value = env[fallback], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        if let value = env["E2E_API_KEY"], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        throw HarnessError.missingProviderKey(provider)
    }

    static func processChat(endpoint: URL, apiKey: String, model: String, transcript: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = cleanupTimeoutSeconds()
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    Message(role: "system", content: CleanupProfile.instruction),
                    Message(role: "user", content: transcript)
                ],
                temperature: 0.2,
                maxCompletionTokens: 1024
            )
        )

        let (data, response) = try performRequest(request, operation: "Groq cleanup")
        guard let http = response as? HTTPURLResponse else {
            throw HarnessError.invalidResponse("Cleanup response was not HTTP")
        }
        guard http.statusCode == 200 else {
            throw HarnessError.invalidResponse("Cleanup HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw HarnessError.invalidResponse("Cleanup response was empty")
        }
        return text
    }

    static func processResponses(endpoint: URL, apiKey: String, model: String, transcript: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = cleanupTimeoutSeconds()
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ResponsesRequest(
                model: model,
                instructions: CleanupProfile.instruction,
                input: transcript,
                maxOutputTokens: 1024
            )
        )

        let (data, response) = try performRequest(request, operation: "OpenAI cleanup")
        guard let http = response as? HTTPURLResponse else {
            throw HarnessError.invalidResponse("Cleanup response was not HTTP")
        }
        guard http.statusCode == 200 else {
            throw HarnessError.invalidResponse("Cleanup HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
        let decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        guard let text = decoded.resolvedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw HarnessError.invalidResponse("Cleanup response was empty")
        }
        return text
    }

    static func assertionsFor(cleaned: String, raw: String, fixture: Fixture) -> [AssertionResult] {
        [
            AssertionResult(
                name: "non_empty",
                passed: !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                detail: "cleanedLength=\(cleaned.count)"
            ),
            AssertionResult(
                name: "required_terms",
                passed: fixture.requiredTerms.allSatisfy { normalize(cleaned).contains(normalize($0)) },
                detail: "required=\(fixture.requiredTerms.joined(separator: ","))"
            ),
            AssertionResult(
                name: "forbidden_terms_removed",
                passed: fixture.forbiddenTerms.allSatisfy { !containsWholeTerm(cleaned, term: $0) },
                detail: "forbidden=\(fixture.forbiddenTerms.joined(separator: ","))"
            ),
            AssertionResult(
                name: "structure_when_obvious",
                passed: !fixture.requiresStructure || hasUsefulStructure(cleaned),
                detail: "requiresStructure=\(fixture.requiresStructure)"
            ),
            AssertionResult(
                name: "not_overexpanded",
                passed: cleaned.count <= max(raw.count * 2, 120),
                detail: "rawLength=\(raw.count) cleanedLength=\(cleaned.count)"
            )
        ]
    }

    static func cleanupTimeoutSeconds() -> TimeInterval {
        let value = ProcessInfo.processInfo.environment["E2E_CLEANUP_TIMEOUT_SECONDS"] ?? ""
        return TimeInterval(value) ?? 90
    }

    static func performRequest(_ request: URLRequest, operation: String) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<(Data, URLResponse), Error>?
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            lock.lock()
            defer {
                lock.unlock()
                semaphore.signal()
            }
            if let error {
                result = .failure(error)
                return
            }
            guard let data, let response else {
                result = .failure(HarnessError.invalidResponse("\(operation) returned no data"))
                return
            }
            result = .success((data, response))
        }

        task.resume()
        let timeout = cleanupTimeoutSeconds()
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            task.cancel()
            throw HarnessError.timedOut(operation, timeout)
        }

        lock.lock()
        let completed = result
        lock.unlock()

        switch completed {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case nil:
            throw HarnessError.invalidResponse("\(operation) completed without a result")
        }
    }

    static func withTimeout<T>(
        seconds: TimeInterval,
        operation: String,
        work: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await work()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw HarnessError.timedOut(operation, seconds)
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    static func containsWholeTerm(_ text: String, term: String) -> Bool {
        " \(normalize(text)) ".contains(" \(normalize(term)) ")
    }

    static func hasUsefulStructure(_ text: String) -> Bool {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count >= 2, lines.contains(where: { line in
            line.hasPrefix("- ")
                || line.hasPrefix("* ")
                || line.range(of: #"^\d+[\.)]\s+"#, options: .regularExpression) != nil
                || line.range(of: #"(?i)^(first|second|third|fourth|finally)[,:]?\s+"#, options: .regularExpression) != nil
        }) {
            return true
        }

        let pattern = #"(?i)\b(first|second|third|fourth|finally)[,:]?\s+"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return (regex?.numberOfMatches(in: text, range: range) ?? 0) >= 2
    }

    static func normalize(_ text: String) -> String {
        String(text.lowercased().map { character in
            character.isLetter || character.isNumber || character.isWhitespace ? character : " "
        })
        .split(separator: " ")
        .joined(separator: " ")
    }

    static func writeArtifact(_ artifact: FixtureArtifact, artifactDir: URL) throws {
        let artifactPath = artifactDir.appendingPathComponent("\(artifact.fixtureID)-artifact.json")
        let data = try JSONEncoder.pretty.encode(artifact)
        try data.write(to: artifactPath)
    }

    static func validateWAV(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count > 12,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            throw HarnessError.invalidWAV(url.path)
        }
    }

    static func ensureExecutable(_ path: String) throws {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw HarnessError.missingAudioTool(path)
        }
    }

    static func runProcess(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String]? = nil
    ) throws -> (status: Int32, output: String) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-live-audio-cleanup-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        process.standardOutput = outputHandle
        process.standardError = outputHandle
        try process.run()
        process.waitUntilExit()

        try outputHandle.synchronize()
        let data = try Data(contentsOf: outputURL)
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw HarnessError.commandFailed(([executable] + arguments).joined(separator: " "), process.terminationStatus, output)
        }
        return (process.terminationStatus, output)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

Task {
    let status = await LiveAudioCleanupQuality.main()
    exit(status)
}

dispatchMain()
