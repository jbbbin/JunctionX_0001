import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var destination: AppDestination = .overview
    @Published var workspace: ApplicationWorkspace
    @Published var documents: [DocumentItem]
    @Published var findings: [AuditFinding]
    @Published var requirements: [RequirementItem]
    @Published var history: [AuditHistoryEntry]
    @Published var selectedFindingID: UUID?
    @Published var isAuditing = false
    @Published private(set) var isImporting = false
    @Published var auditPhase: AuditPhase = .reading
    @Published var showNewWorkspace = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let pipeline: DocumentPipeline
    private let engine = AuditEngine()
    private var extractedDocuments: [UUID: ExtractedDocument] = [:]
    private var importTask: Task<Void, Never>?
    private var activeImportID: UUID?
    private var auditTask: Task<Void, Never>?
    private var activeAuditID: UUID?
    private let storageKey = "GradCheck.workspace.v2"
    private let legacyStorageKey = "GradCheck.workspace.v1"

    init(loadSavedState: Bool = true, environment: [String: String] = ProcessInfo.processInfo.environment) {
        pipeline = DocumentPipeline(environment: environment)

        let snapshot: SafeSnapshot? = loadSavedState ? Self.loadSafeSnapshot(
            storageKey: storageKey,
            legacyStorageKey: legacyStorageKey
        ) : nil

        if let snapshot, snapshot.isSample, snapshot.hadUserDocuments != true {
            var restoredWorkspace = DemoData.workspace
            var restoredDocuments = DemoData.documents
            if snapshot.sampleRevisionApplied == true {
                restoredDocuments.removeAll { $0.type == .sop }
                restoredDocuments.append(DemoData.revisedSOPDocument())
                let current = snapshot.currentAuditValid == true
                restoredWorkspace.lastAuditedAt = current ? snapshot.lastAuditedAt : DemoData.workspace.lastAuditedAt
                restoredWorkspace.status = current ? .needsReview : .preparing
                let extractions = DemoData.extractions(for: restoredDocuments)
                findings = current
                    ? AuditEngine().findings(
                        for: restoredWorkspace,
                        documents: restoredDocuments,
                        extracted: extractions,
                        requirements: DemoData.requirements
                    )
                    : []
            } else {
                findings = DemoData.findings
            }
            workspace = restoredWorkspace
            documents = restoredDocuments
            requirements = DemoData.requirements
            history = snapshot.history.isEmpty ? Self.demoHistory : snapshot.history
        } else if let snapshot {
            let restoredWorkspace = ApplicationWorkspace(
                id: snapshot.workspaceID,
                school: snapshot.school,
                program: snapshot.program,
                degree: snapshot.degree,
                intake: snapshot.intake,
                applicantName: "",
                status: .preparing,
                createdAt: snapshot.createdAt,
                lastAuditedAt: nil,
                isSample: false
            )
            workspace = restoredWorkspace
            documents = []
            findings = AuditEngine().findings(for: restoredWorkspace, documents: [], extracted: [:])
            requirements = []
            history = snapshot.history
        } else {
            workspace = DemoData.workspace
            documents = DemoData.documents
            findings = DemoData.findings
            requirements = DemoData.requirements
            history = Self.demoHistory
        }
        if workspace.isSample { extractedDocuments = DemoData.extractions(for: documents) }
        selectedFindingID = findings.first(where: { $0.status == .blocked })?.id ?? findings.first?.id
    }

    var providerLabel: String { pipeline.providerLabel }
    var isUpstageConnected: Bool { pipeline.isUpstageConnected }
    var hasCurrentAudit: Bool {
        workspace.status != .preparing && !findings.isEmpty && workspace.lastAuditedAt != nil
    }
    var hasUserWorkspaceData: Bool {
        !workspace.isSample || documents.contains { !$0.isSample }
    }

    var blockedCount: Int { findings.filter { $0.status == .blocked }.count }
    var humanReviewCount: Int { findings.filter { $0.status == .humanReview }.count }
    var readyCount: Int { findings.filter { $0.status == .ready }.count }

    var coreDocumentCount: Int {
        Set(documents.filter { $0.type.isCore && $0.processingStatus == .ready }.map(\.type)).count
    }

    var selectedFinding: AuditFinding? {
        get { findings.first(where: { $0.id == selectedFindingID }) }
        set { selectedFindingID = newValue?.id }
    }

    func loadDemo() {
        cancelActiveImport()
        cancelActiveAudit()
        workspace = DemoData.workspace
        documents = DemoData.documents
        findings = DemoData.findings
        requirements = DemoData.requirements
        history = [
            AuditHistoryEntry(
                date: .now,
                blockedCount: 2,
                reviewCount: 2,
                readyCount: 4,
                note: "샘플 지원 패키지 불러오기"
            )
        ]
        extractedDocuments = DemoData.extractions(for: documents)
        selectedFindingID = findings.first(where: { $0.status == .blocked })?.id
        destination = .overview
        successMessage = "샘플 지원서를 불러왔어요."
        persist()
        dismissSuccessMessageLater()
    }

    func createWorkspace(
        school: String,
        program: String,
        degree: String,
        intake: String,
        applicantName: String
    ) {
        cancelActiveImport()
        cancelActiveAudit()
        workspace = ApplicationWorkspace(
            school: school.trimmingCharacters(in: .whitespacesAndNewlines),
            program: program.trimmingCharacters(in: .whitespacesAndNewlines),
            degree: degree,
            intake: intake.trimmingCharacters(in: .whitespacesAndNewlines),
            applicantName: applicantName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        documents = []
        findings = engine.findings(for: workspace, documents: [], extracted: [:])
        requirements = []
        history = []
        extractedDocuments = [:]
        selectedFindingID = findings.first?.id
        destination = .documents
        showNewWorkspace = false
        persist()
    }

    func importDocuments(_ urls: [URL], as requestedType: DocumentType? = nil) {
        guard !urls.isEmpty, !isImporting else { return }
        cancelActiveAudit()
        errorMessage = nil
        isImporting = true
        let importID = UUID()
        activeImportID = importID
        let workspaceID = workspace.id

        importTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activeImportID == importID {
                    self.activeImportID = nil
                    self.isImporting = false
                    self.importTask = nil
                }
            }
            var importedTypes: [DocumentType] = []
            for url in urls {
                guard !Task.isCancelled, self.workspace.id == workspaceID, self.activeImportID == importID else { return }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }

                let provisionalType = requestedType ?? DocumentType.infer(from: url.lastPathComponent)
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                let item = DocumentItem(
                    type: provisionalType,
                    filename: url.lastPathComponent,
                    sizeInBytes: size,
                    processingStatus: .parsing,
                    isSample: false
                )
                self.documents.append(item)

                do {
                    let extraction = try await self.pipeline.extract(from: url)
                    guard !Task.isCancelled, self.workspace.id == workspaceID, self.activeImportID == importID else { return }
                    let finalType = requestedType ?? DocumentType.infer(
                        from: item.filename,
                        content: extraction.text
                    )
                    self.commitImportedDocument(item.id, as: finalType, extraction: extraction)
                    importedTypes.append(finalType)
                } catch {
                    guard self.workspace.id == workspaceID, self.activeImportID == importID else { return }
                    self.documents.removeAll { $0.id == item.id }
                    self.extractedDocuments.removeValue(forKey: item.id)
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }

            self.persist()
            if self.errorMessage == nil {
                let names = importedTypes.map(\.shortTitle).joined(separator: ", ")
                self.successMessage = "\(names) 파일을 분석했어요. 재검수를 실행해 주세요."
                self.dismissSuccessMessageLater()
            }
        }
    }

    func removeDocument(_ document: DocumentItem) {
        guard !isImporting else { return }
        cancelActiveAudit()
        documents.removeAll { $0.id == document.id }
        extractedDocuments.removeValue(forKey: document.id)
        if document.type == .requirements {
            requirements.removeAll { sameFilename($0.sourceName, document.filename) }
        }
        invalidateAudit()
        persist()
    }

    func applyRevisedSampleSOP() {
        guard workspace.isSample, !isImporting else { return }
        cancelActiveAudit()
        let oldIDs = documents.filter { $0.type == .sop }.map(\.id)
        documents.removeAll { $0.type == .sop }
        oldIDs.forEach { extractedDocuments.removeValue(forKey: $0) }

        let revised = DemoData.revisedSOPDocument()
        documents.append(revised)
        extractedDocuments[revised.id] = DemoData.extractions(for: [revised])[revised.id]
        invalidateAudit()
        successMessage = "수정본 샘플을 적용했어요. 재검수를 실행해 주세요."
        persist()
        dismissSuccessMessageLater()
    }

    func runAudit() {
        guard !isAuditing, !isImporting else { return }
        isAuditing = true
        errorMessage = nil
        auditPhase = .reading
        let auditID = UUID()
        activeAuditID = auditID
        let workspaceID = workspace.id
        let auditedWorkspace = workspace
        let auditedDocuments = documents
        let auditedExtractions = extractedDocuments
        let auditedRequirements = requirements

        auditTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activeAuditID == auditID {
                    self.activeAuditID = nil
                    self.auditTask = nil
                    self.isAuditing = false
                }
            }
            for phase in AuditPhase.allCases {
                guard !Task.isCancelled, self.workspace.id == workspaceID, self.activeAuditID == auditID else { return }
                self.auditPhase = phase
                do {
                    try await Task.sleep(for: .milliseconds(520))
                } catch {
                    return
                }
            }

            let auditedFindings = self.engine.findings(
                for: auditedWorkspace,
                documents: auditedDocuments,
                extracted: auditedExtractions,
                requirements: auditedRequirements
            )
            guard !Task.isCancelled, self.workspace.id == workspaceID, self.activeAuditID == auditID else { return }
            self.findings = auditedFindings
            self.workspace.lastAuditedAt = .now
            self.workspace.status = auditedFindings.contains(where: { $0.status != .ready }) ? .needsReview : .ready
            self.selectedFindingID = auditedFindings.first(where: { $0.status == .blocked })?.id
                ?? auditedFindings.first(where: { $0.status == .humanReview })?.id
                ?? auditedFindings.first?.id
            self.history.insert(
                AuditHistoryEntry(
                    blockedCount: self.blockedCount,
                    reviewCount: self.humanReviewCount,
                    readyCount: self.readyCount,
                    note: auditedDocuments.contains(where: { !$0.isSample }) ? "교체 문서 반영 후 재검수" : "지원 패키지 검수"
                ),
                at: 0
            )
            self.destination = .audit
            self.persist()

            if self.blockedCount == 0, self.humanReviewCount == 0 {
                self.successMessage = "업로드된 근거 기준으로 모든 항목을 확인했어요."
                self.dismissSuccessMessageLater()
            } else if self.blockedCount == 0 {
                self.successMessage = "BLOCKED는 없어요. HUMAN REVIEW 항목을 직접 확인해 주세요."
                self.dismissSuccessMessageLater()
            }
        }
    }

    func checklistMarkdown() -> String {
        let date = Date.now.formatted(date: .long, time: .shortened)
        var lines = [
            "# GradCheck 제출 전 체크리스트",
            "",
            "- 지원 목표: \(workspace.school) · \(workspace.program) · \(workspace.degree)",
            "- 입학 학기: \(workspace.intake)",
            "- 생성 시각: \(date)",
            "- 결과: BLOCKED \(blockedCount) · HUMAN REVIEW \(humanReviewCount) · READY \(readyCount)",
            "",
            "> 이 리포트는 업로드된 문서의 제출 전 QA 결과이며 합격, 공식성, 비자 승인 등을 판단하지 않습니다.",
            ""
        ]

        for status in ReviewStatus.allCases {
            lines.append("## \(status.rawValue) — \(status.label)")
            lines.append("")
            for finding in findings.filter({ $0.status == status }) {
                lines.append("- [\(status == .ready ? "x" : " ")] **\(finding.title)**")
                lines.append("  - \(finding.summary)")
                lines.append("  - 조치: \(finding.action)")
                let sources = finding.evidences.map(\.sourceLabel).joined(separator: ", ")
                lines.append("  - 근거: \(sources)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func updateDocument(id: UUID, update: (inout DocumentItem) -> Void) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        update(&documents[index])
    }

    private func commitImportedDocument(
        _ id: UUID,
        as type: DocumentType,
        extraction: ExtractedDocument
    ) {
        guard let item = documents.first(where: { $0.id == id }) else { return }

        let replacedIDs: Set<UUID>
        if type.isCore {
            replacedIDs = Set(documents.filter { $0.id != id && $0.type == type }.map(\.id))
        } else if type == .requirements {
            replacedIDs = Set(documents.filter {
                $0.id != id && $0.type == .requirements && sameFilename($0.filename, item.filename)
            }.map(\.id))
        } else {
            replacedIDs = []
        }

        documents.removeAll { replacedIDs.contains($0.id) }
        replacedIDs.forEach { extractedDocuments.removeValue(forKey: $0) }
        updateDocument(id: id) { document in
            document.type = type
            document.pageCount = extraction.pageCount
            document.processingStatus = .ready
        }
        extractedDocuments[id] = extraction

        if type == .requirements {
            requirements.removeAll { sameFilename($0.sourceName, item.filename) }
            requirements.append(contentsOf: RequirementExtractor().extract(
                from: extraction,
                sourceName: item.filename
            ))
        }
        invalidateAudit()
    }

    private func sameFilename(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private func invalidateAudit() {
        findings = []
        selectedFindingID = nil
        workspace.status = .preparing
    }

    private func cancelActiveImport() {
        importTask?.cancel()
        importTask = nil
        activeImportID = nil
        isImporting = false
    }

    private func cancelActiveAudit() {
        auditTask?.cancel()
        auditTask = nil
        activeAuditID = nil
        isAuditing = false
    }

    private func persist() {
        let snapshot = SafeSnapshot(
            workspaceID: workspace.id,
            school: workspace.school,
            program: workspace.program,
            degree: workspace.degree,
            intake: workspace.intake,
            createdAt: workspace.createdAt,
            lastAuditedAt: workspace.lastAuditedAt,
            isSample: workspace.isSample,
            sampleRevisionApplied: workspace.isSample && documents.contains { $0.filename == "JiyoonKim_SOP_revised.pdf" },
            hadUserDocuments: documents.contains { !$0.isSample },
            currentAuditValid: hasCurrentAudit,
            history: history
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func dismissSuccessMessageLater() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            successMessage = nil
        }
    }

    private static var demoHistory: [AuditHistoryEntry] {
        [
            AuditHistoryEntry(
                date: DemoData.referenceDate.addingTimeInterval(-60 * 18),
                blockedCount: 2,
                reviewCount: 2,
                readyCount: 4,
                note: "샘플 지원 패키지 최초 검수"
            )
        ]
    }

    private static func loadSafeSnapshot(storageKey: String, legacyStorageKey: String) -> SafeSnapshot? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(SafeSnapshot.self, from: data) {
            return snapshot
        }

        guard let legacyData = defaults.data(forKey: legacyStorageKey),
              let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: legacyData) else {
            return nil
        }
        let migrated = SafeSnapshot(
            workspaceID: legacy.workspace.id,
            school: legacy.workspace.school,
            program: legacy.workspace.program,
            degree: legacy.workspace.degree,
            intake: legacy.workspace.intake,
            createdAt: legacy.workspace.createdAt,
            lastAuditedAt: legacy.workspace.lastAuditedAt,
            isSample: legacy.workspace.isSample,
            history: legacy.history
        )
        if let safeData = try? JSONEncoder().encode(migrated) {
            defaults.set(safeData, forKey: storageKey)
            defaults.removeObject(forKey: legacyStorageKey)
        }
        return migrated
    }
}

private struct SafeSnapshot: Codable {
    var workspaceID: UUID
    var school: String
    var program: String
    var degree: String
    var intake: String
    var createdAt: Date
    var lastAuditedAt: Date?
    var isSample: Bool
    var sampleRevisionApplied: Bool? = nil
    var hadUserDocuments: Bool? = nil
    var currentAuditValid: Bool? = nil
    var history: [AuditHistoryEntry]
}

private struct LegacySnapshot: Codable {
    var workspace: ApplicationWorkspace
    var documents: [DocumentItem]
    var findings: [AuditFinding]
    var requirements: [RequirementItem]
    var history: [AuditHistoryEntry]
}
