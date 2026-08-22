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
        requirements: [RequirementItem]
    ) -> [AuditFinding]
}

extension AuditEngine: ApplicationAuditing {}

struct AppDependencies {
    var documentAnalyzer: any DocumentAnalyzing
    var requirementsAnalyzer: any RequirementsAnalyzing
    var auditor: any ApplicationAuditing
    var repository: any ApplicationRepository

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loadSavedState: Bool = true
    ) -> AppDependencies {
        AppDependencies(
            documentAnalyzer: DocumentPipeline(environment: environment),
            requirementsAnalyzer: RequirementExtractor(),
            auditor: AuditEngine(),
            repository: loadSavedState
                ? UserDefaultsApplicationRepository()
                : TransientApplicationRepository()
        )
    }
}
