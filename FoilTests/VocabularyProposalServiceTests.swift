import XCTest
@testable import Foil

final class VocabularyProposalServiceTests: XCTestCase {
    func testValidSubmissionPersistsAndStatusReturnsSameReceipt() throws {
        let fixture = try makeFixture()

        let submission = try fixture.service.submit(request(id: "request-1"))
        let status = try fixture.service.status(id: submission.receipt.proposalID)

        XCTAssertFalse(submission.wasReplay)
        XCTAssertEqual(status, submission.receipt)
        XCTAssertEqual(status.state, .pending)
        XCTAssertEqual(try fixture.store.load().proposals.count, 1)
    }

    func testSemanticReplayReturnsOriginalAfterReviewEditAndDifferentPayloadConflicts() throws {
        let fixture = try makeFixture()
        let original = request(id: "request-1")
        let created = try fixture.service.submit(original)
        _ = try fixture.service.revise(
            id: created.receipt.proposalID,
            scope: .init(kind: "global", id: "global"),
            corrections: [.init(spokenForms: ["superbase"], replacement: "Supabase", note: "reviewed")]
        )

        let replay = try fixture.service.submit(original)
        XCTAssertTrue(replay.wasReplay)
        XCTAssertEqual(replay.receipt.proposalID, created.receipt.proposalID)
        XCTAssertEqual(try fixture.store.load().proposals.first?.scope.kind, "global")

        XCTAssertThrowsError(try fixture.service.submit(request(id: "request-1", replacement: "Postgres"))) {
            XCTAssertEqual($0 as? VocabularyProposalServiceError, .requestConflict)
        }
    }

    func testInvalidProposalsFailWithoutCreatingStore() throws {
        let fixture = try makeFixture()
        let tooMany = (0...AgentAccessLimits.standard.maximumCorrectionPairs).map {
            VocabularyProposalCorrection(spokenForms: ["alias-\($0)"], replacement: "Value")
        }
        let tooManySpokenForms = (0...AgentAccessLimits.standard.maximumSpokenFormsPerPair).map {
            "alias-\($0)"
        }
        let overlongPhrase = String(
            repeating: "x",
            count: AgentAccessLimits.standard.maximumPhraseScalars + 1
        )
        let cases: [(VocabularyProposalRequest, VocabularyProposalServiceError)] = [
            (
                VocabularyProposalRequest(
                    schemaVersion: 999,
                    requestID: "request",
                    scope: .init(kind: "global", id: "global"),
                    corrections: [.init(spokenForms: ["x"], replacement: "y")]
                ),
                .validation(code: "unsupported_schema_version", message: "Use proposal schema version 1.")
            ),
            (
                VocabularyProposalRequest(
                    requestID: "not valid",
                    scope: .init(kind: "global", id: "global"),
                    corrections: [.init(spokenForms: ["x"], replacement: "y")]
                ),
                .invalidRequestID
            ),
            (
                VocabularyProposalRequest(
                    requestID: "empty",
                    scope: .init(kind: "global", id: "global"),
                    corrections: []
                ),
                .validation(code: "corrections_required", message: "Provide at least one correction to preview.")
            ),
            (
                VocabularyProposalRequest(
                    requestID: "invalid-scope",
                    scope: .init(kind: "cleanup_group", id: "missing"),
                    corrections: [.init(spokenForms: ["x"], replacement: "y")]
                ),
                .invalidScope
            ),
            (
                VocabularyProposalRequest(
                    requestID: "duplicate",
                    scope: .init(kind: "global", id: "global"),
                    corrections: [.init(spokenForms: ["Codex", "codex"], replacement: "Agent")]
                ),
                .validation(code: "duplicate_spoken_form", message: "A spoken form is duplicated in this correction.")
            ),
            (
                VocabularyProposalRequest(
                    requestID: "too-many-spoken-forms",
                    scope: .init(kind: "global", id: "global"),
                    corrections: [.init(spokenForms: tooManySpokenForms, replacement: "Value")]
                ),
                .validation(
                    code: "too_many_spoken_forms",
                    message: "Each correction supports at most 10 spoken forms."
                )
            ),
            (
                VocabularyProposalRequest(
                    requestID: "overlong-spoken-form",
                    scope: .init(kind: "global", id: "global"),
                    corrections: [.init(spokenForms: [overlongPhrase], replacement: "Value")]
                ),
                .validation(code: "phrase_too_long", message: "A spoken form exceeds the phrase limit.")
            ),
            (
                VocabularyProposalRequest(
                    requestID: "overlong-replacement",
                    scope: .init(kind: "global", id: "global"),
                    corrections: [.init(spokenForms: ["alias"], replacement: overlongPhrase)]
                ),
                .validation(code: "phrase_too_long", message: "Replacement exceeds the phrase limit.")
            ),
            (
                VocabularyProposalRequest(
                    requestID: "overlong-note",
                    scope: .init(kind: "global", id: "global"),
                    corrections: [.init(spokenForms: ["alias"], replacement: "Value", note: overlongPhrase)]
                ),
                .validation(code: "note_too_long", message: "Notes may contain at most 256 Unicode scalars.")
            ),
            (
                VocabularyProposalRequest(
                    requestID: "too-many",
                    scope: .init(kind: "global", id: "global"),
                    corrections: tooMany
                ),
                .validation(code: "too_many_corrections", message: "At most 50 corrections may be previewed.")
            )
        ]

        for (request, expected) in cases {
            XCTAssertThrowsError(try fixture.service.submit(request)) {
                XCTAssertEqual($0 as? VocabularyProposalServiceError, expected)
            }
        }
        XCTAssertThrowsError(try fixture.service.submit(VocabularyProposalRequest(
            requestID: "ambiguous",
            scope: .init(kind: "global", id: "global"),
            corrections: [
                .init(spokenForms: ["Codex"], replacement: "First"),
                .init(spokenForms: ["codex"], replacement: "Second")
            ]
        ))) { error in
            guard case .validation(code: "correction_conflict", message: _) = error as? VocabularyProposalServiceError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.fileURL.path))
    }

    func testDisabledScopeAndExistingRuleConflictFailClosed() throws {
        let fixture = try makeFixture(model: .init(
            scopes: [.init(id: "disabled", name: "Disabled", isDefault: false, isEnabled: false)],
            terms: [],
            corrections: [.init(
                id: "existing",
                writtenAs: "super base",
                correctVersion: "Supabase",
                note: nil,
                localRule: .init(enabled: true, caseSensitive: false, scopeID: nil)
            )],
            localCorrectionsEnabled: true
        ))

        XCTAssertThrowsError(try fixture.service.submit(VocabularyProposalRequest(
            requestID: "disabled",
            scope: .init(kind: "cleanup_group", id: "disabled"),
            corrections: [.init(spokenForms: ["x"], replacement: "y")]
        ))) {
            XCTAssertEqual($0 as? VocabularyProposalServiceError, .invalidScope)
        }
        XCTAssertThrowsError(try fixture.service.submit(request(id: "conflict"))) { error in
            guard case .validation(code: "correction_conflict", message: _) = error as? VocabularyProposalServiceError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.fileURL.path))
    }

    func testReviewPreviewReportsConflictIntroducedAfterSubmission() throws {
        let fixture = try makeFixture()
        let submission = try fixture.service.submit(request(id: "request-1"))
        fixture.readModelStore.update(.init(
            scopes: [],
            terms: [],
            corrections: [.init(
                id: "existing",
                writtenAs: "super base",
                correctVersion: "Different",
                note: nil,
                localRule: .init(enabled: true, caseSensitive: false, scopeID: nil)
            )],
            localCorrectionsEnabled: true
        ))
        let proposal = try XCTUnwrap(fixture.store.proposal(id: submission.receipt.proposalID))

        let preview = fixture.service.preview(for: proposal)

        XCTAssertFalse(preview.valid)
        XCTAssertEqual(preview.issues.map(\.code), ["correction_conflict"])
        XCTAssertTrue(preview.examples.isEmpty)
    }

    func testRouterCreatesReplaysReportsConflictAndReturnsStatus() throws {
        let fixture = try makeFixture()
        let router = AgentAccessContractRouter(
            socketPath: "/tmp/foil-agent-test.sock",
            openAPIDocument: Data("{}".utf8),
            vocabularyProvider: { fixture.readModelStore.snapshot() },
            proposalSubmitter: { try fixture.service.submit($0) },
            proposalStatusProvider: { try fixture.service.status(id: $0) }
        )
        let body = try JSONEncoder().encode(request(id: "request-1"))

        let created = router.response(to: httpRequest(.post, path: "/v1/vocabulary/proposals", body: body))
        let createdResponse = try decodeResponse(created)
        let replay = router.response(to: httpRequest(.post, path: "/v1/vocabulary/proposals", body: body))
        let replayResponse = try decodeResponse(replay)
        let status = router.response(to: httpRequest(
            .get,
            path: "/v1/vocabulary/proposals/\(createdResponse.proposalID)"
        ))
        let conflictBody = try JSONEncoder().encode(request(id: "request-1", replacement: "Postgres"))
        let conflict = router.response(to: httpRequest(.post, path: "/v1/vocabulary/proposals", body: conflictBody))

        XCTAssertEqual(created.status, 201)
        XCTAssertFalse(createdResponse.replayed)
        XCTAssertEqual(replay.status, 200)
        XCTAssertTrue(replayResponse.replayed)
        XCTAssertEqual(replayResponse.proposalID, createdResponse.proposalID)
        XCTAssertEqual(status.status, 200)
        XCTAssertEqual(try decodeResponse(status).state, .pending)
        XCTAssertEqual(conflict.status, 409)
        XCTAssertEqual(try decodeError(conflict).error.code, "request_id_conflict")
    }

    func testRouterRejectsMalformedAndMissingProposalWithoutMutation() throws {
        let fixture = try makeFixture()
        let router = AgentAccessContractRouter(
            socketPath: "/tmp/foil-agent-test.sock",
            openAPIDocument: Data("{}".utf8),
            vocabularyProvider: { fixture.readModelStore.snapshot() },
            proposalSubmitter: { try fixture.service.submit($0) },
            proposalStatusProvider: { try fixture.service.status(id: $0) }
        )

        let malformed = router.response(to: httpRequest(
            .post,
            path: "/v1/vocabulary/proposals",
            body: Data("{".utf8)
        ))
        let missing = router.response(to: httpRequest(.get, path: "/v1/vocabulary/proposals/missing"))

        XCTAssertEqual(malformed.status, 400)
        XCTAssertEqual(try decodeError(malformed).error.code, "invalid_json")
        XCTAssertEqual(missing.status, 404)
        XCTAssertEqual(try decodeError(missing).error.code, "proposal_not_found")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.fileURL.path))
    }

    private func makeFixture(
        model: AgentAccessVocabularyReadModel = .init(
            scopes: [.init(id: "agents", name: "Agents", isDefault: false, isEnabled: true)],
            terms: [],
            corrections: [],
            localCorrectionsEnabled: false
        )
    ) throws -> (
        service: VocabularyProposalService,
        store: VocabularyProposalStore,
        readModelStore: AgentAccessReadModelStore
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoilVocabularyProposalServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = VocabularyProposalStore(
            fileURL: directory.appendingPathComponent(AgentAccessPaths.proposalStoreFileName)
        )
        let readModelStore = AgentAccessReadModelStore()
        readModelStore.update(model)
        return (
            VocabularyProposalService(
                store: store,
                readModelStore: readModelStore,
                limits: .standard
            ),
            store,
            readModelStore
        )
    }

    private func request(id: String, replacement: String = "Supabase") -> VocabularyProposalRequest {
        VocabularyProposalRequest(
            requestID: id,
            scope: .init(kind: "global", id: "global"),
            corrections: [.init(
                spokenForms: ["super base"],
                replacement: replacement,
                note: "project dependency"
            )]
        )
    }

    private func httpRequest(
        _ method: AgentAccessHTTPMethod,
        path: String,
        body: Data = Data()
    ) -> AgentAccessHTTPRequest {
        AgentAccessHTTPRequest(
            method: method,
            path: path,
            headers: ["x-foil-request-id": "http-test"],
            body: body
        )
    }

    private func decodeResponse(_ response: AgentAccessHTTPResponse) throws -> AgentAccessProposalResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentAccessProposalResponse.self, from: response.body)
    }

    private func decodeError(_ response: AgentAccessHTTPResponse) throws -> AgentAccessErrorBody {
        try JSONDecoder().decode(AgentAccessErrorBody.self, from: response.body)
    }
}
