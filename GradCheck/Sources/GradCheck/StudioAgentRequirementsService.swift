import Foundation
import Security

/// Agent IDs and configuration versions live in one catalog. Add future Agents
/// here rather than scattering IDs throughout the UI and analysis code.
enum StudioAgentPurpose: String, Sendable {
    case graduateRequirements
    case applicantIdentity
    case submissionDocumentValidation
    case applicationPackageAudit
}

struct StudioAgentConfiguration: Sendable, Equatable {
    let purpose: StudioAgentPurpose
    let agentID: String
    let configID: String
    let displayName: String
}

enum StudioAgentCatalog {
    static func configuration(for purpose: StudioAgentPurpose) -> StudioAgentConfiguration? {
        switch purpose {
        case .graduateRequirements:
            StudioAgentConfiguration(
                purpose: .graduateRequirements,
                agentID: "agt_9yuURkpPwpUh6UzJEp5dCA",
                configID: "8",
                displayName: "미국 대학원 모집요강 Agent"
            )
        case .applicantIdentity:
            StudioAgentConfiguration(
                purpose: .applicantIdentity,
                agentID: "agt_3cdAfCvWFyKwDeS6tCw9vJ",
                configID: "3",
                displayName: "지원자 신원 검증 Agent"
            )
        case .submissionDocumentValidation:
            StudioAgentConfiguration(
                purpose: .submissionDocumentValidation,
                agentID: "agt_bmpcUYqLfdAfzbZy7cDQ48",
                configID: "1",
                displayName: "제출 서류 검증 Agent"
            )
        case .applicationPackageAudit:
            // Add its Agent ID and Config ID here when the package-audit Agent exists.
            nil
        }
    }
}

enum UpstageCredentialError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Upstage API 키를 Keychain에서 읽거나 저장하지 못했어요."
    }
}

protocol UpstageAPIKeyStoring: Sendable {
    func readAPIKey() throws -> String?
    func saveAPIKey(_ value: String) throws
    func removeAPIKey() throws
}

/// Never persist a secret in UserDefaults, the Xcode project, or app data.
/// Keychain is encrypted and bound to the current macOS user account.
final class KeychainUpstageAPIKeyStore: @unchecked Sendable, UpstageAPIKeyStoring {
    private let service = "com.jb.GradCheck"
    private let account = "upstage-api-key"

    func readAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { throw UpstageCredentialError.unavailable }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func saveAPIKey(_ value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let data = normalized.data(using: .utf8)
        else {
            try removeAPIKey()
            return
        }

        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var add = lookup
            add[kSecValueData as String] = data
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
                throw UpstageCredentialError.unavailable
            }
        } else if status != errSecSuccess {
            throw UpstageCredentialError.unavailable
        }
    }

    func removeAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UpstageCredentialError.unavailable
        }
    }
}

/// An Xcode scheme variable is convenient for a one-off developer test. A
/// Keychain item is the normal app path; the environment deliberately wins.
struct EnvironmentThenKeychainAPIKeyStore: @unchecked Sendable, UpstageAPIKeyStoring {
    let environment: [String: String]
    let keychain: any UpstageAPIKeyStoring

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        keychain: any UpstageAPIKeyStoring = KeychainUpstageAPIKeyStore()
    ) {
        self.environment = environment
        self.keychain = keychain
    }

    func readAPIKey() throws -> String? {
        let key = environment["UPSTAGE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty ? try keychain.readAPIKey() : key
    }

    func saveAPIKey(_ value: String) throws {
        try keychain.saveAPIKey(value)
    }

    func removeAPIKey() throws {
        try keychain.removeAPIKey()
    }
}

enum StudioAgentRequirementsError: LocalizedError {
    case missingAgent
    case missingAPIKey
    case unreadableFile(String)
    case unsupportedFile(String)
    case invalidResponse
    case api(status: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .missingAgent:
            "모집요강 분석 Agent 설정을 찾지 못했어요."
        case .missingAPIKey:
            "Upstage API 키를 먼저 입력해 주세요."
        case let .unreadableFile(name):
            "\(name) 파일을 읽지 못했습니다."
        case let .unsupportedFile(name):
            "\(name)은 현재 모집요강 Agent에 보낼 수 없습니다. PDF를 사용해 주세요."
        case .invalidResponse:
            "Agent 결과를 모집요강 체크리스트로 읽지 못했어요."
        case let .api(status, detail):
            "Upstage Agent 오류 (HTTP \(status)): \(detail)"
        }
    }
}

protocol GraduateRequirementsAnalyzing: Sendable {
    var providerLabel: String { get }
    var hasAPIKey: Bool { get }
    func analyze(urls: [URL]) async throws -> [RequirementItem]
}

struct UnavailableGraduateRequirementsAnalyzer: GraduateRequirementsAnalyzing {
    var providerLabel: String { "Upstage Studio Agent 설정 필요" }
    var hasAPIKey: Bool { false }

    func analyze(urls: [URL]) async throws -> [RequirementItem] {
        throw StudioAgentRequirementsError.missingAPIKey
    }
}

/// Executes the user's Upstage Studio Agent. Each uploaded official document is
/// one job, which keeps its source filename and page evidence intact.
struct StudioAgentRequirementsService: GraduateRequirementsAnalyzing {
    private let agent: StudioAgentConfiguration?
    private let apiKeyStore: any UpstageAPIKeyStoring
    private let baseURL = URL(string: "https://api.upstage.ai/v2")!

    init(
        purpose: StudioAgentPurpose = .graduateRequirements,
        apiKeyStore: any UpstageAPIKeyStoring
    ) {
        agent = StudioAgentCatalog.configuration(for: purpose)
        self.apiKeyStore = apiKeyStore
    }

    var providerLabel: String {
        guard let agent else { return "Upstage Studio Agent 설정 필요" }
        return ""
    }

    var hasAPIKey: Bool {
        (try? apiKeyStore.readAPIKey())?.isEmpty == false
    }

    func analyze(urls: [URL]) async throws -> [RequirementItem] {
        guard let agent else { throw StudioAgentRequirementsError.missingAgent }
        guard let key = try apiKeyStore.readAPIKey(), !key.isEmpty else {
            throw StudioAgentRequirementsError.missingAPIKey
        }

        var allItems: [RequirementItem] = []
        for url in urls {
            try Task.checkCancellation()
            let fileID = try await upload(url: url, apiKey: key)
            do {
                let jobID = try await createJob(fileID: fileID, agent: agent, apiKey: key)
                let output = try await waitForJob(id: jobID, apiKey: key)
                let result = try decode(output: output)
                // Files persist in the Agent API until deletion. Results have
                // already been received at this point, so remove the source
                // document even when it is only a public admissions guide.
                try? await deleteUploadedFile(id: fileID, apiKey: key)
                allItems.append(contentsOf: map(result, sourceName: url.lastPathComponent))
            } catch {
                // Do not leave a partially processed upload behind on failure
                // or cancellation. Preserve the original processing error.
                try? await deleteUploadedFile(id: fileID, apiKey: key)
                throw error
            }
        }

        guard !allItems.isEmpty else { throw StudioAgentRequirementsError.invalidResponse }
        return deduplicated(allItems)
    }

    private func upload(url: URL, apiKey: String) async throws -> String {
        guard url.pathExtension.lowercased() == "pdf" else {
            throw StudioAgentRequirementsError.unsupportedFile(url.lastPathComponent)
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let file = try? Data(contentsOf: url), !file.isEmpty else {
            throw StudioAgentRequirementsError.unreadableFile(url.lastPathComponent)
        }

        let boundary = "GradCheck-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: "files"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(file: file, filename: url.lastPathComponent, boundary: boundary)
        let data = try await requestData(request)
        return try JSONDecoder().decode(UploadedFile.self, from: data).id
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
        return try JSONDecoder().decode(AgentJob.self, from: data).id
    }

    private func deleteUploadedFile(id: String, apiKey: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "files/\(id)"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try await requestData(request)
    }

    private func waitForJob(id: String, apiKey: String) async throws -> String {
        for _ in 0..<45 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            var components = URLComponents(
                url: baseURL.appending(path: "responses/\(id)"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "include[]", value: "last")]
            guard let url = components?.url else { throw StudioAgentRequirementsError.invalidResponse }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 60
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let data = try await requestData(request)
            let job = try JSONDecoder().decode(AgentJob.self, from: data)
            if job.status == "completed",
               let text = job.outputText ?? job.output?.first?.content?.first?.text {
                return text
            }
            if job.status == "failed" || job.status == "cancelled" {
                throw StudioAgentRequirementsError.api(status: 500, detail: "Studio Agent 실행이 실패했습니다.")
            }
        }
        throw StudioAgentRequirementsError.api(status: 408, detail: "Studio Agent 응답 시간이 초과되었습니다.")
    }

    private func requestData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw StudioAgentRequirementsError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            let raw = String(data: data, encoding: .utf8) ?? "요청이 거절되었습니다."
            throw StudioAgentRequirementsError.api(
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
        append("Content-Type: application/pdf\r\n\r\n")
        body.append(file)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func decode(output: String) throws -> AgentRequirementsResult {
        guard let data = normalizedJSON(output).data(using: .utf8) else {
            throw StudioAgentRequirementsError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(AgentRequirementsResult.self, from: data)
        } catch {
            throw StudioAgentRequirementsError.invalidResponse
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

    private func map(_ result: AgentRequirementsResult, sourceName: String) -> [RequirementItem] {
        result.requirementItems.compactMap { item in
            guard let necessity = necessity(for: item.requirementLevel),
                  !item.requirementName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            let submissionMethod = submissionMethod(for: item)
            let relatedDocumentType = documentType(
                for: item.category,
                title: item.requirementName,
                details: item.details
            ) ?? (submissionMethod.requiresFileUpload ? .supportingDocument : nil)
            return RequirementItem(
                title: item.requirementName,
                detail: item.details.isEmpty ? "공식 모집요강에서 확인된 제출 요건" : item.details,
                scope: result.sourceScope.isUniversityWide ? .university : .program,
                status: necessity == .conditional ? .humanReview : .ready,
                sourceName: sourceName,
                page: firstPage(in: item.sourcePage),
                relatedDocumentType: relatedDocumentType,
                necessity: necessity,
                requiredCount: recommendationCount(
                    in: "\(item.requirementName) \(item.details)",
                    documentType: relatedDocumentType
                ),
                submissionMethod: submissionMethod
            )
        }
    }

    private func documentType(for category: String, title: String, details: String) -> DocumentType? {
        switch normalizedAgentValue(category) {
        case "recommendation", "recommendation_letter", "추천서", "추천인": return .recommendation
        case "statement", "personal_statement", "sop", "학업계획서", "자기소개서", "개인진술서", "에세이", "에세이질문": return .sop
        case "cv_resume", "cv", "resume", "이력서", "경력기술서": return .cv
        case "transcript", "academic_record", "성적표", "성적증명서", "학업성적표": return .transcript
        case "english_test", "english_score", "toefl_ielts", "영어성적", "영어시험", "토플", "아이엘츠": return .englishScore
        case "gre", "gmat", "gre_score", "gre성적", "gmat성적": return .greScore
        case "portfolio", "포트폴리오": return .portfolio
        case "writing_sample", "작문샘플", "글쓰기샘플": return .writingSample
        case "research_proposal", "research_plan", "연구계획서", "연구제안서": return .researchProposal
        case "degree_certificate", "diploma", "학위증명서", "졸업증명서": return .degreeCertificate
        case "passport_visa", "passport", "visa", "여권", "비자", "여권비자": return .passportVisa
        case "financial_proof", "financial_document", "bank_statement", "sponsorship", "재정증명", "경비지변", "경비지변서": return .financialProof
        case "application_form", "application_document", "entry_form", "입학원서", "지원서", "지정양식": return .applicationForm
        case "photo", "identity_photo", "photograph", "사진", "증명사진": return .identityPhoto
        case "residency_document", "residence_certificate", "certificate_of_eligibility", "체류자격", "재류자격": return .residencyDocument
        case "translation", "certified_translation", "번역문", "공인번역": return .certifiedTranslation
        default:
            return documentTypeFromRequirementText("\(title) \(details)")
        }
    }

    private func documentTypeFromRequirementText(_ text: String) -> DocumentType? {
        let value = normalizedAgentValue(text)
        if containsAny(value, ["졸업증명", "학위증명", "degreecertificate", "diploma", "graduationcertificate"]) { return .degreeCertificate }
        if containsAny(value, ["성적증명", "성적표", "transcript", "academicrecord"]) { return .transcript }
        if containsAny(value, ["경비지변", "재정증명", "financialproof", "bankstatement", "sponsor"]) { return .financialProof }
        if containsAny(value, ["입학원서", "지원서", "applicationform", "designatedform", "prescribedform"]) { return .applicationForm }
        if containsAny(value, ["증명사진", "사진", "photo", "photograph"]) { return .identityPhoto }
        if containsAny(value, ["재류자격", "체류자격", "residencecertificate", "certificateofeligibility"]) { return .residencyDocument }
        if containsAny(value, ["번역문", "translation", "translateddocument"]) { return .certifiedTranslation }
        if containsAny(value, ["passport", "visa", "여권", "비자"]) { return .passportVisa }
        return nil
    }

    private func submissionMethod(for item: AgentRequirementsResult.Item) -> SubmissionMethod {
        if let method = SubmissionMethod(agentValue: item.submissionMethod) {
            return method
        }

        let title = normalizedAgentValue(item.requirementName)
        let content = normalizedAgentValue("\(item.requirementName) \(item.details)")
        if containsAny(title, ["수수료", "applicationfee", "마감일", "면접", "원본제출", "우편제출", "서류제출"]) {
            return containsAny(title, ["원본제출", "우편제출", "서류제출"])
                ? .physicalDelivery
                : .portalAction
        }
        if documentType(for: item.category, title: item.requirementName, details: item.details) != nil {
            return .uploadFile
        }
        if containsAny(content, ["증명서", "서류", "사진", "번역문", "양식", "certificate", "document", "photo", "translation", "form"]) {
            return .uploadFile
        }
        if containsAny(content, ["original", "mail", "postal", "우편", "지참", "원본제출", "직접제출"]) {
            return .physicalDelivery
        }
        return .portalAction
    }

    private func containsAny(_ value: String, _ terms: [String]) -> Bool {
        terms.contains { value.contains(normalizedAgentValue($0)) }
    }

    private func necessity(for value: String) -> RequirementNecessity? {
        switch normalizedAgentValue(value) {
        case "not_stated", "notstated", "명시되지않음", "미기재", "미명시":
            nil
        case "conditional", "선택", "조건부", "해당시", "필요시", "경우에따라":
            .conditional
        default:
            // Both `required` and `usually_required` are presented as a
            // required checklist item. The wording remains in `details`.
            .required
        }
    }

    private func firstPage(in value: String?) -> Int? {
        guard let value,
              let match = value.range(of: #"\d+"#, options: .regularExpression)
        else { return nil }
        return Int(value[match])
    }

    private func recommendationCount(in text: String, documentType: DocumentType?) -> Int? {
        guard documentType == .recommendation else { return nil }
        guard let match = text.range(
            of: #"\b([1-9]|10)\s*(?:letters?|recommendations?|references?|부|통)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let digits = text[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits)
    }

    private func deduplicated(_ items: [RequirementItem]) -> [RequirementItem] {
        var keys = Set<String>()
        return items.filter { item in
            let key = [item.sourceName, item.scope.rawValue, item.title.lowercased()]
                .joined(separator: "|")
            return keys.insert(key).inserted
        }
    }
}

private extension String? {
    var isUniversityWide: Bool {
        switch normalizedAgentValue(self ?? "") {
        case "institution_general", "university", "university_general", "학교공통", "대학공통", "대학원공통", "기관공통":
            true
        default:
            false
        }
    }
}

private extension SubmissionMethod {
    init?(agentValue: String?) {
        switch normalizedAgentValue(agentValue ?? "") {
        case "upload_file", "upload", "file", "document", "파일업로드", "파일":
            self = .uploadFile
        case "portal_action", "portal", "online_action", "online", "direct_check", "온라인절차", "포털입력", "직접확인":
            self = .portalAction
        case "physical_delivery", "physical", "mail", "postal", "original_submission", "우편제출", "원본제출", "직접제출":
            self = .physicalDelivery
        case "informational", "information", "안내":
            self = .informational
        default:
            return nil
        }
    }
}

private func normalizedAgentValue(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "\n", with: "")
}

private struct UploadedFile: Decodable { let id: String }

private struct AgentJob: Decodable {
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

private struct AgentRequirementsResult: Decodable {
    struct Item: Decodable {
        let requirementName: String
        let category: String
        let requirementLevel: String
        let submissionMethod: String?
        let details: String
        let sourcePage: String?

        enum CodingKeys: String, CodingKey {
            case category, details
            case requirementName = "requirement_name"
            case requirementLevel = "requirement_level"
            case submissionMethod = "submission_method"
            case sourcePage = "source_page"
        }
    }

    let sourceScope: String?
    let requirementItems: [Item]

    enum CodingKeys: String, CodingKey {
        case sourceScope = "source_scope"
        case requirementItems = "requirement_items"
    }
}
