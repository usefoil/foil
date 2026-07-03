#!/usr/bin/env swift
//
// Cleanup profile quality smoke test.
//
// With no provider key, this script runs structural prompt/assertion checks only.
// Pass --require-live-provider to require a real Groq or OpenAI cleanup call.

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

enum CleanupProfile {
    static let displayName = "Cleanup profile"
    static let instruction = """
    Clean up the transcript while preserving the speaker's meaning, facts, voice, and intent.
    Correct punctuation and capitalization.
    Add paragraph breaks where they improve readability.
    Turn clearly enumerated spoken points into ordered or unordered lists when that structure is obvious from the transcript.
    Remove obvious filler, stutters, repeated words, and false starts only when doing so does not change meaning.
    Preserve names, numbers, technical terms, code-like strings, URLs, and intent.
    Return only the final processed transcript.
    """
}

enum CleanupProvider: String {
    case groq
    case openAI = "openai"

    var displayName: String {
        switch self {
        case .groq: "Groq"
        case .openAI: "OpenAI"
        }
    }
}

struct QualitySample {
    let name: String
    let transcript: String
    let requiredTerms: [String]
    let forbiddenTerms: [String]
    let requiresStructure: Bool
}

enum CleanupQualityTest {
    static let samples = [
        QualitySample(
            name: "filler-stutter",
            transcript: "um I I think tomorrow before the demo we should maybe test async paste in Chrome Terminal and TextEdit and then record a short video for Foil",
            requiredTerms: ["tomorrow", "demo", "async paste", "Chrome", "Terminal", "TextEdit", "video", "Foil"],
            forbiddenTerms: ["um", "i i"],
            requiresStructure: false
        ),
        QualitySample(
            name: "obvious-structure",
            transcript: "first confirm the launch checklist second assign follow ups for Chrome Terminal and TextEdit third record the Foil demo",
            requiredTerms: ["launch checklist", "follow up", "Chrome", "Terminal", "TextEdit", "Foil demo"],
            forbiddenTerms: [],
            requiresStructure: true
        )
    ]

    static func run() async -> Int32 {
        let requireLiveProvider = ProcessInfo.processInfo.arguments.contains("--require-live-provider")
        let groqKey = envKey("GROQ_API_KEY")
        let openAIKey = envKey("OPENAI_API_KEY")

        print("=== Cleanup Profile Quality Smoke Test ===")
        print("Profile: \(CleanupProfile.displayName)")
        print("Samples: \(samples.map(\.name).joined(separator: ", "))")
        print()

        guard runStructuralChecks() else {
            return 1
        }

        guard groqKey != nil || openAIKey != nil else {
            if requireLiveProvider {
                print("ERROR: Missing GROQ_API_KEY and OPENAI_API_KEY environment variables.")
                print("Live cleanup QA intentionally avoids legacy plaintext app key files.")
                return 1
            }

            print("SKIP: No provider key set; structural checks passed without live cleanup calls.")
            print("Run GROQ_API_KEY=... make test-cleanup-quality before release sign-off.")
            return 0
        }

        var failed = false
        if let groqKey {
            failed = await runGroq(apiKey: groqKey) || failed
        } else {
            print("SKIP: GROQ_API_KEY not set.")
            print()
        }

        if let openAIKey {
            failed = await runOpenAI(apiKey: openAIKey) || failed
        } else {
            print("SKIP: OPENAI_API_KEY not set.")
            print()
        }

        return failed ? 1 : 0
    }

    static func runStructuralChecks() -> Bool {
        var failed = false

        if CleanupProfile.displayName != "Cleanup profile" {
            print("FAIL: cleanup display name drifted.")
            failed = true
        }

        let instruction = CleanupProfile.instruction.lowercased()
        for term in ["filler", "stutters", "false starts", "preserve names", "return only"] {
            if !instruction.contains(term) {
                print("FAIL: cleanup instruction missing required term: \(term)")
                failed = true
            }
        }

        for sample in samples {
            if sample.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("FAIL: sample \(sample.name) is empty.")
                failed = true
            }
            if sample.requiredTerms.isEmpty {
                print("FAIL: sample \(sample.name) has no required terms.")
                failed = true
            }
        }

        if !failed {
            print("PASS: structural cleanup profile checks passed.")
            print()
        }
        return !failed
    }

    static func runGroq(apiKey: String) async -> Bool {
        let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        let model = ProcessInfo.processInfo.environment["GROQ_CLEANUP_QUALITY_MODEL"] ?? "llama-3.3-70b-versatile"

        return await runProviderChecks(provider: .groq) { transcript in
            try await processChat(endpoint: endpoint, apiKey: apiKey, model: model, transcript: transcript)
        }
    }

    static func runOpenAI(apiKey: String) async -> Bool {
        let endpoint = URL(string: "https://api.openai.com/v1/responses")!
        let model = ProcessInfo.processInfo.environment["OPENAI_CLEANUP_QUALITY_MODEL"] ?? "gpt-5.4-mini"

        return await runProviderChecks(provider: .openAI) { transcript in
            try await processResponses(endpoint: endpoint, apiKey: apiKey, model: model, transcript: transcript)
        }
    }

    static func runProviderChecks(
        provider: CleanupProvider,
        process: (String) async throws -> String
    ) async -> Bool {
        var failed = false
        for sample in samples {
            do {
                let output = try await process(sample.transcript)
                print("\(provider.displayName) \(CleanupProfile.displayName) \(sample.name):")
                print(output)
                print()

                if !validates(output: output, sample: sample) {
                    failed = true
                    print("FAIL: \(provider.displayName) \(sample.name) failed cleanup profile quality checks.")
                } else {
                    print("PASS: \(provider.displayName) \(sample.name) preserved facts and cleaned transcript shape.")
                }
                print()
            } catch {
                failed = true
                print("FAIL: \(provider.displayName) \(sample.name) failed: \(error)")
                print()
            }
        }
        return failed
    }

    static func processChat(
        endpoint: URL,
        apiKey: String,
        model: String,
        transcript: String
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "CleanupQualityTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        guard http.statusCode == 200 else {
            throw httpError(statusCode: http.statusCode, data: data)
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func processResponses(
        endpoint: URL,
        apiKey: String,
        model: String,
        transcript: String
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "CleanupQualityTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        guard http.statusCode == 200 else {
            throw httpError(statusCode: http.statusCode, data: data)
        }
        let decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        return decoded.resolvedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func validates(output: String, sample: QualitySample) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard preservesRequiredTerms(trimmed, requiredTerms: sample.requiredTerms) else { return false }
        guard omitsForbiddenTerms(trimmed, forbiddenTerms: sample.forbiddenTerms) else { return false }
        if sample.requiresStructure && !hasUsefulStructure(trimmed) {
            return false
        }
        return trimmed.count <= max(sample.transcript.count * 2, 80)
    }

    static func preservesRequiredTerms(_ text: String, requiredTerms: [String]) -> Bool {
        let normalized = normalize(text)
        return requiredTerms.allSatisfy { term in
            normalized.contains(normalize(term))
        }
    }

    static func omitsForbiddenTerms(_ text: String, forbiddenTerms: [String]) -> Bool {
        let normalized = " \(normalize(text)) "
        return forbiddenTerms.allSatisfy { term in
            !normalized.contains(" \(normalize(term)) ")
        }
    }

    static func hasUsefulStructure(_ text: String) -> Bool {
        let lines = meaningfulLines(text)
        guard lines.count >= 2 else { return false }
        return lines.contains { line in
            line.hasPrefix("- ")
                || line.hasPrefix("* ")
                || line.range(of: #"^\d+[\.)]\s+"#, options: .regularExpression) != nil
        }
    }

    static func meaningfulLines(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalize(_ text: String) -> String {
        String(text.lowercased().map { character in
            character.isLetter || character.isNumber || character.isWhitespace ? character : " "
        })
        .split(separator: " ")
        .joined(separator: " ")
    }

    static func envKey(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    static func httpError(statusCode: Int, data: Data) -> NSError {
        let body = String(data: data, encoding: .utf8) ?? ""
        return NSError(
            domain: "CleanupQualityTest",
            code: statusCode,
            userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode): \(body.prefix(240))"]
        )
    }
}

Task {
    let code = await CleanupQualityTest.run()
    exit(code)
}

dispatchMain()
