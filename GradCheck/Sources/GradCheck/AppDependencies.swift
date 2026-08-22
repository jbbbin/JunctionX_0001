import Foundation

protocol RequirementsAnalyzing {
    func extract(from document: ExtractedDocument, sourceName: String) -> [RequirementItem]
}

extension RequirementExtractor: RequirementsAnalyzing {}

protocol ApplicationAuditing {
    func findings(
        for workspace: ApplicationWorkspace,
        documents: [DocumentItem],
        extracted: [UUID: ExtractedDocument],
        requirements: [RequirementItem],
        identityExtractions: [UUID: ApplicantIdentityExtraction]
    ) -> [AuditFinding]
}

extension AuditEngine: ApplicationAuditing {}

struct AppDependencies {
    var documentAnalyzer: any DocumentAnalyzing
    var requirementsAnalyzer: any RequirementsAnalyzing
    var graduateRequirementsAnalyzer: any GraduateRequirementsAnalyzing = UnavailableGraduateRequirementsAnalyzer()
    var applicantIdentityAnalyzer: any ApplicantIdentityAnalyzing = UnavailableApplicantIdentityAnalyzer()
    var apiKeyStore: any UpstageAPIKeyStoring = EnvironmentThenKeychainAPIKeyStore()
    var auditor: any ApplicationAuditing
    var repository: any ApplicationRepository

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loadSavedState: Bool = true
    ) -> AppDependencies {
        let apiKeyStore = EnvironmentThenKeychainAPIKeyStore(environment: environment)
        return AppDependencies(
            documentAnalyzer: DocumentPipeline(environment: environment),
            requirementsAnalyzer: RequirementExtractor(),
            graduateRequirementsAnalyzer: StudioAgentRequirementsService(
                purpose: .graduateRequirements,
                apiKeyStore: apiKeyStore
            ),
            applicantIdentityAnalyzer: ApplicantIdentityAgentService(apiKeyStore: apiKeyStore),
            apiKeyStore: apiKeyStore,
            auditor: AuditEngine(),
            repository: loadSavedState
                ? UserDefaultsApplicationRepository()
                : TransientApplicationRepository()
        )
    }
}
