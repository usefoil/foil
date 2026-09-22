import XCTest
@testable import Foil

final class VocabularyProposalContractTests: XCTestCase {
    func testDocumentedRequestShapeDecodesWithSafeDefaults() throws {
        let data = Data(#"""
        {
          "schema_version": 1,
          "request_id": "opaque-idempotency-key",
          "scope": { "kind": "cleanup_group", "id": "agents" },
          "corrections": [{
            "spoken_forms": ["super base", "superbase", "super bass"],
            "replacement": "Supabase",
            "note": "Project dependency"
          }]
        }
        """#.utf8)

        let request = try JSONDecoder().decode(VocabularyProposalRequest.self, from: data)

        XCTAssertEqual(request.schemaVersion, 1)
        XCTAssertEqual(request.requestID, "opaque-idempotency-key")
        XCTAssertEqual(request.scope, .init(kind: "cleanup_group", id: "agents"))
        XCTAssertEqual(request.corrections.first?.spokenForms, ["super base", "superbase", "super bass"])
        XCTAssertEqual(request.corrections.first?.replacement, "Supabase")
        XCTAssertEqual(request.corrections.first?.note, "Project dependency")
        XCTAssertEqual(request.corrections.first?.caseSensitive, false)
    }

    func testReceiptUsesVersionedSnakeCaseWireFields() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let receipt = VocabularyProposalReceipt(
            requestID: "request-1",
            proposalID: "proposal-1",
            state: .pending,
            createdAt: date,
            updatedAt: date
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(receipt)) as? [String: Any]
        )

        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["request_id"] as? String, "request-1")
        XCTAssertEqual(object["proposal_id"] as? String, "proposal-1")
        XCTAssertEqual(object["state"] as? String, "pending")
        XCTAssertNotNil(object["created_at"])
        XCTAssertNotNil(object["updated_at"])
        XCTAssertNil(object["request_hash"])
        XCTAssertNil(object["snapshot_token"])
    }

    func testCanonicalDigestIgnoresJSONFormattingAndNormalizesText() throws {
        let decomposed = "Cafe\u{301}"
        let first = VocabularyProposalRequest(
            requestID: " request-1 ",
            scope: .init(kind: " cleanup_group ", id: " agents "),
            corrections: [.init(
                spokenForms: ["  super base\n", decomposed],
                replacement: " Supabase ",
                note: " project dependency "
            )]
        )
        let second = VocabularyProposalRequest(
            requestID: "request-1",
            scope: .init(kind: "cleanup_group", id: "agents"),
            corrections: [.init(
                spokenForms: ["super base", "Café"],
                replacement: "Supabase",
                note: "project dependency"
            )]
        )

        let firstDigest = try first.canonicalPayloadDigest()
        let secondDigest = try second.canonicalPayloadDigest()
        XCTAssertEqual(firstDigest, secondDigest)
        XCTAssertEqual(first.canonicalized(), second)
    }

    func testCanonicalDigestChangesWhenMeaningfulContentOrOrderChanges() throws {
        let base = request(id: "same", aliases: ["one", "two"])
        let changedReplacement = VocabularyProposalRequest(
            requestID: "same",
            scope: base.scope,
            corrections: [.init(spokenForms: ["one", "two"], replacement: "Different")]
        )
        let reordered = request(id: "same", aliases: ["two", "one"])

        let baseDigest = try base.canonicalPayloadDigest()
        let changedDigest = try changedReplacement.canonicalPayloadDigest()
        let reorderedDigest = try reordered.canonicalPayloadDigest()
        XCTAssertNotEqual(baseDigest, changedDigest)
        XCTAssertNotEqual(baseDigest, reorderedDigest)
    }

    func testProposalStorePathIsBrandScopedAndInsideSupportDirectory() throws {
        let root = URL(fileURLWithPath: "/tmp/foil-agent-contract", isDirectory: true)
        let production = AgentAccessPaths(applicationSupportRoot: root, directoryName: "Foil")
        let development = AgentAccessPaths(applicationSupportRoot: root, directoryName: "Foil Dev")

        XCTAssertEqual(production.proposalStoreURL.lastPathComponent, "agent-vocabulary-proposals-v1.json")
        XCTAssertEqual(production.proposalStoreURL.deletingLastPathComponent(), production.supportDirectory)
        XCTAssertEqual(development.proposalStoreURL.deletingLastPathComponent(), development.supportDirectory)
        XCTAssertNotEqual(production.proposalStoreURL, development.proposalStoreURL)
        XCTAssertNoThrow(try production.validateSocketPath())
        XCTAssertNoThrow(try development.validateSocketPath())
    }

    private func request(id: String, aliases: [String]) -> VocabularyProposalRequest {
        VocabularyProposalRequest(
            requestID: id,
            scope: .init(kind: "cleanup_group", id: "agents"),
            corrections: [.init(spokenForms: aliases, replacement: "Replacement")]
        )
    }
}
