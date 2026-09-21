import XCTest
@testable import Foil

final class AgentAccessContractTests: XCTestCase {
    func testReadEndpointsExposeOnlyPurposeBuiltFields() throws {
        let model = AgentAccessVocabularyReadModel(
            scopes: [.init(id: "default", name: "Default", isDefault: true, isEnabled: true)],
            terms: [.init(id: "term-1", term: "Codex", note: "agent")],
            corrections: [.init(
                id: "correction-1",
                writtenAs: "super base",
                correctVersion: "Supabase",
                note: "database",
                localRule: .init(enabled: true, caseSensitive: false, scopeID: "default")
            )],
            localCorrectionsEnabled: false
        )
        let router = makeRouter(model: model)

        for path in ["/v1/vocabulary/scopes", "/v1/vocabulary"] {
            let response = router.response(to: request(.get, path: path))
            let json = String(decoding: response.body, as: UTF8.self)
            XCTAssertEqual(response.status, 200)
            for forbidden in ["source_record", "source_app", "created_at", "updated_at", "provider", "repository", "transcript"] {
                XCTAssertFalse(json.contains(forbidden), "Unexpected field \(forbidden) in \(json)")
            }
        }
    }

    func testPreviewCompilesHypotheticalRulesWhenGlobalProcessingIsOff() throws {
        let model = AgentAccessVocabularyReadModel(
            scopes: [.init(id: "default", name: "Default", isDefault: true, isEnabled: true)],
            terms: [], corrections: [], localCorrectionsEnabled: false
        )
        let body = Data(#"{"corrections":[{"spoken_forms":[" super base ","superbase"],"replacement":" Supabase ","scope_id":"default"}]}"#.utf8)
        let response = makeRouter(model: model).response(to: request(.post, path: "/v1/vocabulary/preview", body: body))
        let preview = try JSONDecoder().decode(AgentAccessPreviewResponse.self, from: response.body)

        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(preview.valid, "\(preview.issues)")
        XCTAssertEqual(preview.normalizedCorrections.first?.spokenForms, ["super base", "superbase"])
        XCTAssertEqual(preview.normalizedCorrections.first?.replacement, "Supabase")
        XCTAssertEqual(preview.examples.first?.output, "Use Supabase in this project.")
        XCTAssertEqual(preview.examples.first?.replacementCount, 1)
    }

    func testPreviewRejectsUnknownScopeDuplicateAliasAndLimitsWithoutMutation() throws {
        let model = AgentAccessVocabularyReadModel(
            scopes: [.init(id: "disabled", name: "Disabled", isDefault: false, isEnabled: false)],
            terms: [], corrections: [], localCorrectionsEnabled: false
        )
        let before = model
        let body = Data(#"{"corrections":[{"spoken_forms":["cloud code","Cloud Code"],"replacement":"Claude Code","scope_id":"missing"}]}"#.utf8)
        let preview = try JSONDecoder().decode(
            AgentAccessPreviewResponse.self,
            from: makeRouter(model: model).response(to: request(.post, path: "/v1/vocabulary/preview", body: body)).body
        )

        XCTAssertFalse(preview.valid)
        XCTAssertEqual(Set(preview.issues.map(\.code)), ["duplicate_spoken_form", "scope_not_found"])
        XCTAssertEqual(model, before)
        XCTAssertTrue(preview.examples.isEmpty)
    }

    func testPreviewAcceptsAliasesThatDifferOnlyByCaseWhenCaseSensitive() throws {
        let model = AgentAccessVocabularyReadModel(
            scopes: [], terms: [], corrections: [], localCorrectionsEnabled: false
        )
        let body = Data(#"{"corrections":[{"spoken_forms":["Codex","codex"],"replacement":"Agent","case_sensitive":true}]}"#.utf8)
        let response = makeRouter(model: model).response(
            to: request(.post, path: "/v1/vocabulary/preview", body: body)
        )
        let preview = try JSONDecoder().decode(AgentAccessPreviewResponse.self, from: response.body)

        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(preview.valid, "\(preview.issues)")
        XCTAssertEqual(preview.normalizedCorrections.first?.spokenForms, ["Codex", "codex"])
        let compiled = try LocalCorrectionEngine.compile([
            .init(id: "upper", source: "Codex", replacement: "Agent", group: nil, enabled: true, caseSensitive: true),
            .init(id: "lower", source: "codex", replacement: "Agent", group: nil, enabled: true, caseSensitive: true)
        ])
        XCTAssertEqual(
            LocalCorrectionEngine.correct("Codex codex", activeGroup: nil, enabled: true, compiled: compiled).replacementCount,
            2
        )
    }

    func testPreviewUsesProductionASCIIFoldingForUnicodeAliases() throws {
        let model = AgentAccessVocabularyReadModel(
            scopes: [], terms: [], corrections: [], localCorrectionsEnabled: false
        )
        let body = Data(#"{"corrections":[{"spoken_forms":["Ä","ä"],"replacement":"A","case_sensitive":false}]}"#.utf8)
        let preview = try JSONDecoder().decode(
            AgentAccessPreviewResponse.self,
            from: makeRouter(model: model).response(
                to: request(.post, path: "/v1/vocabulary/preview", body: body)
            ).body
        )

        XCTAssertTrue(preview.valid, "\(preview.issues)")
        XCTAssertEqual(preview.normalizedCorrections.first?.spokenForms, ["Ä", "ä"])
    }

    func testPreviewDoesNotCrashWhenPersistedScopesContainDuplicateIDs() throws {
        let model = AgentAccessVocabularyReadModel(
            scopes: [
                .init(id: "project", name: "First", isDefault: false, isEnabled: true),
                .init(id: "project", name: "Duplicate", isDefault: false, isEnabled: false)
            ],
            terms: [],
            corrections: [],
            localCorrectionsEnabled: false
        )
        let body = Data(#"{"corrections":[{"spoken_forms":["super base"],"replacement":"Supabase","scope_id":"project"}]}"#.utf8)
        let response = makeRouter(model: model).response(
            to: request(.post, path: "/v1/vocabulary/preview", body: body)
        )
        let preview = try JSONDecoder().decode(AgentAccessPreviewResponse.self, from: response.body)

        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(preview.valid, "\(preview.issues)")
        XCTAssertEqual(preview.normalizedCorrections.first?.scopeID, "project")
    }

    func testPreviewRejectsEmptyCorrectionSet() throws {
        let router = makeRouter(model: .init(scopes: [], terms: [], corrections: [], localCorrectionsEnabled: false))
        let response = router.response(
            to: request(.post, path: "/v1/vocabulary/preview", body: Data(#"{"corrections":[]}"#.utf8))
        )
        let preview = try JSONDecoder().decode(AgentAccessPreviewResponse.self, from: response.body)

        XCTAssertFalse(preview.valid)
        XCTAssertEqual(preview.issues.map(\.code), ["corrections_required"])
        XCTAssertTrue(preview.examples.isEmpty)
    }

    func testPreviewReportsAllConfiguredLimitsAndDisabledScope() throws {
        let limits = AgentAccessLimits(
            maximumHeaderBytes: 1024,
            maximumBodyBytes: 4096,
            maximumCorrectionPairs: 1,
            maximumSpokenFormsPerPair: 1,
            maximumPhraseScalars: 3,
            requestDeadlineSeconds: 1
        )
        let model = AgentAccessVocabularyReadModel(
            scopes: [.init(id: "disabled", name: "Disabled", isDefault: false, isEnabled: false)],
            terms: [], corrections: [], localCorrectionsEnabled: false
        )
        let router = AgentAccessContractRouter(
            socketPath: "/tmp/foil-agent-test.sock",
            openAPIDocument: Data("{}".utf8),
            limits: limits,
            vocabularyProvider: { model }
        )
        let body = Data(#"{"corrections":[{"spoken_forms":["toolong","two"],"replacement":"also-long","scope_id":"disabled"},{"spoken_forms":["x"],"replacement":"y"}]}"#.utf8)
        let response = router.response(to: request(.post, path: "/v1/vocabulary/preview", body: body))
        let preview = try JSONDecoder().decode(AgentAccessPreviewResponse.self, from: response.body)
        let codes = preview.issues.map(\.code)

        XCTAssertFalse(preview.valid)
        for expected in ["too_many_corrections", "too_many_spoken_forms", "phrase_too_long", "scope_disabled"] {
            XCTAssertTrue(codes.contains(expected), "Missing \(expected) in \(codes)")
        }
        XCTAssertTrue(preview.examples.isEmpty)
    }

    func testMalformedAndUndocumentedRequestsFailWithStableErrors() throws {
        let router = makeRouter(model: .init(scopes: [], terms: [], corrections: [], localCorrectionsEnabled: false))
        let malformed = router.response(to: request(.post, path: "/v1/vocabulary/preview", body: Data("{".utf8)))
        let wrongMethod = router.response(to: request(.post, path: "/v1/vocabulary", body: Data("{}".utf8)))
        let unknown = router.response(to: request(.get, path: "/v1/vocabulary/private"))

        XCTAssertEqual(try error(malformed).error.code, "invalid_json")
        XCTAssertEqual(try error(wrongMethod).error.code, "method_not_allowed")
        XCTAssertEqual(try error(unknown).error.code, "route_not_found")
    }

    private func makeRouter(model: AgentAccessVocabularyReadModel) -> AgentAccessContractRouter {
        AgentAccessContractRouter(
            socketPath: "/tmp/foil-agent-test.sock",
            openAPIDocument: Data("{}".utf8),
            vocabularyProvider: { model }
        )
    }

    private func request(_ method: AgentAccessHTTPMethod, path: String, body: Data = Data()) -> AgentAccessHTTPRequest {
        AgentAccessHTTPRequest(method: method, path: path, headers: [:], body: body)
    }

    private func error(_ response: AgentAccessHTTPResponse) throws -> AgentAccessErrorBody {
        try JSONDecoder().decode(AgentAccessErrorBody.self, from: response.body)
    }
}
