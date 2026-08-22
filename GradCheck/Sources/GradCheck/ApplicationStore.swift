import Foundation

struct WorkspaceDraft: Equatable {
    var school: String
    var program: String
    var degree: String
    var intake: String
    var applicantName: String

    var normalized: WorkspaceDraft {
        WorkspaceDraft(
            school: school.trimmingCharacters(in: .whitespacesAndNewlines),
            program: program.trimmingCharacters(in: .whitespacesAndNewlines),
            degree: degree.trimmingCharacters(in: .whitespacesAndNewlines),
            intake: intake.trimmingCharacters(in: .whitespacesAndNewlines),
            applicantName: applicantName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct RequirementAnalysisResult {
    var documents: [DocumentItem]
    var requirements: [RequirementItem]
    var extractions: [UUID: ExtractedDocument]

    var requiredDocumentTypes: [DocumentType] {
        Self.requiredTypes(from: requirements)
    }

    static func requiredTypes(from requirements: [RequirementItem]) -> [DocumentType] {
        var seen = Set<DocumentType>()
        return requirements
            .filter { $0.effectiveNecessity != .informational }
            .compactMap(\.relatedDocumentType)
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter { seen.insert($0).inserted }
    }

    static func requiredCount(for type: DocumentType, in requirements: [RequirementItem]) -> Int {
        requirements
            .filter {
                $0.relatedDocumentType == type && $0.effectiveNecessity != .informational
            }
            .map { max($0.requiredCount ?? 1, 1) }
            .max() ?? 0
    }
}

struct ApplicationSession: Identifiable {
    var workspace: ApplicationWorkspace
    var documents: [DocumentItem]
    var findings: [AuditFinding]
    var requirements: [RequirementItem]
    var history: [AuditHistoryEntry]
    var extractedDocuments: [UUID: ExtractedDocument]
    /// Agent-derived personal data is intentionally in-memory only and is not
    /// written to ApplicationSessionSnapshot.
    var identityExtractions: [UUID: ApplicantIdentityExtraction] = [:]

    var id: UUID { workspace.id }

    var requiredDocumentTypes: [DocumentType] {
        RequirementAnalysisResult.requiredTypes(from: requirements)
    }

    var requiredDocumentCount: Int {
        requiredDocumentTypes.reduce(0) { $0 + requiredCount(for: $1) }
    }

    var readyDocumentCount: Int {
        requiredDocumentTypes.reduce(0) { $0 + readyCount(for: $1) }
    }

    func requiredCount(for type: DocumentType) -> Int {
        RequirementAnalysisResult.requiredCount(for: type, in: requirements)
    }

    func readyCount(for type: DocumentType) -> Int {
        min(
            documents.filter { $0.type == type && $0.processingStatus == .ready }.count,
            requiredCount(for: type)
        )
    }

    var requirementDocuments: [DocumentItem] {
        documents.filter { $0.type == .requirements }
    }
}

struct WorkspaceOverviewItem: Identifiable {
    let workspace: ApplicationWorkspace
    let requirementCount: Int
    let requiredDocumentCount: Int
    let readyDocumentCount: Int
    let blockedCount: Int
    let reviewCount: Int
    let readyFindingCount: Int
    let hasCurrentAudit: Bool

    var id: UUID { workspace.id }
    var missingDocumentCount: Int { max(requiredDocumentCount - readyDocumentCount, 0) }
}

struct PortfolioFindingItem: Identifiable {
    let workspaceID: UUID
    let workspaceTitle: String
    let finding: AuditFinding

    var id: UUID { finding.id }
}

struct ApplicationPortfolio {
    var sessions: [ApplicationSession]
    var selectedWorkspaceID: UUID

    var selectedIndex: Int? {
        sessions.firstIndex { $0.id == selectedWorkspaceID }
    }

    var selectedSession: ApplicationSession? {
        guard let selectedIndex else { return nil }
        return sessions[selectedIndex]
    }

    var workspaces: [ApplicationWorkspace] {
        sessions.map(\.workspace)
    }

    mutating func select(_ id: UUID) -> Bool {
        guard sessions.contains(where: { $0.id == id }) else { return false }
        selectedWorkspaceID = id
        return true
    }

    mutating func upsert(_ session: ApplicationSession, select: Bool) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        if select { selectedWorkspaceID = session.id }
    }
}

struct ApplicationPortfolioSnapshot: Codable {
    var sessions: [ApplicationSessionSnapshot]
    var selectedWorkspaceID: UUID
}

struct ApplicationSessionSnapshot: Codable {
    var workspace: ApplicationWorkspace
    var requirementDocuments: [DocumentItem]
    var requirements: [RequirementItem]
    var history: [AuditHistoryEntry]
    var sampleRevisionApplied: Bool
    var currentAuditValid: Bool
}

protocol ApplicationRepository {
    func load() -> ApplicationPortfolioSnapshot?
    func save(_ snapshot: ApplicationPortfolioSnapshot)
}

struct UserDefaultsApplicationRepository: ApplicationRepository {
    private let defaults: UserDefaults
    private let storageKey: String
    private let legacyStorageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "GradCheck.portfolio.v3",
        legacyStorageKey: String = "GradCheck.workspace.v2"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.legacyStorageKey = legacyStorageKey
    }

    func load() -> ApplicationPortfolioSnapshot? {
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(ApplicationPortfolioSnapshot.self, from: data) {
            return snapshot
        }
        guard let data = defaults.data(forKey: legacyStorageKey),
              let legacy = try? JSONDecoder().decode(LegacyWorkspaceSnapshot.self, from: data) else {
            return nil
        }
        let workspace = ApplicationWorkspace(
            id: legacy.workspaceID,
            school: legacy.school,
            program: legacy.program,
            degree: legacy.degree,
            intake: legacy.intake,
            applicantName: "",
            status: legacy.currentAuditValid == true ? .needsReview : .preparing,
            createdAt: legacy.createdAt,
            lastAuditedAt: legacy.lastAuditedAt,
            isSample: legacy.isSample
        )
        let snapshot = ApplicationPortfolioSnapshot(
            sessions: [
                ApplicationSessionSnapshot(
                    workspace: workspace,
                    requirementDocuments: [],
                    requirements: legacy.isSample ? DemoData.requirements : [],
                    history: legacy.history,
                    sampleRevisionApplied: legacy.sampleRevisionApplied == true,
                    currentAuditValid: legacy.currentAuditValid == true
                )
            ],
            selectedWorkspaceID: workspace.id
        )
        save(snapshot)
        return snapshot
    }

    func save(_ snapshot: ApplicationPortfolioSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct TransientApplicationRepository: ApplicationRepository {
    func load() -> ApplicationPortfolioSnapshot? { nil }
    func save(_ snapshot: ApplicationPortfolioSnapshot) {}
}

private struct LegacyWorkspaceSnapshot: Codable {
    var workspaceID: UUID
    var school: String
    var program: String
    var degree: String
    var intake: String
    var createdAt: Date
    var lastAuditedAt: Date?
    var isSample: Bool
    var sampleRevisionApplied: Bool?
    var hadUserDocuments: Bool?
    var currentAuditValid: Bool?
    var history: [AuditHistoryEntry]
}
