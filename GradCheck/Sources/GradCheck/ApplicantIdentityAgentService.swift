import Foundation

protocol ApplicantIdentityAnalyzing: Sendable {
    var providerLabel: String { get }
    var hasAPIKey: Bool { get }
    func analyze(url: URL) async throws -> ApplicantIdentityExtraction
}

struct UnavailableApplicantIdentityAnalyzer: ApplicantIdentityAnalyzing {
    var providerLabel: String { "Upstage Studio 신원 검증 Agent 설정 필요" }
    var hasAPIKey: Bool { false }

    func analyze(url: URL) async throws -> ApplicantIdentityExtraction {
        throw ApplicantIdentityAgentError.missingAPIKey
    }
}

enum ApplicantIdentityAgentError: LocalizedError {
    case missingAgent
    case missingAPIKey
    case unreadableFile(String)
    case invalidResponse
    case api(status: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .missingAgent:
            "지원자 신원 검증 Agent 설정을 찾지 못했어요."
        case .missingAPIKey:
            "지원자 신원 검증 Agent를 실행하려면 Upstage API 키가 필요해요."
        case let .unreadableFile(name):
            "\(name) 파일을 읽지 못했습니다."
        case .invalidResponse:
            "Agent 결과에서 이름 또는 이메일을 읽지 못했어요."
        case let .api(status, detail):
            "Upstage 신원 검증 Agent 오류 (HTTP \(status)): \(detail)"
        }
    }
}

/// A second, independent Studio Agent. It deliberately shares only the API key
/// store with the requirements Agent; its output schema and audit use are separate.
struct ApplicantIdentityAgentService: ApplicantIdentityAnalyzing {
    private let agent: StudioAgentConfiguration?
    private let apiKeyStore: any UpstageAPIKeyStoring
    private let baseURL = URL(string: "https://api.upstage.ai/v2")!

    init(apiKeyStore: any UpstageAPIKeyStoring) {
        agent = StudioAgentCatalog.configuration(for: .applicantIdentity)
        self.apiKeyStore = apiKeyStore
    }

    var providerLabel: String {
        guard let agent else { return "Upstage Studio 신원 검증 Agent 설정 필요" }
        return "Upstage Studio · \(agent.displayName)"
    }

    var hasAPIKey: Bool {
        (try? apiKeyStore.readAPIKey())?.isEmpty == false
    }

    func analyze(url: URL) async throws -> ApplicantIdentityExtraction {
        guard let agent else { throw ApplicantIdentityAgentError.missingAgent }
        guard let apiKey = try apiKeyStore.readAPIKey(), !apiKey.isEmpty else {
            throw ApplicantIdentityAgentError.missingAPIKey
        }

        let fileID = try await upload(url: url, apiKey: apiKey)
        do {
            let jobID = try await createJob(fileID: fileID, agent: agent, apiKey: apiKey)
            let output = try await waitForJob(id: jobID, apiKey: apiKey)
            let identity = try decode(output: output)
            try? await deleteUploadedFile(id: fileID, apiKey: apiKey)
            guard !identity.isEmpty else { throw ApplicantIdentityAgentError.invalidResponse }
            return identity
        } catch {
            try? await deleteUploadedFile(id: fileID, apiKey: apiKey)
            throw error
        }
    }

    private func upload(url: URL, apiKey: String) async throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let file = try? Data(contentsOf: url), !file.isEmpty else {
            throw ApplicantIdentityAgentError.unreadableFile(url.lastPathComponent)
        }

        let boundary = "GradCheckIdentity-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: "files"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(file: file, filename: url.lastPathComponent, boundary: boundary)
        let data = try await requestData(request)
        return try JSONDecoder().decode(UploadedIdentityFile.self, from: data).id
    }

    private func createJob(fileID: String, agent: StudioAgentConfiguration, apiKey: String) async throws -> String {
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
        return try JSONDecoder().decode(IdentityAgentJob.self, from: data).id
    }

    private func waitForJob(id: String, apiKey: String) async throws -> String {
        for _ in 0..<45 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            var components = URLComponents(url: baseURL.appending(path: "responses/\(id)"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "include[]", value: "last")]
            guard let url = components?.url else { throw ApplicantIdentityAgentError.invalidResponse }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 60
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let data = try await requestData(request)
            let job = try JSONDecoder().decode(IdentityAgentJob.self, from: data)
            if job.status == "completed",
               let text = job.outputText ?? job.output?.first?.content?.first?.text {
                return text
            }
            if job.status == "failed" || job.status == "cancelled" {
                throw ApplicantIdentityAgentError.api(status: 500, detail: "Studio Agent 실행이 실패했습니다.")
            }
        }
        throw ApplicantIdentityAgentError.api(status: 408, detail: "Studio Agent 응답 시간이 초과되었습니다.")
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
            throw ApplicantIdentityAgentError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            let detail = String((String(data: data, encoding: .utf8) ?? "요청이 거절되었습니다.").prefix(240))
            throw ApplicantIdentityAgentError.api(status: response.statusCode, detail: detail)
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

    private func decode(output: String) throws -> ApplicantIdentityExtraction {
        let json = normalizedJSON(output)
        guard let data = json.data(using: .utf8) else { throw ApplicantIdentityAgentError.invalidResponse }
        do {
            let payload = try JSONDecoder().decode(IdentityAgentPayload.self, from: data)
            return ApplicantIdentityExtraction(
                fullName: payload.fullName,
                email: payload.email,
                namePage: payload.namePage,
                emailPage: payload.emailPage,
                nameEvidence: payload.nameEvidence ?? payload.fullName,
                emailEvidence: payload.emailEvidence ?? payload.email
            )
        } catch {
            throw ApplicantIdentityAgentError.invalidResponse
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
}

private struct UploadedIdentityFile: Decodable { let id: String }

private struct IdentityAgentJob: Decodable {
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

/// Supports common field names so the Extract schema can stay simple while the
/// app continues to work if it uses `name` instead of `full_name`.
private struct IdentityAgentPayload: Decodable {
    private enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
        case applicantName = "applicant_name"
        case legalName = "legal_name"
        case englishName = "english_name"
        case email
        case emailAddress = "email_address"
        case applicantEmail = "applicant_email"
        case namePage = "name_page"
        case emailPage = "email_page"
        case sourcePage = "source_page"
        case page
        case nameEvidence = "name_evidence"
        case emailEvidence = "email_evidence"
        case evidence
    }

    let fullName: String?
    let email: String?
    let namePage: Int?
    let emailPage: Int?
    let nameEvidence: String?
    let emailEvidence: String?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fullName = Self.string([.fullName, .name, .applicantName, .legalName, .englishName], from: values)
        email = Self.string([.email, .emailAddress, .applicantEmail], from: values)
        let sharedPage = Self.page([.sourcePage, .page], from: values)
        namePage = Self.page([.namePage], from: values) ?? sharedPage
        emailPage = Self.page([.emailPage], from: values) ?? sharedPage
        nameEvidence = Self.string([.nameEvidence, .evidence], from: values)
        emailEvidence = Self.string([.emailEvidence, .evidence], from: values)
    }

    private static func string(_ keys: [CodingKeys], from values: KeyedDecodingContainer<CodingKeys>) -> String? {
        for key in keys {
            if let value = try? values.decode(String.self, forKey: key) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty, normalized.lowercased() != "null", normalized.lowercased() != "not_stated" {
                    return normalized
                }
            }
        }
        return nil
    }

    private static func page(_ keys: [CodingKeys], from values: KeyedDecodingContainer<CodingKeys>) -> Int? {
        for key in keys {
            if let value = try? values.decode(Int.self, forKey: key) { return value }
            if let value = try? values.decode(String.self, forKey: key),
               let range = value.range(of: #"\d+"#, options: .regularExpression) {
                return Int(value[range])
            }
        }
        return nil
    }
}
