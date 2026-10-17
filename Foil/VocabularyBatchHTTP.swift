import Foundation

struct VocabularyBatchHTTP {
    let store: VocabularyBatchStore
    let model: () -> AgentAccessVocabularyReadModel
    let didChange: () -> Void
    var delegatedSubmit: ((VocabularyBatchRequest, String) throws -> VocabularyBatchRecord)? = nil

    func response(to request: AgentAccessHTTPRequest, requestID: String) -> AgentAccessHTTPResponse {
        do {
            switch request.path {
            case "/v2/vocabulary":
                guard request.method == .get else { return failure(405, "method_not_allowed", "Use GET.", requestID) }
                struct Response: Encodable {
                    let schema_version = 2
                    let terms: [VocabularyBatchTerm]
                    let corrections: [AgentAccessVocabularyCorrection]
                    let scopes: [AgentAccessVocabularyScope]
                    let local_corrections_enabled: Bool
                    let pending_proposals: [VocabularyBatchRecord]
                }
                let snapshot = model()
                return try .json(requestID: requestID, value: Response(terms: snapshot.scopedTerms, corrections: snapshot.corrections, scopes: snapshot.scopes, local_corrections_enabled: snapshot.localCorrectionsEnabled, pending_proposals: try store.records().filter { $0.state == .pending }))
            case "/v2/vocabulary/preview", "/v2/vocabulary/proposals", "/v2/vocabulary/delegated-proposals":
                guard request.method == .post else { return failure(405, "method_not_allowed", "Use POST.", requestID) }
                guard request.body.count <= AgentAccessLimits.standard.maximumBodyBytes else {
                    return failure(413, "body_too_large", "Request body exceeds the Agent Access limit.", requestID)
                }
                let decoded: VocabularyBatchRequest
                do { decoded = try JSONDecoder().decode(VocabularyBatchRequest.self, from: request.body) }
                catch { return failure(400, "invalid_json", "Use a v2 request with request_id, scope, and typed items.", requestID) }
                guard decoded.schemaVersion == 2 else { throw VocabularyBatchError.invalid("Use schema_version 2.") }
                if request.path.hasSuffix("/preview") {
                    return try .json(requestID: requestID, value: VocabularyBatchEvaluator.preview(decoded, model: model()))
                }
                if request.path.hasSuffix("/delegated-proposals") {
                    guard let token = request.bearerToken, let delegatedSubmit else { throw AgentAccessGrantError.unauthorized }
                    let record = try delegatedSubmit(decoded, token)
                    didChange()
                    return try .json(status: record.state == .applied ? 200 : 202, reason: "Accepted", requestID: requestID, value: record)
                }
                let result = try store.submit(decoded) {
                    try Self.validate(decoded, model: model())
                }
                if !result.replay { didChange() }
                return try .json(status: result.replay ? 200 : 202, reason: result.replay ? "OK" : "Accepted", requestID: requestID, value: result.record)
            default:
                let prefix = "/v2/vocabulary/proposals/"
                guard request.path.hasPrefix(prefix), request.method == .get else {
                    return failure(404, "not_found", "No such Vocabulary operation.", requestID)
                }
                let id = String(request.path.dropFirst(prefix.count))
                guard UUID(uuidString: id) != nil else { throw VocabularyBatchError.notFound }
                return try .json(requestID: requestID, value: store.record(id: id))
            }
        } catch let error as AgentAccessGrantError {
            return failure(403, "grant_required", error.localizedDescription, requestID)
        } catch let error as VocabularyBatchError {
            switch error {
            case .invalid: return failure(400, "invalid_batch", error.localizedDescription, requestID)
            case .conflict: return failure(409, "batch_conflict", error.localizedDescription, requestID)
            case .notFound: return failure(404, "not_found", error.localizedDescription, requestID)
            case .queueFull: return failure(429, "queue_full", error.localizedDescription, requestID)
            case .unavailable: return failure(503, "unavailable", error.localizedDescription, requestID)
            }
        } catch { return failure(503, "unavailable", "Foil could not read or save this batch.", requestID) }
    }

    static func validate(_ request: VocabularyBatchRequest, model: AgentAccessVocabularyReadModel) throws {
        let preview = VocabularyBatchEvaluator.preview(request, model: model)
        guard preview.valid else {
            let messages = preview.issues + preview.items.filter { $0.disposition == .invalid || $0.disposition == .conflict }.map(\.message)
            throw VocabularyBatchError.invalid(messages.joined(separator: " "))
        }
    }

    static func unavailable(requestID: String) -> AgentAccessHTTPResponse {
        failure(503, "unavailable", "Foil Agent Access is unavailable.", requestID)
    }

    private func failure(_ status: Int, _ code: String, _ message: String, _ requestID: String) -> AgentAccessHTTPResponse {
        Self.failure(status, code, message, requestID)
    }

    private static func failure(_ status: Int, _ code: String, _ message: String, _ requestID: String) -> AgentAccessHTTPResponse {
        // All values are fixed or bounded validation messages; request contents are never logged.
        let value = AgentAccessErrorBody(requestID: requestID, code: code, message: message)
        return (try? .json(status: status, reason: "Vocabulary Request Error", requestID: requestID, value: value))
            ?? AgentAccessHTTPResponse(status: 500, reason: "Internal Server Error", headers: [:], body: Data())
    }
}
