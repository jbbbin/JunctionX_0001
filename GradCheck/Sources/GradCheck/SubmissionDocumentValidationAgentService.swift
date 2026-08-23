import Foundation

/// Executes the user's separate Upstage Studio Agent for one uploaded
/// submission file at a time. It is deliberately independent of both the
/// admissions-requirements Agent and the applicant-identity Agent.
protocol SubmissionDocumentValidating: Sendable {
    var providerLabel: String { get }
    var hasAPIKey: Bool { get }
    func analyze(url: URL) async throws -> SubmissionDocumentValidation
}

struct UnavailableSubmissionDocumentValidator: SubmissionDocumentValidating {
    var providerLabel: String { "Upstage Studio 제출 서류 검증 Agent 설정 필요" }
    var hasAPIKey: Bool { false }

    func analyze(url: URL) async throws -> SubmissionDocumentValidation {
        throw SubmissionDocumentValidationAgentError.missingAPIKey
    }
}

enum SubmissionDocumentValidationAgentError: LocalizedError {
    case missingAgent
    case missingAPIKey
    case unreadableFile(String)
    case invalidResponse
    case api(status: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .missingAgent:
            "제출 서류 검증 Agent 설정을 찾지 못했어요."
        case .missingAPIKey:
            "제출 서류 검증 Agent를 실행하려면 Upstage API 키가 필요해요."
        case let .unreadableFile(name):
            "\(name) 파일을 읽지 못했습니다."
        case .invalidResponse:
            "Agent 결과에서 문서 유형을 읽지 못했어요."
        case let .api(status, detail):
            "Upstage 제출 서류 검증 Agent 오류 (HTTP \(status)): \(detail)"
        }
    }
}

struct SubmissionDocumentValidationAgentService: SubmissionDocumentValidating {
    private let agent: StudioAgentConfiguration?
    private let apiKeyStore: any UpstageAPIKeyStoring
    private let baseURL = URL(string: "https://api.upstage.ai/v2")!

    init(apiKeyStore: any UpstageAPIKeyStoring) {
        agent = StudioAgentCatalog.configuration(for: .submissionDocumentValidation)
        self.apiKeyStore = apiKeyStore
    }

    var providerLabel: String {
        guard let agent else { return "Upstage Studio 제출 서류 검증 Agent 설정 필요" }
        return "Upstage Studio · \(agent.displayName)"
    }

    var hasAPIKey: Bool {
        (try? apiKeyStore.readAPIKey())?.isEmpty == false
    }

    func analyze(url: URL) async throws -> SubmissionDocumentValidation {
        guard let agent else { throw SubmissionDocumentValidationAgentError.missingAgent }
        guard let apiKey = try apiKeyStore.readAPIKey(), !apiKey.isEmpty else {
            throw SubmissionDocumentValidationAgentError.missingAPIKey
        }

        let fileID = try await upload(url: url, apiKey: apiKey)
        do {
            let jobID = try await createJob(fileID: fileID, agent: agent, apiKey: apiKey)
            let output = try await waitForJob(id: jobID, apiKey: apiKey)
            let validation = try decode(output: output)
            try? await deleteUploadedFile(id: fileID, apiKey: apiKey)
            return validation
        } catch {
            // User documents can include personal data, so always clean them
            // up on the Agent API after a completed or failed run.
            try? await deleteUploadedFile(id: fileID, apiKey: apiKey)
            throw error
        }
    }

    private func upload(url: URL, apiKey: String) async throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let file = try? Data(contentsOf: url), !file.isEmpty else {
            throw SubmissionDocumentValidationAgentError.unreadableFile(url.lastPathComponent)
        }

        let boundary = "GradCheckSubmissionValidation-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: "files"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(file: file, filename: url.lastPathComponent, boundary: boundary)
        let data = try await requestData(request)
        return try JSONDecoder().decode(SubmissionValidationUploadedFile.self, from: data).id
    }

    private func createJob(
        fileID: String,
        agent: StudioAgentConfiguration,
        apiKey: String
    ) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "responses"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": agent.agentID,
            "config_id": agent.configID,
            "include": ["last"],
            "input": [[
                "role": "user",
                "content": [["type": "input_file", "file_id": fileID]],
            ]],
        ])
        let data = try await requestData(request)
        return try JSONDecoder().decode(SubmissionValidationJob.self, from: data).id
    }

    private func waitForJob(id: String, apiKey: String) async throws -> String {
        for _ in 0..<45 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            var components = URLComponents(
                url: baseURL.appending(path: "responses/\(id)"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "include[]", value: "last")]
            guard let url = components?.url else {
                throw SubmissionDocumentValidationAgentError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 60
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let data = try await requestData(request)
            let job = try JSONDecoder().decode(SubmissionValidationJob.self, from: data)
            if job.status == "completed",
               let text = job.outputText ?? job.output?.last?.content?.last?.text {
                return text
            }
            if job.status == "failed" || job.status == "cancelled" {
                throw SubmissionDocumentValidationAgentError.api(
                    status: 500,
                    detail: "Studio Agent 실행이 실패했습니다."
                )
            }
        }
        throw SubmissionDocumentValidationAgentError.api(
            status: 408,
            detail: "Studio Agent 응답 시간이 초과되었습니다."
        )
    }

    private func deleteUploadedFile(id: String, apiKey: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "files/\(id)"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try await requestData(request)
    }

    private func requestData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SubmissionDocumentValidationAgentError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            let raw = String(data: data, encoding: .utf8) ?? "요청이 거절되었습니다."
            throw SubmissionDocumentValidationAgentError.api(
                status: response.statusCode,
                detail: String(raw.prefix(240))
            )
        }
        return data
    }

    private func multipartBody(file: Data, filename: String, boundary: String) -> Data {
        var body = Data()
        func append(_ value: String) { body.append(value.data(using: .utf8) ?? Data()) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\nuser_data\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(file)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func decode(output: String) throws -> SubmissionDocumentValidation {
        guard let data = normalizedJSON(output).data(using: .utf8) else {
            throw SubmissionDocumentValidationAgentError.invalidResponse
        }
        do {
            let payload = try JSONDecoder().decode(SubmissionValidationPayload.self, from: data)
            guard let documentType = normalizedString(payload.documentType) else {
                throw SubmissionDocumentValidationAgentError.invalidResponse
            }
            return SubmissionDocumentValidation(
                rawDocumentType: documentType,
                documentSubtype: normalizedString(payload.documentSubtype),
                documentTitle: normalizedString(payload.documentTitle),
                classificationConfidence: normalizedString(payload.classificationConfidence),
                classificationReason: normalizedString(payload.classificationReason),
                applicantName: normalizedString(payload.applicantName),
                applicantEmail: normalizedString(payload.applicantEmail),
                issuingOrganization: normalizedString(payload.issuingOrganization),
                documentDate: normalizedString(payload.documentDate),
                expirationDate: normalizedString(payload.expirationDate),
                evidenceItems: payload.evidenceItems.map { item in
                    SubmissionDocumentValidation.Evidence(
                        factType: normalizedString(item.factType),
                        value: normalizedString(item.factValue),
                        page: pageNumber(item.sourcePage),
                        quote: normalizedString(item.sourceQuote)
                    )
                }
            )
        } catch let error as SubmissionDocumentValidationAgentError {
            throw error
        } catch {
            throw SubmissionDocumentValidationAgentError.invalidResponse
        }
    }

    private func normalizedJSON(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }
        text = text.components(separatedBy: .newlines).dropFirst().joined(separator: "\n")
        if let end = text.range(of: "\n```", options: .backwards) {
            text = String(text[..<end.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !["null", "not_stated", "not stated", "n/a"].contains(normalized.lowercased())
        else { return nil }
        return normalized
    }

    private func pageNumber(_ value: String?) -> Int? {
        guard let value,
              let range = value.range(of: #"\d+"#, options: .regularExpression)
        else { return nil }
        return Int(value[range])
    }
}

private struct SubmissionValidationUploadedFile: Decodable { let id: String }

private struct SubmissionValidationJob: Decodable {
    struct Output: Decodable {
        struct Content: Decodable { let text: String? }
        let content: [Content]?
    }

    let id: String
    let status: String
    let outputText: String?
    let output: [Output]?

    enum CodingKeys: String, CodingKey {
        case id, status, output
        case outputText = "output_text"
    }
}

private struct SubmissionValidationPayload: Decodable {
    struct EvidenceItem: Decodable {
        let factType: String?
        let factValue: String?
        let sourcePage: String?
        let sourceQuote: String?

        enum CodingKeys: String, CodingKey {
            case factType = "fact_type"
            case factValue = "fact_value"
            case sourcePage = "source_page"
            case sourceQuote = "source_quote"
        }
    }

    let documentType: String?
    let documentSubtype: String?
    let documentTitle: String?
    let classificationConfidence: String?
    let classificationReason: String?
    let applicantName: String?
    let applicantEmail: String?
    let issuingOrganization: String?
    let documentDate: String?
    let expirationDate: String?
    let evidenceItems: [EvidenceItem]

    enum CodingKeys: String, CodingKey {
        case documentType = "document_type"
        case documentSubtype = "document_subtype"
        case documentTitle = "document_title"
        case classificationConfidence = "classification_confidence"
        case classificationReason = "classification_reason"
        case applicantName = "applicant_name"
        case applicantEmail = "applicant_email"
        case issuingOrganization = "issuing_organization"
        case documentDate = "document_date"
        case expirationDate = "expiration_date"
        case evidenceItems = "evidence_items"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        documentType = try values.decodeIfPresent(String.self, forKey: .documentType)
        documentSubtype = try values.decodeIfPresent(String.self, forKey: .documentSubtype)
        documentTitle = try values.decodeIfPresent(String.self, forKey: .documentTitle)
        classificationConfidence = try values.decodeIfPresent(String.self, forKey: .classificationConfidence)
        classificationReason = try values.decodeIfPresent(String.self, forKey: .classificationReason)
        applicantName = try values.decodeIfPresent(String.self, forKey: .applicantName)
        applicantEmail = try values.decodeIfPresent(String.self, forKey: .applicantEmail)
        issuingOrganization = try values.decodeIfPresent(String.self, forKey: .issuingOrganization)
        documentDate = try values.decodeIfPresent(String.self, forKey: .documentDate)
        expirationDate = try values.decodeIfPresent(String.self, forKey: .expirationDate)
        evidenceItems = try values.decodeIfPresent([EvidenceItem].self, forKey: .evidenceItems) ?? []
    }
}
