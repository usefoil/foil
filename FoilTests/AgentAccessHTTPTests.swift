import CryptoKit
import XCTest
@testable import Foil

final class AgentAccessHTTPTests: XCTestCase {
    private let parser = AgentAccessHTTPRequestParser()

    func testParsesBoundedGETRequestAndNormalizesHeaders() {
        let data = Data("GET /v1/instructions HTTP/1.1\r\nHost: foil\r\nX-Foil-Request-ID: request-1\r\n\r\n".utf8)

        XCTAssertEqual(
            parser.parse(data),
            .complete(AgentAccessHTTPRequest(
                method: .get,
                path: "/v1/instructions",
                headers: ["host": "foil", "x-foil-request-id": "request-1"],
                body: Data()
            ))
        )
    }

    func testFragmentedRequestRemainsIncompleteUntilBodyArrives() {
        let first = Data("POST /v1/example HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{".utf8)
        let complete = Data("POST /v1/example HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}".utf8)

        XCTAssertEqual(parser.parse(first), .incomplete)
        guard case let .complete(request) = parser.parse(complete) else {
            return XCTFail("Expected a complete request")
        }
        XCTAssertEqual(request.body, Data("{}".utf8))
    }

    func testRejectsOversizedHeadersBeforeDelimiter() {
        let limits = AgentAccessLimits(
            maximumHeaderBytes: 32,
            maximumBodyBytes: 64,
            maximumCorrectionPairs: 1,
            maximumSpokenFormsPerPair: 1,
            maximumPhraseScalars: 10,
            requestDeadlineSeconds: 1
        )
        let result = AgentAccessHTTPRequestParser(limits: limits).parse(
            Data("GET /v1/instructions HTTP/1.1\r\nX-Fill: abcdefghijklmnopqrstuvwxyz".utf8)
        )

        XCTAssertEqual(result, .failure(.headerTooLarge))
    }

    func testRejectsOversizedBodyFromContentLengthWithoutWaitingForIt() {
        let limits = AgentAccessLimits(
            maximumHeaderBytes: 1_024,
            maximumBodyBytes: 4,
            maximumCorrectionPairs: 1,
            maximumSpokenFormsPerPair: 1,
            maximumPhraseScalars: 10,
            requestDeadlineSeconds: 1
        )
        let data = Data("POST /v1/example HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 5\r\n\r\n".utf8)

        XCTAssertEqual(
            AgentAccessHTTPRequestParser(limits: limits).parse(data),
            .failure(.bodyTooLarge)
        )
    }

    func testRejectsDuplicateHeadersAndTransferEncoding() {
        let duplicate = Data("GET /v1/instructions HTTP/1.1\r\nHost: one\r\nHost: two\r\n\r\n".utf8)
        let chunked = Data("POST /v1/example HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)

        XCTAssertEqual(errorCode(parser.parse(duplicate)), "duplicate_or_invalid_header")
        XCTAssertEqual(errorCode(parser.parse(chunked)), "unsupported_transfer_encoding")
    }

    func testRejectsUnsupportedMethodVersionAndContentTypes() {
        let method = Data("PUT /v1/instructions HTTP/1.1\r\n\r\n".utf8)
        let version = Data("GET /v1/instructions HTTP/2\r\n\r\n".utf8)
        let missingType = Data("POST /v1/example HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}".utf8)
        let wrongType = Data("POST /v1/example HTTP/1.1\r\nContent-Type: text/plain\r\nContent-Length: 2\r\n\r\n{}".utf8)

        XCTAssertEqual(errorCode(parser.parse(method)), "unsupported_method")
        XCTAssertEqual(errorCode(parser.parse(version)), "unsupported_http_version")
        XCTAssertEqual(errorCode(parser.parse(missingType)), "content_type_required")
        XCTAssertEqual(errorCode(parser.parse(wrongType)), "unsupported_content_type")
    }

    func testRejectsNonnumericContentLengthAndControlCharacters() {
        let signedLength = Data("POST /v1/example HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: +2\r\n\r\n{}".utf8)
        var controlHeader = Data("GET /v1/instructions HTTP/1.1\r\nX-Test: ok".utf8)
        controlHeader.append(0)
        controlHeader.append(Data("bad\r\n\r\n".utf8))

        XCTAssertEqual(errorCode(parser.parse(signedLength)), "invalid_content_length")
        XCTAssertEqual(errorCode(parser.parse(controlHeader)), "invalid_header")
    }

    func testProposalStatesAreStableContractValues() throws {
        XCTAssertEqual(
            AgentAccessProposalState.allCases.map(\.rawValue),
            ["pending", "applied", "rejected", "discarded"]
        )
        let data = try JSONEncoder().encode(AgentAccessProposalState.pending)
        XCTAssertEqual(try JSONDecoder().decode(AgentAccessProposalState.self, from: data), .pending)
    }

    func testRejectsPOSTWithoutLengthTrailingBytesAndInvalidUTF8() {
        let noLength = Data("POST /v1/example HTTP/1.1\r\nContent-Type: application/json\r\n\r\n".utf8)
        let trailing = Data("GET /v1/instructions HTTP/1.1\r\n\r\nx".utf8)
        var invalidUTF8 = Data("GET /v1/instructions HTTP/1.1\r\nX-Test: ".utf8)
        invalidUTF8.append(0xff)
        invalidUTF8.append(Data("\r\n\r\n".utf8))
        var invalidBody = Data("POST /v1/example HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 1\r\n\r\n".utf8)
        invalidBody.append(0xff)

        XCTAssertEqual(errorCode(parser.parse(noLength)), "content_length_required")
        XCTAssertEqual(errorCode(parser.parse(trailing)), "unexpected_trailing_bytes")
        XCTAssertEqual(errorCode(parser.parse(invalidUTF8)), "invalid_header_encoding")
        XCTAssertEqual(errorCode(parser.parse(invalidBody)), "invalid_body_encoding")
    }

    func testRejectsTraversalQueryFragmentsAndEncodedDotSegments() {
        for path in ["/v1/../secret", "/v1/%2e%2e/secret", "/v1/instructions?q=x", "/v1/instructions#x"] {
            let data = Data("GET \(path) HTTP/1.1\r\n\r\n".utf8)
            XCTAssertEqual(errorCode(parser.parse(data)), "invalid_path", path)
        }
    }

    func testRejectsInvalidRequestIDs() {
        let spaced = Data("GET /v1/instructions HTTP/1.1\r\nX-Foil-Request-ID: not valid\r\n\r\n".utf8)
        let tooLong = String(repeating: "a", count: 129)
        let long = Data("GET /v1/instructions HTTP/1.1\r\nX-Foil-Request-ID: \(tooLong)\r\n\r\n".utf8)

        XCTAssertEqual(errorCode(parser.parse(spaced)), "invalid_request_id")
        XCTAssertEqual(errorCode(parser.parse(long)), "invalid_request_id")
    }

    func testInstructionsRouterReturnsOnlyImplementedOperationsAndLimits() throws {
        let router = AgentAccessContractRouter(
            socketPath: "/tmp/Foil Test/agent-v1.sock",
            openAPIDocument: try openAPIData()
        )
        let request = AgentAccessHTTPRequest(
            method: .get,
            path: "/v1/instructions",
            headers: ["x-foil-request-id": "contract-test"],
            body: Data()
        )

        let response = router.response(to: request)
        let decoded = try JSONDecoder().decode(AgentAccessInstructionsResponse.self, from: response.body)

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(decoded.requestID, "contract-test")
        XCTAssertEqual(decoded.availableOperations, [
            "get_instructions", "get_openapi", "list_vocabulary_scopes",
            "list_vocabulary", "preview_vocabulary_corrections",
            "verify_vocabulary_targets", "preview_effective_vocabulary",
            "propose_vocabulary_corrections", "get_vocabulary_proposal_status",
            "request_vocabulary_action", "get_vocabulary_action_status",
            "get_paired_agent_access", "submit_delegated_vocabulary_proposal",
            "submit_delegated_correction_policies"
        ])
        XCTAssertEqual(decoded.limits, .standard)
        XCTAssertTrue(decoded.bootstrapCommand.contains("--unix-socket"))
        XCTAssertTrue(decoded.bootstrapCommand.contains("/tmp/Foil Test/agent-v1.sock"))
        XCTAssertEqual(decoded.openAPIPath, "/v1/openapi.json")
        XCTAssertTrue(decoded.openAPICommand.contains("http://foil/v1/openapi.json"))
        XCTAssertTrue(decoded.openAPICommand.contains("/tmp/Foil Test/agent-v1.sock"))
        XCTAssertTrue(decoded.unavailableBehavior.contains("exits nonzero within 12 seconds"))
        XCTAssertTrue(decoded.correctionGuidance.contains("case sensitivity"))
        XCTAssertTrue(decoded.correctionGuidance.contains("punctuation between words"))
        XCTAssertTrue(decoded.correctionGuidance.contains("approval inside Foil"))
    }

    func testOpenAPIRouterAddsRequestMetadataAndMatchesImplementedPaths() throws {
        let router = AgentAccessContractRouter(
            socketPath: "/tmp/agent-v1.sock",
            openAPIDocument: try openAPIData()
        )
        let response = router.response(to: AgentAccessHTTPRequest(
            method: .get,
            path: "/v1/openapi.json",
            headers: ["x-foil-request-id": "openapi-test"],
            body: Data()
        ))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let paths = try XCTUnwrap(object["paths"] as? [String: Any])

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(object["x-foil-request-id"] as? String, "openapi-test")
        XCTAssertEqual(object["x-foil-schema-version"] as? Int, 1)
        XCTAssertEqual(object["x-foil-socket-path"] as? String, "/tmp/agent-v1.sock")
        XCTAssertEqual(
            object["x-foil-bootstrap-command"] as? String,
            AgentAccessInstructionsResponse.bootstrapCommand(socketPath: "/tmp/agent-v1.sock")
        )
        XCTAssertEqual(
            object["x-foil-openapi-command"] as? String,
            AgentAccessInstructionsResponse.openAPICommand(socketPath: "/tmp/agent-v1.sock")
        )
        XCTAssertEqual(Set(paths.keys), [
            "/v1/instructions", "/v1/openapi.json", "/v1/vocabulary/scopes",
            "/v1/vocabulary", "/v1/vocabulary/preview",
            "/v1/vocabulary/targets/verify", "/v1/vocabulary/effective-preview",
            "/v1/vocabulary/proposals",
            "/v1/vocabulary/proposals/{proposal_id}",
            "/v1/vocabulary/actions", "/v1/vocabulary/actions/{action_id}",
            "/v1/access", "/v1/vocabulary/delegated-proposals",
            "/v1/vocabulary/delegated-actions"
        ])
        let limits = try XCTUnwrap(object["x-foil-limits"] as? [String: Any])
        XCTAssertEqual(limits["maximum_header_bytes"] as? Int, AgentAccessLimits.standard.maximumHeaderBytes)
        XCTAssertEqual(limits["maximum_body_bytes"] as? Int, AgentAccessLimits.standard.maximumBodyBytes)
        XCTAssertEqual(limits["maximum_correction_pairs"] as? Int, AgentAccessLimits.standard.maximumCorrectionPairs)
        XCTAssertEqual(limits["maximum_spoken_forms_per_pair"] as? Int, AgentAccessLimits.standard.maximumSpokenFormsPerPair)
        XCTAssertEqual(limits["maximum_phrase_scalars"] as? Int, AgentAccessLimits.standard.maximumPhraseScalars)
        XCTAssertEqual(limits["request_deadline_seconds"] as? Int, AgentAccessLimits.standard.requestDeadlineSeconds)
        XCTAssertEqual(
            object["x-foil-proposal-states"] as? [String],
            AgentAccessProposalState.allCases.map(\.rawValue)
        )
        let components = try XCTUnwrap(object["components"] as? [String: Any])
        let schemas = try XCTUnwrap(components["schemas"] as? [String: Any])
        for schema in [
            "InstructionsResponse", "ScopesResponse", "VocabularyResponse",
            "PreviewRequest", "PreviewResponse", "ProposalRequest", "ProposalResponse",
            "TargetVerificationRequest", "TargetVerificationResponse",
            "EffectivePreviewRequest", "EffectivePreviewResponse", "CorrectionPolicy",
            "ActionRequest", "ActionResponse", "GrantStatusResponse",
            "ErrorResponse"
        ] {
            XCTAssertNotNil(schemas[schema], "Missing schema \(schema)")
        }
        let previewRequest = try XCTUnwrap(schemas["PreviewRequest"] as? [String: Any])
        let previewProperties = try XCTUnwrap(previewRequest["properties"] as? [String: Any])
        let corrections = try XCTUnwrap(previewProperties["corrections"] as? [String: Any])
        XCTAssertEqual(corrections["minItems"] as? Int, 1)
        for schemaName in ["PreviewCorrection", "ProposalCorrection", "CorrectionPolicy", "LocalRule", "EffectiveRule"] {
            let schema = try XCTUnwrap(schemas[schemaName] as? [String: Any])
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            XCTAssertNotNil(properties["match_punctuation_variants"], schemaName)
        }
        for (path, method) in [
            ("/v1/instructions", "get"),
            ("/v1/openapi.json", "get"),
            ("/v1/vocabulary/scopes", "get"),
            ("/v1/vocabulary", "get"),
            ("/v1/vocabulary/preview", "post"),
            ("/v1/vocabulary/targets/verify", "post"),
            ("/v1/vocabulary/effective-preview", "post"),
            ("/v1/vocabulary/proposals", "post"),
            ("/v1/vocabulary/proposals/{proposal_id}", "get"),
            ("/v1/vocabulary/actions", "post"),
            ("/v1/vocabulary/actions/{action_id}", "get"),
            ("/v1/access", "get"),
            ("/v1/vocabulary/delegated-proposals", "post"),
            ("/v1/vocabulary/delegated-actions", "post")
        ] {
            let pathItem = try XCTUnwrap(paths[path] as? [String: Any])
            let operation = try XCTUnwrap(pathItem[method] as? [String: Any])
            let responses = try XCTUnwrap(operation["responses"] as? [String: Any])
            let successCode = path == "/v1/vocabulary/proposals" || path == "/v1/vocabulary/actions"
                ? "201" : path.contains("delegated-") ? "202" : "200"
            let success = try XCTUnwrap(responses[successCode] as? [String: Any])
            XCTAssertNotNil(success["content"], "Missing 200 response schema for \(method.uppercased()) \(path)")
        }
        let privacy = try XCTUnwrap(object["x-foil-privacy"] as? [String: Any])
        XCTAssertEqual(
            Set(try XCTUnwrap(privacy["excludes"] as? [String])),
            [
                "history", "transcript", "audio", "credentials", "provider_configuration",
                "source_record", "source_app", "timestamps", "project_files", "repository",
                "clipboard", "active_application"
            ]
        )
    }

    func testRouterRejectsUnknownRoutesMethodsAndGETBodiesWithStableErrors() throws {
        let router = AgentAccessContractRouter(
            socketPath: "/tmp/agent-v1.sock",
            openAPIDocument: try openAPIData()
        )
        let unknown = router.response(to: AgentAccessHTTPRequest(
            method: .get,
            path: "/v1/unknown",
            headers: [:],
            body: Data()
        ))
        let method = router.response(to: AgentAccessHTTPRequest(
            method: .post,
            path: "/v1/instructions",
            headers: [:],
            body: Data()
        ))
        let body = router.response(to: AgentAccessHTTPRequest(
            method: .get,
            path: "/v1/instructions",
            headers: [:],
            body: Data("x".utf8)
        ))

        XCTAssertEqual(unknown.status, 404)
        XCTAssertEqual(try errorBody(unknown).error.code, "route_not_found")
        XCTAssertEqual(method.status, 405)
        XCTAssertEqual(try errorBody(method).error.code, "method_not_allowed")
        XCTAssertEqual(body.status, 400)
        XCTAssertEqual(try errorBody(body).error.code, "unexpected_body")
    }

    func testGrantStoreKeepsOnlyTokenDigestAndFailsClosedAfterExpiryOrRevocation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-grant-test-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("grants.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let token = "foil_" + String(repeating: "a", count: 64)
        let start = Date(timeIntervalSince1970: 1_700_000_000.345)
        let store = AgentAccessGrantStore(fileURL: file, now: { start }, makeToken: { token })
        let (grant, issued) = try store.create(name: " Codex ", groupID: "agent-apps", appPaths: ["/Applications/Codex.app"])
        XCTAssertEqual(issued, token)
        XCTAssertEqual(grant.name, "Codex")
        XCTAssertEqual(try store.authorize(token).id, grant.id)
        XCTAssertThrowsError(try store.authorize("foil_" + String(repeating: "b", count: 64)))
        let restarted = AgentAccessGrantStore(fileURL: file, now: { start.addingTimeInterval(30) })
        XCTAssertThrowsError(try restarted.authorize(token)) {
            XCTAssertEqual($0 as? AgentAccessGrantError, .unauthorized)
        }
        XCTAssertTrue(try XCTUnwrap(restarted.load().grants.first).summary.isRevoked)
        let data = try Data(contentsOf: file)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(token))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let forgedToken = "foil_" + String(repeating: "f", count: 64)
        let forgedDigest = SHA256.hash(data: Data(forgedToken.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let forged = StoredAgentAccessGrant(
            summary: AgentAccessGrantSummary(
                id: UUID().uuidString.lowercased(), name: "Forged", groupID: "agent-apps",
                appPaths: ["/Applications/Codex.app"], createdAt: start,
                expiresAt: start.addingTimeInterval(3_600), revokedAt: nil
            ), tokenDigest: forgedDigest
        )
        let snapshot = try store.load()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(AgentAccessGrantSnapshot(
            grants: snapshot.grants + [forged], uses: snapshot.uses
        )).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: file.path)
        XCTAssertThrowsError(try store.authorize(forgedToken)) {
            XCTAssertEqual($0 as? AgentAccessGrantError, .unauthorized)
        }
        XCTAssertTrue(try XCTUnwrap(store.load().grants.first(where: { $0.summary.id == forged.summary.id })).summary.isRevoked)

        let expired = AgentAccessGrantStore(fileURL: file, now: { start.addingTimeInterval(3_601) })
        XCTAssertThrowsError(try expired.authorize(token)) { XCTAssertEqual($0 as? AgentAccessGrantError, .unauthorized) }
        try store.revoke(id: grant.id)
        XCTAssertThrowsError(try store.authorize(token)) { XCTAssertEqual($0 as? AgentAccessGrantError, .unauthorized) }
    }

    func testGrantStoreRejectsUnsafeOrCorruptFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-grant-unsafe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("grants.json")
        try Data("not json".utf8).write(to: file)
        let store = AgentAccessGrantStore(fileURL: file)
        XCTAssertThrowsError(try store.load())
        try FileManager.default.removeItem(at: file)
        let other = directory.appendingPathComponent("other.json")
        try Data("{}".utf8).write(to: other)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: other)
        XCTAssertThrowsError(try store.load())
    }

    func testEndingAgentAccessInvalidatesActiveGrantWithoutTrustingTheAuditFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("foil-grant-session-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let token = "foil_" + String(repeating: "e", count: 64)
        let store = AgentAccessGrantStore(
            fileURL: directory.appendingPathComponent("grants.json"), makeToken: { token }
        )
        _ = try store.create(name: "Codex", groupID: "agent-apps", appPaths: ["/Applications/Codex.app"])
        XCTAssertNoThrow(try store.authorize(token))
        store.invalidateAll()
        XCTAssertThrowsError(try store.authorize(token)) {
            XCTAssertEqual($0 as? AgentAccessGrantError, .unauthorized)
        }
        XCTAssertTrue(try XCTUnwrap(store.load().grants.first).summary.isRevoked)
    }

    func testDelegatedRoutesRequireBearerGrant() throws {
        let grant = AgentAccessGrantSummary(
            id: UUID().uuidString, name: "Codex", groupID: "agent-apps",
            appPaths: ["/Applications/Codex.app"], createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3_600), revokedAt: nil
        )
        let router = AgentAccessContractRouter(
            socketPath: "/tmp/agent-v1.sock", openAPIDocument: try openAPIData(),
            grantProvider: { token in
                guard token == "foil_valid" else { throw AgentAccessGrantError.unauthorized }
                return grant
            },
            delegatedProposalSubmitter: { _, _ in throw AgentAccessGrantError.invalidScope },
            delegatedActionSubmitter: { _, _ in throw AgentAccessGrantError.invalidScope }
        )
        let missing = router.response(to: .init(method: .get, path: "/v1/access", headers: [:], body: Data()))
        XCTAssertEqual(missing.status, 401)
        let accepted = router.response(to: .init(
            method: .get, path: "/v1/access", headers: ["authorization": "Bearer foil_valid"], body: Data()
        ))
        XCTAssertEqual(accepted.status, 200)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: accepted.body) as? [String: Any])
        XCTAssertEqual(body["group_id"] as? String, "agent-apps")
        XCTAssertNil(body["token"])
        let invalid = router.response(to: .init(
            method: .get, path: "/v1/access", headers: ["authorization": "Bearer foil_bad"], body: Data()
        ))
        XCTAssertEqual(invalid.status, 401)
        for route in ["/v1/vocabulary/delegated-proposals", "/v1/vocabulary/delegated-actions"] {
            let response = router.response(to: .init(method: .post, path: route, headers: [:], body: Data("{}".utf8)))
            XCTAssertEqual(response.status, 401, route)
        }
    }

    private func errorCode(_ result: AgentAccessHTTPParseResult) -> String? {
        guard case let .failure(error) = result else { return nil }
        return error.code
    }

    private func errorBody(_ response: AgentAccessHTTPResponse) throws -> AgentAccessErrorBody {
        try JSONDecoder().decode(AgentAccessErrorBody.self, from: response.body)
    }

    private func openAPIData() throws -> Data {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Foil/Resources/AgentAccessOpenAPI.json")
        return try Data(contentsOf: fileURL)
    }
}
