import Foundation

enum AgentAccessHTTPMethod: String, Equatable {
    case get = "GET"
    case post = "POST"
}

struct AgentAccessHTTPRequest: Equatable {
    let method: AgentAccessHTTPMethod
    let path: String
    let headers: [String: String]
    let body: Data

    var requestID: String? { headers["x-foil-request-id"] }
}

struct AgentAccessHTTPResponse: Equatable {
    let status: Int
    let reason: String
    let headers: [String: String]
    let body: Data

    static func json<T: Encodable>(
        status: Int = 200,
        reason: String = "OK",
        requestID: String,
        value: T
    ) throws -> AgentAccessHTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return AgentAccessHTTPResponse(
            status: status,
            reason: reason,
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "X-Foil-Request-ID": requestID
            ],
            body: try encoder.encode(value)
        )
    }

    func serialized() -> Data {
        var responseHeaders = headers
        responseHeaders["Content-Length"] = String(body.count)
        responseHeaders["Connection"] = "close"
        var text = "HTTP/1.1 \(status) \(reason)\r\n"
        for key in responseHeaders.keys.sorted() {
            text += "\(key): \(responseHeaders[key]!)\r\n"
        }
        text += "\r\n"
        var data = Data(text.utf8)
        data.append(body)
        return data
    }
}

enum AgentAccessHTTPParseResult: Equatable {
    case incomplete
    case complete(AgentAccessHTTPRequest)
    case failure(AgentAccessHTTPError)
}

struct AgentAccessHTTPError: Error, Equatable {
    let status: Int
    let reason: String
    let code: String
    let message: String

    static func badRequest(_ code: String, _ message: String) -> AgentAccessHTTPError {
        AgentAccessHTTPError(status: 400, reason: "Bad Request", code: code, message: message)
    }

    static let headerTooLarge = AgentAccessHTTPError(
        status: 431,
        reason: "Request Header Fields Too Large",
        code: "header_too_large",
        message: "Request headers exceed the Agent Access limit."
    )

    static let bodyTooLarge = AgentAccessHTTPError(
        status: 413,
        reason: "Payload Too Large",
        code: "body_too_large",
        message: "Request body exceeds the Agent Access limit."
    )
}

struct AgentAccessHTTPRequestParser {
    let limits: AgentAccessLimits

    init(limits: AgentAccessLimits = .standard) {
        self.limits = limits
    }

    func parse(_ data: Data) -> AgentAccessHTTPParseResult {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter) else {
            return data.count > limits.maximumHeaderBytes ? .failure(.headerTooLarge) : .incomplete
        }
        guard headerRange.lowerBound <= limits.maximumHeaderBytes else {
            return .failure(.headerTooLarge)
        }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .failure(.badRequest("invalid_header_encoding", "Request headers must be valid UTF-8."))
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .failure(.badRequest("missing_request_line", "Request line is required."))
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard requestParts.count == 3 else {
            return .failure(.badRequest("invalid_request_line", "Use a method, path, and HTTP version."))
        }
        guard requestParts[2] == "HTTP/1.1" else {
            return .failure(.badRequest("unsupported_http_version", "Agent Access requires HTTP/1.1."))
        }
        guard let method = AgentAccessHTTPMethod(rawValue: String(requestParts[0])) else {
            return .failure(.badRequest("unsupported_method", "Agent Access supports GET and POST only."))
        }

        let path = String(requestParts[1])
        guard path.hasPrefix("/"),
              !path.contains("?"),
              !path.contains("#"),
              !path.localizedCaseInsensitiveContains("%2e"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            return .failure(.badRequest("invalid_path", "Request path is not valid."))
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty,
                  let colon = line.firstIndex(of: ":"),
                  colon != line.startIndex else {
                return .failure(.badRequest("invalid_header", "Request contains an invalid header."))
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard isValidHeaderName(name), !headers.keys.contains(name) else {
                return .failure(.badRequest("duplicate_or_invalid_header", "Request contains a duplicate or invalid header."))
            }
            guard value.utf8.allSatisfy({ $0 == 0x09 || ($0 >= 0x20 && $0 != 0x7f) }) else {
                return .failure(.badRequest("invalid_header", "Request contains an invalid header."))
            }
            headers[name] = value
        }

        if headers["transfer-encoding"] != nil {
            return .failure(.badRequest("unsupported_transfer_encoding", "Transfer-Encoding is not supported."))
        }
        if let requestID = headers["x-foil-request-id"], !isValidRequestID(requestID) {
            return .failure(.badRequest("invalid_request_id", "X-Foil-Request-ID must be 1-128 visible ASCII characters."))
        }
        if let contentType = headers["content-type"], !isSupportedContentType(contentType) {
            return .failure(.badRequest("unsupported_content_type", "Use application/json for request bodies."))
        }
        if method == .post && headers["content-type"] == nil {
            return .failure(.badRequest("content_type_required", "POST requests require Content-Type: application/json."))
        }

        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard !rawLength.isEmpty,
                  rawLength.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
                  let parsedLength = Int(rawLength) else {
                return .failure(.badRequest("invalid_content_length", "Content-Length must be a nonnegative integer."))
            }
            contentLength = parsedLength
        } else {
            contentLength = 0
        }
        guard contentLength <= limits.maximumBodyBytes else {
            return .failure(.bodyTooLarge)
        }
        if method == .post && headers["content-length"] == nil {
            return .failure(.badRequest("content_length_required", "POST requests require Content-Length."))
        }

        let bodyStart = headerRange.upperBound
        let availableBodyBytes = data.count - bodyStart
        guard availableBodyBytes >= contentLength else { return .incomplete }
        guard availableBodyBytes == contentLength else {
            return .failure(.badRequest("unexpected_trailing_bytes", "One request is allowed per connection."))
        }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        guard body.isEmpty || String(data: body, encoding: .utf8) != nil else {
            return .failure(.badRequest("invalid_body_encoding", "Request bodies must be valid UTF-8."))
        }
        return .complete(AgentAccessHTTPRequest(method: method, path: path, headers: headers, body: body))
    }

    private func isValidHeaderName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-.^_`|~")
        return name.unicodeScalars.allSatisfy(allowed.contains)
    }

    private func isValidRequestID(_ requestID: String) -> Bool {
        guard !requestID.isEmpty, requestID.utf8.count <= 128 else { return false }
        return requestID.utf8.allSatisfy { $0 >= 0x21 && $0 <= 0x7e }
    }

    private func isSupportedContentType(_ value: String) -> Bool {
        let normalized = value.lowercased().replacingOccurrences(of: " ", with: "")
        return normalized == "application/json" || normalized == "application/json;charset=utf-8"
    }
}

struct AgentAccessContractRouter {
    typealias VocabularyProvider = () -> AgentAccessVocabularyReadModel
    typealias ProposalSubmitter = (VocabularyProposalRequest) throws -> VocabularyProposalSubmission
    typealias ProposalStatusProvider = (String) throws -> VocabularyProposalReceipt

    let socketPath: String
    let openAPIDocument: Data
    let limits: AgentAccessLimits
    let vocabularyProvider: VocabularyProvider
    let proposalSubmitter: ProposalSubmitter?
    let proposalStatusProvider: ProposalStatusProvider?

    init(
        socketPath: String,
        openAPIDocument: Data,
        limits: AgentAccessLimits = .standard,
        vocabularyProvider: @escaping VocabularyProvider = {
            AgentAccessVocabularyReadModel(
                scopes: [], terms: [], corrections: [], localCorrectionsEnabled: false
            )
        },
        proposalSubmitter: ProposalSubmitter? = nil,
        proposalStatusProvider: ProposalStatusProvider? = nil
    ) {
        self.socketPath = socketPath
        self.openAPIDocument = openAPIDocument
        self.limits = limits
        self.vocabularyProvider = vocabularyProvider
        self.proposalSubmitter = proposalSubmitter
        self.proposalStatusProvider = proposalStatusProvider
    }

    func response(to request: AgentAccessHTTPRequest) -> AgentAccessHTTPResponse {
        let requestID = request.requestID ?? UUID().uuidString.lowercased()
        if request.method == .get, !request.body.isEmpty {
            return errorResponse(
                status: 400,
                reason: "Bad Request",
                requestID: requestID,
                code: "unexpected_body",
                message: "GET requests must not include a body."
            )
        }
        switch request.path {
        case "/v1/instructions":
            guard request.method == .get else { return methodNotAllowed(requestID: requestID) }
            let value = AgentAccessInstructionsResponse(
                requestID: requestID,
                socketPath: socketPath,
                limits: limits
            )
            return (try? .json(requestID: requestID, value: value))
                ?? internalError(requestID: requestID)
        case "/v1/openapi.json":
            guard request.method == .get else { return methodNotAllowed(requestID: requestID) }
            return openAPIResponse(requestID: requestID)
        case "/v1/vocabulary/scopes":
            guard request.method == .get else { return methodNotAllowed(requestID: requestID) }
            let value = AgentAccessScopesResponse(
                requestID: requestID,
                scopes: vocabularyProvider().scopes
            )
            return (try? .json(requestID: requestID, value: value))
                ?? internalError(requestID: requestID)
        case "/v1/vocabulary":
            guard request.method == .get else { return methodNotAllowed(requestID: requestID) }
            let model = vocabularyProvider()
            let value = AgentAccessVocabularyResponse(
                requestID: requestID,
                localCorrectionsEnabled: model.localCorrectionsEnabled,
                terms: model.terms,
                corrections: model.corrections
            )
            return (try? .json(requestID: requestID, value: value))
                ?? internalError(requestID: requestID)
        case "/v1/vocabulary/preview":
            guard request.method == .post else { return methodNotAllowed(requestID: requestID) }
            guard let value = try? JSONDecoder().decode(AgentAccessPreviewRequest.self, from: request.body) else {
                return errorResponse(
                    status: 400,
                    reason: "Bad Request",
                    requestID: requestID,
                    code: "invalid_json",
                    message: "Preview requires a JSON object with a corrections array."
                )
            }
            let preview = AgentAccessPreviewEvaluator(limits: limits).evaluate(
                value,
                requestID: requestID,
                scopes: vocabularyProvider().scopes
            )
            return (try? .json(requestID: requestID, value: preview))
                ?? internalError(requestID: requestID)
        case "/v1/vocabulary/proposals":
            guard request.method == .post else { return methodNotAllowed(requestID: requestID) }
            guard let proposalSubmitter else { return unavailableResponse(requestID: requestID) }
            guard let proposal = try? JSONDecoder().decode(VocabularyProposalRequest.self, from: request.body) else {
                return errorResponse(
                    status: 400,
                    reason: "Bad Request",
                    requestID: requestID,
                    code: "invalid_json",
                    message: "Proposal requires a versioned request ID, scope, and corrections array."
                )
            }
            do {
                let submission = try proposalSubmitter(proposal)
                let value = AgentAccessProposalResponse(
                    requestID: requestID,
                    receipt: submission.receipt,
                    replayed: submission.wasReplay
                )
                return (try? .json(
                    status: submission.wasReplay ? 200 : 201,
                    reason: submission.wasReplay ? "OK" : "Created",
                    requestID: requestID,
                    value: value
                )) ?? internalError(requestID: requestID)
            } catch {
                return proposalErrorResponse(error, requestID: requestID)
            }
        default:
            if request.path.hasPrefix("/v1/vocabulary/proposals/") {
                guard request.method == .get else { return methodNotAllowed(requestID: requestID) }
                guard let proposalStatusProvider else { return unavailableResponse(requestID: requestID) }
                let proposalID = String(request.path.dropFirst("/v1/vocabulary/proposals/".count))
                guard !proposalID.isEmpty, !proposalID.contains("/") else {
                    return errorResponse(
                        status: 404,
                        reason: "Not Found",
                        requestID: requestID,
                        code: "proposal_not_found",
                        message: "No proposal matches that ID."
                    )
                }
                do {
                    let receipt = try proposalStatusProvider(proposalID)
                    let value = AgentAccessProposalResponse(
                        requestID: requestID,
                        receipt: receipt,
                        replayed: false
                    )
                    return (try? .json(requestID: requestID, value: value))
                        ?? internalError(requestID: requestID)
                } catch {
                    return proposalErrorResponse(error, requestID: requestID)
                }
            }
            return errorResponse(
                status: 404,
                reason: "Not Found",
                requestID: requestID,
                code: "route_not_found",
                message: "No Agent Access route matches this path."
            )
        }
    }

    private func proposalErrorResponse(_ error: Error, requestID: String) -> AgentAccessHTTPResponse {
        guard let error = error as? VocabularyProposalServiceError else {
            return unavailableResponse(requestID: requestID)
        }
        switch error {
        case .invalidRequestID:
            return errorResponse(status: 400, reason: "Bad Request", requestID: requestID, code: "invalid_request_id", message: "Proposal request_id must be 1-128 visible ASCII characters.")
        case .invalidScope:
            return errorResponse(status: 422, reason: "Unprocessable Content", requestID: requestID, code: "invalid_scope", message: "Choose global scope or an enabled Cleanup Group returned by the scopes endpoint.")
        case let .validation(code, message):
            return errorResponse(status: 422, reason: "Unprocessable Content", requestID: requestID, code: code, message: message)
        case .requestConflict:
            return errorResponse(status: 409, reason: "Conflict", requestID: requestID, code: "request_id_conflict", message: "That request_id was already used for different proposal content.")
        case .queueFull:
            return errorResponse(status: 429, reason: "Too Many Requests", requestID: requestID, code: "proposal_queue_full", message: "Review or discard pending proposals before submitting another.")
        case .notFound:
            return errorResponse(status: 404, reason: "Not Found", requestID: requestID, code: "proposal_not_found", message: "No proposal matches that ID.")
        case .unavailable:
            return unavailableResponse(requestID: requestID)
        }
    }

    private func unavailableResponse(requestID: String) -> AgentAccessHTTPResponse {
        errorResponse(
            status: 503,
            reason: "Service Unavailable",
            requestID: requestID,
            code: "proposal_store_unavailable",
            message: "Foil cannot access the proposal inbox. Open Settings to review the local error."
        )
    }

    private func methodNotAllowed(requestID: String) -> AgentAccessHTTPResponse {
        errorResponse(
            status: 405,
            reason: "Method Not Allowed",
            requestID: requestID,
            code: "method_not_allowed",
            message: "Use the HTTP method documented for this Agent Access route."
        )
    }

    func parseErrorResponse(_ error: AgentAccessHTTPError, requestID: String = UUID().uuidString.lowercased()) -> AgentAccessHTTPResponse {
        errorResponse(
            status: error.status,
            reason: error.reason,
            requestID: requestID,
            code: error.code,
            message: error.message
        )
    }

    private func openAPIResponse(requestID: String) -> AgentAccessHTTPResponse {
        guard var object = (try? JSONSerialization.jsonObject(with: openAPIDocument)) as? [String: Any] else {
            return internalError(requestID: requestID)
        }
        object["x-foil-request-id"] = requestID
        object["x-foil-schema-version"] = AgentAccessContract.schemaVersion
        object["x-foil-socket-path"] = socketPath
        object["x-foil-bootstrap-command"] = AgentAccessInstructionsResponse.bootstrapCommand(
            socketPath: socketPath
        )
        object["x-foil-openapi-command"] = AgentAccessInstructionsResponse.openAPICommand(
            socketPath: socketPath
        )
        guard let body = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return internalError(requestID: requestID)
        }
        return AgentAccessHTTPResponse(
            status: 200,
            reason: "OK",
            headers: [
                "Content-Type": "application/vnd.oai.openapi+json;version=3.1",
                "X-Foil-Request-ID": requestID
            ],
            body: body
        )
    }

    private func internalError(requestID: String) -> AgentAccessHTTPResponse {
        errorResponse(
            status: 500,
            reason: "Internal Server Error",
            requestID: requestID,
            code: "contract_unavailable",
            message: "The Agent Access contract is unavailable."
        )
    }

    private func errorResponse(
        status: Int,
        reason: String,
        requestID: String,
        code: String,
        message: String
    ) -> AgentAccessHTTPResponse {
        let value = AgentAccessErrorBody(requestID: requestID, code: code, message: message)
        return (try? .json(status: status, reason: reason, requestID: requestID, value: value))
            ?? AgentAccessHTTPResponse(status: status, reason: reason, headers: [:], body: Data())
    }
}

struct AgentAccessPreviewEvaluator {
    let limits: AgentAccessLimits

    func evaluate(
        _ request: AgentAccessPreviewRequest,
        requestID: String,
        scopes: [AgentAccessVocabularyScope]
    ) -> AgentAccessPreviewResponse {
        var issues: [AgentAccessPreviewIssue] = []
        var normalized: [AgentAccessPreviewCorrection] = []

        if request.corrections.isEmpty {
            issues.append(.init(
                code: "corrections_required",
                message: "Provide at least one correction to preview.",
                correctionIndex: nil
            ))
        }
        if request.corrections.count > limits.maximumCorrectionPairs {
            issues.append(.init(
                code: "too_many_corrections",
                message: "At most \(limits.maximumCorrectionPairs) corrections may be previewed.",
                correctionIndex: nil
            ))
        }

        let scopeByID = scopes.reduce(into: [String: AgentAccessVocabularyScope]()) { result, scope in
            // Persisted cleanup groups may contain duplicate IDs. Keep the first
            // value so malformed legacy data cannot trap the local API.
            if result[scope.id] == nil { result[scope.id] = scope }
        }
        for (index, correction) in request.corrections.prefix(limits.maximumCorrectionPairs).enumerated() {
            let replacement = correction.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            let scopeID = correction.scopeID?.trimmingCharacters(in: .whitespacesAndNewlines)
            var forms: [String] = []

            if correction.spokenForms.isEmpty {
                issues.append(.init(code: "spoken_forms_required", message: "Provide at least one spoken form.", correctionIndex: index))
            }
            if correction.spokenForms.count > limits.maximumSpokenFormsPerPair {
                issues.append(.init(
                    code: "too_many_spoken_forms",
                    message: "Each correction supports at most \(limits.maximumSpokenFormsPerPair) spoken forms.",
                    correctionIndex: index
                ))
            }
            if replacement.isEmpty {
                issues.append(.init(code: "replacement_required", message: "Replacement cannot be empty.", correctionIndex: index))
            } else if replacement.unicodeScalars.count > limits.maximumPhraseScalars {
                issues.append(.init(code: "phrase_too_long", message: "Replacement exceeds the phrase limit.", correctionIndex: index))
            }
            if let scopeID, !scopeID.isEmpty {
                if let scope = scopeByID[scopeID] {
                    if !scope.isEnabled {
                        issues.append(.init(code: "scope_disabled", message: "The selected scope is disabled.", correctionIndex: index))
                    }
                } else {
                    issues.append(.init(code: "scope_not_found", message: "The selected scope does not exist.", correctionIndex: index))
                }
            }

            for rawForm in correction.spokenForms.prefix(limits.maximumSpokenFormsPerPair) {
                let form = rawForm.trimmingCharacters(in: .whitespacesAndNewlines)
                if form.isEmpty {
                    issues.append(.init(code: "spoken_form_required", message: "Spoken forms cannot be empty.", correctionIndex: index))
                } else if form.unicodeScalars.count > limits.maximumPhraseScalars {
                    issues.append(.init(code: "phrase_too_long", message: "A spoken form exceeds the phrase limit.", correctionIndex: index))
                } else if forms.contains(where: {
                    LocalCorrectionEngine.aliasesOverlap(
                        $0,
                        caseSensitive: correction.caseSensitive,
                        form,
                        caseSensitive: correction.caseSensitive
                    )
                }) {
                    issues.append(.init(code: "duplicate_spoken_form", message: "A spoken form is duplicated in this correction.", correctionIndex: index))
                } else {
                    forms.append(form)
                }
            }
            normalized.append(.init(
                spokenForms: forms,
                replacement: replacement,
                scopeID: scopeID.flatMap { $0.isEmpty ? nil : $0 },
                caseSensitive: correction.caseSensitive
            ))
        }

        let rules = normalized.enumerated().flatMap { pairIndex, correction in
            correction.spokenForms.enumerated().map { formIndex, form in
                LocalCorrectionRule(
                    id: "preview-\(pairIndex)-\(formIndex)",
                    source: form,
                    replacement: correction.replacement,
                    group: correction.scopeID,
                    enabled: true,
                    caseSensitive: correction.caseSensitive
                )
            }
        }
        var compiled: CompiledLocalCorrections?
        if issues.isEmpty {
            do {
                compiled = try LocalCorrectionEngine.compile(rules)
            } catch let error as LocalCorrectionValidationError {
                issues.append(.init(code: "correction_conflict", message: error.description, correctionIndex: nil))
            } catch {
                issues.append(.init(code: "correction_invalid", message: "The correction set could not be compiled.", correctionIndex: nil))
            }
        }

        let examples: [AgentAccessPreviewExample]
        if let compiled {
            examples = normalized.compactMap { correction in
                guard let form = correction.spokenForms.first else { return nil }
                let input = "Use \(form) in this project."
                let result = LocalCorrectionEngine.correct(
                    input,
                    activeGroup: correction.scopeID,
                    enabled: true,
                    compiled: compiled
                )
                return .init(input: input, output: result.text, replacementCount: result.replacementCount)
            }
        } else {
            examples = []
        }

        return AgentAccessPreviewResponse(
            requestID: requestID,
            valid: issues.isEmpty,
            issues: issues,
            normalizedCorrections: normalized,
            examples: examples
        )
    }
}
