import Foundation

enum UpstageAPIError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case requestRejected(statusCode: Int)
    case rateLimited
    case usageLimitExceeded
    case networkUnavailable
    case serviceUnavailable
    case invalidResponse
    case truncatedResponse
    case emptyDocument
    case sourceTooLarge

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Upstage API 키를 먼저 연결해 주세요."
        case .invalidAPIKey:
            "Upstage API 키가 유효하지 않아요. 키를 다시 확인해 주세요."
        case let .requestRejected(statusCode):
            "Upstage가 요청을 처리하지 못했어요. (HTTP \(statusCode))"
        case .rateLimited:
            "Upstage 요청이 잠시 많아요. 잠시 후 다시 시도해 주세요."
        case .usageLimitExceeded:
            "Upstage 사용 한도를 확인해 주세요. 이 요청은 자동 재시도하지 않았어요."
        case .networkUnavailable:
            "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
        case .serviceUnavailable:
            "Upstage 서비스에 일시적으로 연결할 수 없어요."
        case .invalidResponse:
            "Upstage 분석 결과를 읽지 못했어요. 다시 시도해 주세요."
        case .truncatedResponse:
            "Upstage 분석 결과가 중간에 잘렸어요. 더 짧은 원문으로 다시 시도해 주세요."
        case .emptyDocument:
            "문서에서 분석할 텍스트를 찾지 못했어요."
        case .sourceTooLarge:
            "선택한 원문이 로컬 분석 허용 크기를 넘었어요."
        }
    }
}

struct UpstageAPIConfiguration: Sendable {
    static let solarModelEnvironmentVariable = "UPSTAGE_SOLAR_MODEL"
    static let documentModelEnvironmentVariable = "UPSTAGE_DOCUMENT_MODEL"

    var baseURL: URL
    var documentModel: String
    var solarModel: String
    var requestTimeout: TimeInterval

    init(
        baseURL: URL = URL(string: "https://api.upstage.ai/v1")!,
        documentModel: String = "document-parse",
        solarModel: String = "solar-pro4",
        requestTimeout: TimeInterval = 180
    ) {
        self.baseURL = baseURL
        self.documentModel = documentModel
        self.solarModel = solarModel
        self.requestTimeout = requestTimeout
    }

    static func local(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UpstageAPIConfiguration {
        let documentModel = normalized(
            environment[documentModelEnvironmentVariable],
            fallback: "document-parse"
        )
        let solarModel = normalized(
            environment[solarModelEnvironmentVariable],
            fallback: "solar-pro4"
        )
        return UpstageAPIConfiguration(
            documentModel: documentModel,
            solarModel: solarModel
        )
    }

    private static func normalized(_ value: String?, fallback: String) -> String {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }
}

enum UpstageOCRMode: String, Sendable {
    case auto
    case force
}

struct UpstageDocumentInput: Sendable {
    var data: Data
    var filename: String
    var mimeType: String
    var ocrMode: UpstageOCRMode
}

struct UpstageParsedDocument: Sendable {
    var content: String
}

/// Keeps large, synchronous preparation work off the main actor while preserving
/// structured-concurrency cancellation for callers that own the UI state.
enum AnalysisBackgroundWorker {
    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let value = try operation()
            try Task.checkCancellation()
            return value
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

indirect enum UpstageJSONSchemaNode: Sendable {
    case object(properties: [String: UpstageJSONSchemaNode], required: [String])
    case array(items: UpstageJSONSchemaNode)
    case string(enumValues: [String]? = nil)
    case integer
    case nullableString
    case nullableInteger

    fileprivate var jsonObject: Any {
        switch self {
        case let .object(properties, required):
            return [
                "type": "object",
                "properties": properties.mapValues(\.jsonObject),
                "required": required,
                "additionalProperties": false,
            ] as [String: Any]
        case let .array(items):
            return ["type": "array", "items": items.jsonObject] as [String: Any]
        case let .string(enumValues):
            var value: [String: Any] = ["type": "string"]
            if let enumValues {
                value["enum"] = enumValues
            }
            return value
        case .integer:
            return ["type": "integer"]
        case .nullableString:
            return ["type": ["string", "null"]]
        case .nullableInteger:
            return ["type": ["integer", "null"]]
        }
    }
}

struct UpstageStructuredOutputSchema: Sendable {
    var name: String
    var root: UpstageJSONSchemaNode
}

@MainActor
protocol UpstageAPIClienting: AnyObject {
    func parseDocument(_ input: UpstageDocumentInput) async throws -> UpstageParsedDocument
    func createStructuredCompletion(
        systemPrompt: String,
        userPrompt: String,
        schema: UpstageStructuredOutputSchema
    ) async throws -> String
}

@MainActor
protocol UpstageRequestPerforming: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

@MainActor
final class URLSessionUpstageTransport: UpstageRequestPerforming {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

@MainActor
final class UpstageAPIClient: UpstageAPIClienting {
    private let apiKeyStore: any UpstageAPIKeyStoring
    private let configuration: UpstageAPIConfiguration
    private let transport: any UpstageRequestPerforming

    init(
        apiKeyStore: any UpstageAPIKeyStoring,
        configuration: UpstageAPIConfiguration = .local(),
        transport: (any UpstageRequestPerforming)? = nil
    ) {
        self.apiKeyStore = apiKeyStore
        self.configuration = configuration
        self.transport = transport ?? URLSessionUpstageTransport()
    }

    func parseDocument(_ input: UpstageDocumentInput) async throws -> UpstageParsedDocument {
        let boundary = "PassReady-\(UUID().uuidString)"
        let documentModel = configuration.documentModel
        var request = URLRequest(
            url: configuration.baseURL.appending(path: "document-digitization")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        try authorize(&request)
        request.httpBody = try await AnalysisBackgroundWorker.run {
            try Self.multipartBody(
                input: input,
                boundary: boundary,
                documentModel: documentModel
            )
        }

        let data = try await validatedData(for: request)
        return try await AnalysisBackgroundWorker.run {
            try Task.checkCancellation()
            let response: DocumentParseResponse
            do {
                response = try JSONDecoder().decode(DocumentParseResponse.self, from: data)
            } catch {
                throw UpstageAPIError.invalidResponse
            }

            guard let content = response.bestContent else {
                throw UpstageAPIError.emptyDocument
            }
            try Task.checkCancellation()
            return UpstageParsedDocument(content: content)
        }
    }

    func createStructuredCompletion(
        systemPrompt: String,
        userPrompt: String,
        schema: UpstageStructuredOutputSchema
    ) async throws -> String {
        var request = URLRequest(
            url: configuration.baseURL.appending(path: "chat/completions")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try authorize(&request)

        let solarModel = configuration.solarModel
        request.httpBody = try await AnalysisBackgroundWorker.run {
            try Self.structuredCompletionBody(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                schema: schema,
                solarModel: solarModel
            )
        }

        let data = try await validatedData(for: request)
        return try await AnalysisBackgroundWorker.run {
            try Task.checkCancellation()
            let response: ChatCompletionResponse
            do {
                response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            } catch {
                throw UpstageAPIError.invalidResponse
            }

            guard let choice = response.choices.first else {
                throw UpstageAPIError.invalidResponse
            }
            guard choice.finishReason == "stop" else {
                throw choice.finishReason == "length"
                    ? UpstageAPIError.truncatedResponse
                    : UpstageAPIError.invalidResponse
            }
            guard let content = choice.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty
            else {
                throw UpstageAPIError.invalidResponse
            }
            try Task.checkCancellation()
            return content
        }
    }

    private func authorize(_ request: inout URLRequest) throws {
        guard let apiKey = try apiKeyStore.loadAPIKey() else {
            throw UpstageAPIError.missingAPIKey
        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private func validatedData(
        for request: URLRequest,
        rateLimitRetryCount: Int = 0
    ) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw UpstageAPIError.networkUnavailable
        }
        guard let response = response as? HTTPURLResponse else {
            throw UpstageAPIError.invalidResponse
        }

        switch response.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw UpstageAPIError.invalidAPIKey
        case 413:
            throw UpstageAPIError.sourceTooLarge
        case 429 where errorCode(in: data) == "usage_limit_exceeded":
            throw UpstageAPIError.usageLimitExceeded
        case 429 where rateLimitRetryCount == 0:
            let seconds = min(max(retryDelay(from: response), 1), 5)
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return try await validatedData(
                for: request,
                rateLimitRetryCount: rateLimitRetryCount + 1
            )
        case 429:
            throw UpstageAPIError.rateLimited
        case 500..<600:
            throw UpstageAPIError.serviceUnavailable
        default:
            throw UpstageAPIError.requestRejected(statusCode: response.statusCode)
        }
    }

    private func retryDelay(from response: HTTPURLResponse) -> Double {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Double(value)
        else { return 1 }
        return seconds
    }

    private func errorCode(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any]
        else { return nil }
        return error["code"] as? String
    }

    private nonisolated static func structuredCompletionBody(
        systemPrompt: String,
        userPrompt: String,
        schema: UpstageStructuredOutputSchema,
        solarModel: String
    ) throws -> Data {
        try Task.checkCancellation()
        var body: [String: Any] = [
            "model": solarModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": 0.1,
            "max_tokens": 6_000,
            "stream": false,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": schema.name,
                    "strict": true,
                    "schema": schema.root.jsonObject,
                ],
            ],
        ]
        if solarModel.hasPrefix("solar-pro") {
            body["reasoning_effort"] = "minimal"
        }
        try Task.checkCancellation()

        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            try Task.checkCancellation()
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UpstageAPIError.invalidResponse
        }
    }

    private nonisolated static func multipartBody(
        input: UpstageDocumentInput,
        boundary: String,
        documentModel: String
    ) throws -> Data {
        try Task.checkCancellation()
        var data = Data()
        appendField(name: "model", value: documentModel, boundary: boundary, to: &data)
        appendField(name: "mode", value: "auto", boundary: boundary, to: &data)
        appendField(name: "ocr", value: input.ocrMode.rawValue, boundary: boundary, to: &data)
        appendField(name: "output_formats", value: "[\"markdown\",\"text\"]", boundary: boundary, to: &data)
        appendField(name: "coordinates", value: "false", boundary: boundary, to: &data)
        appendField(name: "base64_encoding", value: "[]", boundary: boundary, to: &data)
        try Task.checkCancellation()

        let filename = input.filename
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"document\"; filename=\"\(filename)\"\r\n")
        data.appendUTF8("Content-Type: \(input.mimeType)\r\n\r\n")
        try Task.checkCancellation()
        data.append(input.data)
        try Task.checkCancellation()
        data.appendUTF8("\r\n--\(boundary)--\r\n")
        return data
    }

    private nonisolated static func appendField(
        name: String,
        value: String,
        boundary: String,
        to data: inout Data
    ) {
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.appendUTF8("\(value)\r\n")
    }
}

private struct DocumentParseResponse: Decodable, Sendable {
    struct Content: Decodable, Sendable {
        var markdown: String?
        var text: String?
        var html: String?

        var bestValue: String? {
            [markdown, text, html]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })
        }
    }

    struct Element: Decodable, Sendable {
        var content: Content?
        var page: Int?
    }

    var content: Content?
    var elements: [Element]?

    var bestContent: String? {
        let values = (elements ?? []).compactMap { element -> String? in
            guard let content = element.content?.bestValue else { return nil }
            if let page = element.page {
                // Upstage's official Solar Pro 4 Cookbook treats this value as
                // a 1-based human page number and adds only a zero-based chunk
                // offset when merging split PDFs.
                return "[PAGE \(page)]\n\(content)"
            }
            return content
        }
        if !values.isEmpty {
            return values.joined(separator: "\n\n")
        }
        return content?.bestValue
    }
}

private struct ChatCompletionResponse: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Message: Decodable, Sendable {
            var content: String?
        }

        var message: Message
        var finishReason: String

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    var choices: [Choice]
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(Data(value.utf8))
    }
}
