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
    let socketPath: String
    let openAPIDocument: Data
    let limits: AgentAccessLimits

    init(socketPath: String, openAPIDocument: Data, limits: AgentAccessLimits = .standard) {
        self.socketPath = socketPath
        self.openAPIDocument = openAPIDocument
        self.limits = limits
    }

    func response(to request: AgentAccessHTTPRequest) -> AgentAccessHTTPResponse {
        let requestID = request.requestID ?? UUID().uuidString.lowercased()
        guard request.method == .get else {
            return errorResponse(
                status: 405,
                reason: "Method Not Allowed",
                requestID: requestID,
                code: "method_not_allowed",
                message: "This contract host supports GET only."
            )
        }
        guard request.body.isEmpty else {
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
            let value = AgentAccessInstructionsResponse(
                requestID: requestID,
                socketPath: socketPath,
                limits: limits
            )
            return (try? .json(requestID: requestID, value: value))
                ?? internalError(requestID: requestID)
        case "/v1/openapi.json":
            return openAPIResponse(requestID: requestID)
        default:
            return errorResponse(
                status: 404,
                reason: "Not Found",
                requestID: requestID,
                code: "route_not_found",
                message: "No Agent Access route matches this path."
            )
        }
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
