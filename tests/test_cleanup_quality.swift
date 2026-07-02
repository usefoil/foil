#!/usr/bin/env swift
//
// Real cleanup-quality smoke test.
//
// Reads GROQ_API_KEY and/or OPENAI_API_KEY, then runs short active cleanup mode
// prompts against fixed samples. Prints model outputs, never keys.

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

enum CleanupMode: String, CaseIterable {
    case cleanUp
    case rewriteClearly
    case bulletize
    case numbered
    case summarize

    var displayName: String {
        switch self {
        case .cleanUp: "Clean up"
        case .rewriteClearly: "Rewrite clearly"
        case .bulletize: "Bullets"
        case .numbered: "Numbered list"
        case .summarize: "Summary"
        }
    }

    var instruction: String {
        switch self {
        case .cleanUp:
            """
            Clean up transcript formatting while preserving the speaker's meaning, facts, voice, and intent.
            Add punctuation and capitalization.
            Add paragraph breaks where they improve readability.
            Turn clearly enumerated spoken points into numbered or bulleted lists.
            Remove obvious filler and false starts only when doing so does not change meaning.
            Preserve names, numbers, technical terms, code-like strings, URLs, and intent.
            Return only the final processed transcript.
            """
        case .rewriteClearly:
            "Rewrite the transcript into clear, concise prose. Preserve all concrete facts, names, numbers, and intent. Do not add new information. Return only the rewritten text."
        case .bulletize:
            """
            Convert the transcript into concise bullet points.
            Preserve every important fact, name, number, task, decision, and next action.
            Use one bullet per important idea.
            Start every bullet line with "- ".
            Do not add information that was not in the transcript.
            Return only the final processed transcript.
            """
        case .numbered:
            """
            Convert the transcript into a concise numbered list.
            Preserve every important fact, name, number, task, decision, and next action.
            Use one numbered item per important idea.
            Start each item with "1. ", "2. ", "3. ", and so on.
            Do not add information that was not in the transcript.
            Return only the final processed transcript.
            """
        case .summarize:
            """
            Summarize the transcript briefly as one short paragraph.
            Preserve the key facts, decisions, names, numbers, and next actions.
            Keep the summary concise and readable.
            Do not use bullet points, numbered lists, headings, or labels.
            Do not add information that was not in the transcript.
            Return only the final processed transcript.
            """
        }
    }
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

enum CleanupQualityTest {
    static let activeModeSample = "first confirm the launch checklist then assign follow ups for chrome terminal and textedit before the foil demo"
    static let cleanupSample = "um so i think tomorrow before the demo we should maybe test async paste in chrome terminal and textedit and then record a short video for foil"
    static let historyBulletizeInstruction = CleanupMode.bulletize.instruction
    static let customPromptInstruction = """
    Return exactly two non-empty lines and nothing else.
    Line 1 must start with CUSTOM-1: and mention the launch checklist.
    Line 2 must start with CUSTOM-2: and mention Chrome, Terminal, TextEdit, and the Foil demo.
    Do not use bullets, numbering, headings, explanations, or extra lines.
    """

    static func run() async -> Int32 {
        let groqKey = envKey("GROQ_API_KEY")
        let openAIKey = envKey("OPENAI_API_KEY")

        guard groqKey != nil || openAIKey != nil else {
            print("ERROR: Missing GROQ_API_KEY and OPENAI_API_KEY environment variables.")
            print("This live QA check intentionally avoids legacy plaintext app key files.")
            return 1
        }

        print("=== Cleanup Quality Smoke Test ===")
        print("Raw active-mode sample:")
        print(activeModeSample)
        print()

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

    static func runGroq(apiKey: String) async -> Bool {
        let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        let model = "llama-3.3-70b-versatile"
        var failed = false

        failed = await runActiveModeChecks(
            provider: .groq,
            process: { mode, transcript in
                try await processChat(endpoint: endpoint, apiKey: apiKey, model: model, mode: mode, transcript: transcript)
            }
        ) || failed

        failed = await runHistoryBulletizeCheck(provider: .groq) { transcript in
            try await processChat(
                endpoint: endpoint,
                apiKey: apiKey,
                model: model,
                instruction: historyBulletizeInstruction,
                transcript: transcript
            )
        } || failed

        failed = await runCustomPromptCheck(provider: .groq) { transcript in
            try await processChat(
                endpoint: endpoint,
                apiKey: apiKey,
                model: model,
                instruction: customPromptInstruction,
                transcript: transcript
            )
        } || failed

        return failed
    }

    static func runOpenAI(apiKey: String) async -> Bool {
        let endpoint = URL(string: "https://api.openai.com/v1/responses")!
        let model = ProcessInfo.processInfo.environment["OPENAI_CLEANUP_QUALITY_MODEL"] ?? "gpt-5.4-mini"

        var failed = false
        failed = await runActiveModeChecks(
            provider: .openAI,
            process: { mode, transcript in
                try await processResponses(endpoint: endpoint, apiKey: apiKey, model: model, mode: mode, transcript: transcript)
            }
        ) || failed

        failed = await runCustomPromptCheck(provider: .openAI) { transcript in
            try await processResponses(
                endpoint: endpoint,
                apiKey: apiKey,
                model: model,
                instruction: customPromptInstruction,
                transcript: transcript
            )
        } || failed

        return failed
    }

    static func runActiveModeChecks(
        provider: CleanupProvider,
        process: (CleanupMode, String) async throws -> String
    ) async -> Bool {
        var failed = false
        for mode in [CleanupMode.bulletize, .numbered, .summarize] {
            do {
                let output = try await process(mode, activeModeSample)
                print("\(provider.displayName) \(mode.displayName):")
                print(output)
                print()

                if !validates(output: output, for: mode) {
                    failed = true
                    print("FAIL: \(provider.displayName) \(mode.displayName) failed structure or fact-preservation check.")
                } else {
                    print("PASS: \(provider.displayName) \(mode.displayName) preserved core facts with expected structure.")
                }
                print()
            } catch {
                failed = true
                print("FAIL: \(provider.displayName) \(mode.displayName) failed: \(error)")
                print()
            }
        }
        return failed
    }

    static func runHistoryBulletizeCheck(
        provider: CleanupProvider,
        process: (String) async throws -> String
    ) async -> Bool {
        do {
            let output = try await process(activeModeSample)
            print("\(provider.displayName) History Bulletize:")
            print(output)
            print()

            if !validates(output: output, for: .bulletize) {
                print("FAIL: \(provider.displayName) History Bulletize failed list-format or fact-preservation check.")
                return true
            }
            print("PASS: \(provider.displayName) History Bulletize returned list format and preserved core facts.")
            print()
            return false
        } catch {
            print("FAIL: \(provider.displayName) History Bulletize failed: \(error)")
            print()
            return true
        }
    }

    static func runCustomPromptCheck(
        provider: CleanupProvider,
        process: (String) async throws -> String
    ) async -> Bool {
        do {
            let output = try await process(activeModeSample)
            print("\(provider.displayName) Custom Prompt:")
            print(output)
            print()

            if !validatesCustomPromptOutput(output) {
                print("FAIL: \(provider.displayName) Custom Prompt did not follow the requested custom line markers.")
                return true
            }
            print("PASS: \(provider.displayName) Custom Prompt followed requested custom markers and preserved core facts.")
            print()
            return false
        } catch {
            print("FAIL: \(provider.displayName) Custom Prompt failed: \(error)")
            print()
            return true
        }
    }

    static func processChat(
        endpoint: URL,
        apiKey: String,
        model: String,
        mode: CleanupMode,
        transcript: String
    ) async throws -> String {
        try await processChat(endpoint: endpoint, apiKey: apiKey, model: model, instruction: mode.instruction, transcript: transcript)
    }

    static func processChat(
        endpoint: URL,
        apiKey: String,
        model: String,
        instruction: String,
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
                    Message(role: "system", content: instruction),
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
        mode: CleanupMode,
        transcript: String
    ) async throws -> String {
        try await processResponses(endpoint: endpoint, apiKey: apiKey, model: model, instruction: mode.instruction, transcript: transcript)
    }

    static func processResponses(
        endpoint: URL,
        apiKey: String,
        model: String,
        instruction: String,
        transcript: String
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ResponsesRequest(
                model: model,
                instructions: instruction,
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

    static func validatesCustomPromptOutput(_ output: String) -> Bool {
        let lines = meaningfulLines(output)
        guard lines.count == 2 else { return false }
        let first = lines[0].lowercased()
        let second = lines[1].lowercased()
        return first.hasPrefix("custom-1:")
            && first.contains("launch checklist")
            && second.hasPrefix("custom-2:")
            && second.contains("chrome")
            && second.contains("terminal")
            && second.contains("textedit")
            && second.contains("foil demo")
    }

    static func validates(output: String, for mode: CleanupMode) -> Bool {
        guard preservesCoreFacts(output) else { return false }
        switch mode {
        case .bulletize:
            return hasBulletFormat(output)
        case .numbered:
            return hasNumberedFormat(output)
        case .summarize:
            return !output.isEmpty
                && output.split(whereSeparator: \.isNewline).count <= 3
                && !containsListMarker(output)
        case .cleanUp, .rewriteClearly:
            return !output.isEmpty
        }
    }

    static func preservesCoreFacts(_ text: String) -> Bool {
        let lower = text
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
        return lower.contains("launch checklist")
            && (lower.contains("follow up") || lower.contains("follow ups"))
            && lower.contains("chrome")
            && lower.contains("terminal")
            && lower.contains("textedit")
            && lower.contains("foil demo")
    }

    static func hasBulletFormat(_ text: String) -> Bool {
        let lines = meaningfulLines(text)
        guard lines.count >= 2 else { return false }
        return lines.allSatisfy { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
    }

    static func hasNumberedFormat(_ text: String) -> Bool {
        let lines = meaningfulLines(text)
        guard lines.count >= 2 else { return false }
        return lines.allSatisfy { line in
            line.range(of: #"^\d+[\.)]\s+"#, options: .regularExpression) != nil
        }
    }

    static func containsListMarker(_ text: String) -> Bool {
        meaningfulLines(text).contains { line in
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
