import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var destination: AppDestination = .documents
    @Published private(set) var documentsRoute: DocumentsRoute = .list
    @Published private(set) var portfolio: ApplicationPortfolio
    @Published var selectedFindingID: UUID?
    @Published var isAuditing = false
    @Published private(set) var isImporting = false
    @Published var auditPhase: AuditPhase = .reading
    @Published var showNewWorkspace = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let documentAnalyzer: any DocumentAnalyzing
    private let requirementsAnalyzer: any RequirementsAnalyzing
    private let graduateRequirementsAnalyzer: any GraduateRequirementsAnalyzing
    private let apiKeyStore: any UpstageAPIKeyStoring
    private let auditor: any ApplicationAuditing
    private let repository: any ApplicationRepository
    private var importTask: Task<Void, Never>?
    private var activeImportID: UUID?
    private var auditTask: Task<Void, Never>?
    private var activeAuditID: UUID?

    convenience init(
        loadSavedState: Bool = true,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.init(dependencies: .live(environment: environment, loadSavedState: loadSavedState))
    }

    init(dependencies: AppDependencies) {
        documentAnalyzer = dependencies.documentAnalyzer
        requirementsAnalyzer = dependencies.requirementsAnalyzer
        graduateRequirementsAnalyzer = dependencies.graduateRequirementsAnalyzer
        apiKeyStore = dependencies.apiKeyStore
        auditor = dependencies.auditor
        repository = dependencies.repository

        if let snapshot = dependencies.repository.load(), !snapshot.sessions.isEmpty {
            let sessions = snapshot.sessions.map { Self.restore($0, auditor: dependencies.auditor) }
            let selectedID = sessions.contains(where: { $0.id == snapshot.selectedWorkspaceID })
                ? snapshot.selectedWorkspaceID
                : sessions[0].id
            portfolio = ApplicationPortfolio(sessions: sessions, selectedWorkspaceID: selectedID)
        } else {
            let demo = Self.demoSession()
            portfolio = ApplicationPortfolio(sessions: [demo], selectedWorkspaceID: demo.id)
        }
        selectedFindingID = findings.first(where: { $0.status == .blocked })?.id ?? findings.first?.id
    }

    var workspaces: [ApplicationWorkspace] { portfolio.workspaces }
    var selectedWorkspaceID: UUID { portfolio.selectedWorkspaceID }
    var workspace: ApplicationWorkspace { selectedSession.workspace }
    var documents: [DocumentItem] { selectedSession.documents }
    var findings: [AuditFinding] { selectedSession.findings }
    var requirements: [RequirementItem] { selectedSession.requirements }
    var history: [AuditHistoryEntry] { selectedSession.history }
    var requirementDocuments: [DocumentItem] { selectedSession.requirementDocuments }
    var requiredDocumentTypes: [DocumentType] { selectedSession.requiredDocumentTypes }
    var requiredDocumentCount: Int { selectedSession.requiredDocumentCount }
    var readyDocumentCount: Int { selectedSession.readyDocumentCount }

    var providerLabel: String { graduateRequirementsAnalyzer.providerLabel }
    var isUpstageConnected: Bool { graduateRequirementsAnalyzer.hasAPIKey }
    var hasStoredUpstageAPIKey: Bool { graduateRequirementsAnalyzer.hasAPIKey }
    var hasCurrentAudit: Bool {
        workspace.status != .preparing && !findings.isEmpty && workspace.lastAuditedAt != nil
    }
    var hasUserWorkspaceData: Bool {
        !workspace.isSample || documents.contains { !$0.isSample }
    }
    var canRunAudit: Bool {
        !requirements.isEmpty && requiredDocumentCount > 0 && !isAuditing && !isImporting
    }

    var blockedCount: Int { findings.filter { $0.status == .blocked }.count }
    var humanReviewCount: Int { findings.filter { $0.status == .humanReview }.count }
    var readyCount: Int { findings.filter { $0.status == .ready }.count }

    var selectedFinding: AuditFinding? {
        get { findings.first(where: { $0.id == selectedFindingID }) }
        set { selectedFindingID = newValue?.id }
    }

    func requiredCount(for type: DocumentType) -> Int {
        selectedSession.requiredCount(for: type)
    }

    func readyCount(for type: DocumentType) -> Int {
        selectedSession.readyCount(for: type)
    }

    func selectWorkspace(_ id: UUID) {
        guard id != selectedWorkspaceID else { return }
        cancelActiveImport()
        cancelActiveAudit()
        var updated = portfolio
        guard updated.select(id) else { return }
        portfolio = updated
        selectedFindingID = findings.first(where: { $0.status == .blocked })?.id ?? findings.first?.id
        persist()
    }

    func showWorkspaceList() {
        destination = .documents
        documentsRoute = .list
    }

    func showWorkspaceDocuments(_ id: UUID) {
        selectWorkspace(id)
        destination = .documents
        documentsRoute = .detail
    }

    func showSelectedWorkspaceDocuments() {
        destination = .documents
        documentsRoute = .detail
    }

    func saveUpstageAPIKey(_ value: String) throws {
        try apiKeyStore.saveAPIKey(value)
        objectWillChange.send()
    }

    func removeUpstageAPIKey() throws {
        try apiKeyStore.removeAPIKey()
        objectWillChange.send()
    }

    func deleteWorkspace(_ id: UUID) {
        guard portfolio.sessions.count > 1 else {
            errorMessage = "지원 항목은 하나 이상 남겨야 합니다."
            return
        }
        guard let index = portfolio.sessions.firstIndex(where: { $0.id == id }) else { return }

        let deletingSelectedWorkspace = id == selectedWorkspaceID
        if deletingSelectedWorkspace {
            cancelActiveImport()
            cancelActiveAudit()
        }

        var updated = portfolio
        let deletedWorkspace = updated.sessions.remove(at: index).workspace
        if deletingSelectedWorkspace {
            let nextIndex = min(index, updated.sessions.count - 1)
            updated.selectedWorkspaceID = updated.sessions[nextIndex].id
        }
        portfolio = updated

        if deletingSelectedWorkspace {
            selectedFindingID = findings.first(where: { $0.status == .blocked })?.id ?? findings.first?.id
            showWorkspaceList()
        }
        successMessage = "\(deletedWorkspace.school) 지원 항목을 삭제했어요."
        persist()
        dismissSuccessMessageLater()
    }

    func analyzeRequirements(_ urls: [URL]) async throws -> RequirementAnalysisResult {
        guard !urls.isEmpty else { throw WorkspaceFlowError.requirementsMissing }

        // The Studio Agent is the source of truth for requirement extraction.
        // The local pipeline below is retained only for PDF page count/preview
        // and later document-to-requirement evidence checks.
        let agentRequirements = try await graduateRequirementsAnalyzer.analyze(urls: urls)

        var documents: [DocumentItem] = []
        var extractions: [UUID: ExtractedDocument] = [:]

        for url in urls {
            try Task.checkCancellation()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

            let extraction: ExtractedDocument
            do {
                extraction = try await documentAnalyzer.extract(from: url)
            } catch {
                // The Studio Agent has already read this PDF. A scan without a
                // local PDF text layer must not prevent its extracted checklist
                // from proceeding to the support-document preparation screen.
                extraction = agentBackedExtraction(for: url)
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let document = DocumentItem(
                type: .requirements,
                filename: url.lastPathComponent,
                pageCount: extraction.pageCount,
                sizeInBytes: size,
                processingStatus: .ready,
                isSample: false
            )
            documents.removeAll { sameFilename($0.filename, document.filename) }
            documents.append(document)
            extractions[document.id] = extraction
        }

        guard !agentRequirements.isEmpty else { throw WorkspaceFlowError.noRequirementsExtracted }
        return RequirementAnalysisResult(
            documents: documents,
            requirements: agentRequirements,
            extractions: extractions
        )
    }

    func addWorkspace(draft: WorkspaceDraft, analysis: RequirementAnalysisResult) {
        let draft = draft.normalized
        guard !draft.school.isEmpty, !draft.program.isEmpty, !draft.intake.isEmpty else {
            errorMessage = WorkspaceFlowError.targetMissing.localizedDescription
            return
        }
        guard !analysis.documents.isEmpty, !analysis.requirements.isEmpty else {
            errorMessage = WorkspaceFlowError.requirementsMissing.localizedDescription
            return
        }
        guard !analysis.requiredDocumentTypes.isEmpty else {
            errorMessage = WorkspaceFlowError.noApplicantDocuments.localizedDescription
            return
        }

        cancelActiveImport()
        cancelActiveAudit()
        let workspace = ApplicationWorkspace(
            school: draft.school,
            program: draft.program,
            degree: draft.degree,
            intake: draft.intake,
            applicantName: draft.applicantName
        )
        let session = ApplicationSession(
            workspace: workspace,
            documents: analysis.documents,
            findings: [],
            requirements: analysis.requirements,
            history: [],
            extractedDocuments: analysis.extractions
        )
        var updated = portfolio
        updated.upsert(session, select: true)
        portfolio = updated
        selectedFindingID = nil
        showSelectedWorkspaceDocuments()
        showNewWorkspace = false
        successMessage = "모집요강에서 필요한 서류를 정리했어요."
        persist()
        dismissSuccessMessageLater()
    }

    func loadDemo() {
        cancelActiveImport()
        cancelActiveAudit()
        let demo = Self.demoSession(noteDate: .now)
        var updated = portfolio
        updated.upsert(demo, select: true)
        portfolio = updated
        selectedFindingID = findings.first(where: { $0.status == .blocked })?.id
        showSelectedWorkspaceDocuments()
        showNewWorkspace = false
        successMessage = "샘플 지원서를 불러왔어요."
        persist()
        dismissSuccessMessageLater()
    }

    func importDocuments(_ urls: [URL], as requestedType: DocumentType? = nil) {
        guard !urls.isEmpty, !isImporting else { return }
        cancelActiveAudit()
        errorMessage = nil
        isImporting = true
        let importID = UUID()
        activeImportID = importID
        let workspaceID = selectedWorkspaceID

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
                guard !Task.isCancelled,
                      self.selectedWorkspaceID == workspaceID,
                      self.activeImportID == importID else { return }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

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
                self.updateSession(id: workspaceID) { $0.documents.append(item) }

                do {
                    var agentRequirements: [RequirementItem]?
                    if provisionalType == .requirements, self.graduateRequirementsAnalyzer.hasAPIKey {
                        agentRequirements = try await self.graduateRequirementsAnalyzer.analyze(urls: [url])
                    }

                    let extraction: ExtractedDocument
                    do {
                        extraction = try await self.documentAnalyzer.extract(from: url)
                    } catch {
                        guard agentRequirements != nil else { throw error }
                        extraction = self.agentBackedExtraction(for: url)
                    }
                    guard !Task.isCancelled,
                          self.selectedWorkspaceID == workspaceID,
                          self.activeImportID == importID else { return }
                    let finalType = requestedType ?? DocumentType.infer(
                        from: item.filename,
                        content: extraction.text
                    )
                    if finalType == .requirements,
                       agentRequirements == nil,
                       self.graduateRequirementsAnalyzer.hasAPIKey {
                        agentRequirements = try await self.graduateRequirementsAnalyzer.analyze(urls: [url])
                    }
                    self.commitImportedDocument(
                        item.id,
                        workspaceID: workspaceID,
                        as: finalType,
                        extraction: extraction,
                        requirements: agentRequirements
                    )
                    importedTypes.append(finalType)
                } catch {
                    guard self.selectedWorkspaceID == workspaceID,
                          self.activeImportID == importID else { return }
                    self.updateSession(id: workspaceID) { session in
                        session.documents.removeAll { $0.id == item.id }
                        session.extractedDocuments.removeValue(forKey: item.id)
                    }
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }

            self.persist()
            if self.errorMessage == nil, !importedTypes.isEmpty {
                let names = importedTypes.map(\.shortTitle).joined(separator: ", ")
                self.successMessage = "\(names) 파일을 분석했어요. 재검수를 실행해 주세요."
                self.dismissSuccessMessageLater()
            }
        }
    }

    func removeDocument(_ document: DocumentItem) {
        guard !isImporting else { return }
        cancelActiveAudit()
        updateSelectedSession { session in
            session.documents.removeAll { $0.id == document.id }
            session.extractedDocuments.removeValue(forKey: document.id)
            if document.type == .requirements {
                session.requirements.removeAll { sameFilename($0.sourceName, document.filename) }
            }
            invalidateAudit(&session)
        }
        persist()
    }

    func applyRevisedSampleSOP() {
        guard workspace.isSample, !isImporting else { return }
        cancelActiveAudit()
        updateSelectedSession { session in
            let oldIDs = session.documents.filter { $0.type == .sop }.map(\.id)
            session.documents.removeAll { $0.type == .sop }
            oldIDs.forEach { session.extractedDocuments.removeValue(forKey: $0) }

            let revised = DemoData.revisedSOPDocument()
            session.documents.append(revised)
            session.extractedDocuments[revised.id] = DemoData.extractions(for: [revised])[revised.id]
            invalidateAudit(&session)
        }
        successMessage = "수정본 샘플을 적용했어요. 재검수를 실행해 주세요."
        persist()
        dismissSuccessMessageLater()
    }

    func runAudit() {
        guard canRunAudit else {
            if requirements.isEmpty {
                destination = .requirements
                errorMessage = "먼저 공식 모집요강을 추가해 필요 서류를 확인해 주세요."
            }
            return
        }
        isAuditing = true
        errorMessage = nil
        auditPhase = .reading
        let auditID = UUID()
        activeAuditID = auditID
        let workspaceID = selectedWorkspaceID
        let session = selectedSession

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
                guard !Task.isCancelled,
                      self.selectedWorkspaceID == workspaceID,
                      self.activeAuditID == auditID else { return }
                self.auditPhase = phase
                do { try await Task.sleep(for: .milliseconds(520)) } catch { return }
            }

            let auditedFindings = self.auditor.findings(
                for: session.workspace,
                documents: session.documents,
                extracted: session.extractedDocuments,
                requirements: session.requirements
            )
            guard !Task.isCancelled,
                  self.selectedWorkspaceID == workspaceID,
                  self.activeAuditID == auditID else { return }

            self.updateSession(id: workspaceID) { current in
                current.findings = auditedFindings
                current.workspace.lastAuditedAt = .now
                current.workspace.status = auditedFindings.contains { $0.status != .ready } ? .needsReview : .ready
                let blocked = auditedFindings.filter { $0.status == .blocked }.count
                let review = auditedFindings.filter { $0.status == .humanReview }.count
                let ready = auditedFindings.filter { $0.status == .ready }.count
                current.history.insert(
                    AuditHistoryEntry(
                        blockedCount: blocked,
                        reviewCount: review,
                        readyCount: ready,
                        note: current.documents.contains(where: { !$0.isSample })
                            ? "교체 문서 반영 후 재검수"
                            : "지원 패키지 검수"
                    ),
                    at: 0
                )
            }
            self.selectedFindingID = auditedFindings.first(where: { $0.status == .blocked })?.id
                ?? auditedFindings.first(where: { $0.status == .humanReview })?.id
                ?? auditedFindings.first?.id
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
                lines.append("  - 근거: \(finding.evidences.map(\.sourceLabel).joined(separator: ", "))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private var selectedSession: ApplicationSession {
        portfolio.selectedSession ?? Self.demoSession()
    }

    private func updateSelectedSession(_ update: (inout ApplicationSession) -> Void) {
        updateSession(id: selectedWorkspaceID, update)
    }

    private func updateSession(id: UUID, _ update: (inout ApplicationSession) -> Void) {
        var updated = portfolio
        guard let index = updated.sessions.firstIndex(where: { $0.id == id }) else { return }
        update(&updated.sessions[index])
        portfolio = updated
    }

    private func commitImportedDocument(
        _ id: UUID,
        workspaceID: UUID,
        as type: DocumentType,
        extraction: ExtractedDocument,
        requirements agentRequirements: [RequirementItem]? = nil
    ) {
        updateSession(id: workspaceID) { session in
            guard let item = session.documents.first(where: { $0.id == id }) else { return }

            let expectedCount = session.requiredCount(for: type)
            let replacedIDs: Set<UUID>
            if type == .requirements {
                replacedIDs = Set(session.documents.filter {
                    $0.id != id && $0.type == .requirements && sameFilename($0.filename, item.filename)
                }.map(\.id))
            } else if type.isApplicantDocument && expectedCount <= 1 {
                replacedIDs = Set(session.documents.filter { $0.id != id && $0.type == type }.map(\.id))
            } else {
                replacedIDs = Set(session.documents.filter {
                    $0.id != id && $0.type == type && sameFilename($0.filename, item.filename)
                }.map(\.id))
            }

            session.documents.removeAll { replacedIDs.contains($0.id) }
            replacedIDs.forEach { session.extractedDocuments.removeValue(forKey: $0) }
            guard let index = session.documents.firstIndex(where: { $0.id == id }) else { return }
            session.documents[index].type = type
            session.documents[index].pageCount = extraction.pageCount
            session.documents[index].processingStatus = .ready
            session.extractedDocuments[id] = extraction

            if type == .requirements {
                session.requirements.removeAll { sameFilename($0.sourceName, item.filename) }
                session.requirements.append(contentsOf: agentRequirements ?? requirementsAnalyzer.extract(
                    from: extraction,
                    sourceName: item.filename
                ))
            }
            invalidateAudit(&session)
        }
    }

    private func sameFilename(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private func agentBackedExtraction(for url: URL) -> ExtractedDocument {
        ExtractedDocument(
            pages: ["이 모집요강은 Upstage Studio Agent가 직접 분석했습니다."],
            provider: graduateRequirementsAnalyzer.providerLabel,
            sourcePageNumbers: [nil]
        )
    }

    private func invalidateAudit(_ session: inout ApplicationSession) {
        session.findings = []
        session.workspace.status = .preparing
        session.workspace.lastAuditedAt = nil
        selectedFindingID = nil
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
        let snapshots = portfolio.sessions.map { session in
            var safeWorkspace = session.workspace
            if !safeWorkspace.isSample { safeWorkspace.applicantName = "" }
            return ApplicationSessionSnapshot(
                workspace: safeWorkspace,
                requirementDocuments: session.requirementDocuments,
                requirements: session.requirements,
                history: session.history,
                sampleRevisionApplied: session.workspace.isSample
                    && session.documents.contains { $0.filename == "JiyoonKim_SOP_revised.pdf" },
                currentAuditValid: session.workspace.isSample
                    && session.workspace.status != .preparing
                    && !session.findings.isEmpty
            )
        }
        repository.save(ApplicationPortfolioSnapshot(
            sessions: snapshots,
            selectedWorkspaceID: selectedWorkspaceID
        ))
    }

    private func dismissSuccessMessageLater() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.successMessage = nil
        }
    }

    private static func demoSession(noteDate: Date? = nil) -> ApplicationSession {
        ApplicationSession(
            workspace: DemoData.workspace,
            documents: DemoData.documents,
            findings: DemoData.findings,
            requirements: DemoData.requirements,
            history: [
                AuditHistoryEntry(
                    date: noteDate ?? DemoData.referenceDate.addingTimeInterval(-60 * 18),
                    blockedCount: 2,
                    reviewCount: 2,
                    readyCount: 4,
                    note: noteDate == nil ? "샘플 지원 패키지 최초 검수" : "샘플 지원 패키지 불러오기"
                )
            ],
            extractedDocuments: DemoData.extractions(for: DemoData.documents)
        )
    }

    private static func restore(
        _ snapshot: ApplicationSessionSnapshot,
        auditor: any ApplicationAuditing
    ) -> ApplicationSession {
        guard snapshot.workspace.isSample else {
            var workspace = snapshot.workspace
            workspace.status = .preparing
            workspace.lastAuditedAt = nil
            return ApplicationSession(
                workspace: workspace,
                documents: snapshot.requirementDocuments,
                findings: [],
                requirements: snapshot.requirements,
                history: snapshot.history,
                extractedDocuments: [:]
            )
        }

        var documents = DemoData.documents
        if snapshot.sampleRevisionApplied {
            documents.removeAll { $0.type == .sop }
            documents.append(DemoData.revisedSOPDocument())
        }
        var workspace = DemoData.workspace
        let extractions = DemoData.extractions(for: documents)
        let findings: [AuditFinding]
        if snapshot.currentAuditValid {
            workspace.lastAuditedAt = snapshot.workspace.lastAuditedAt ?? DemoData.workspace.lastAuditedAt
            workspace.status = .needsReview
            findings = auditor.findings(
                for: workspace,
                documents: documents,
                extracted: extractions,
                requirements: DemoData.requirements
            )
        } else {
            workspace.status = .preparing
            workspace.lastAuditedAt = nil
            findings = []
        }
        return ApplicationSession(
            workspace: workspace,
            documents: documents,
            findings: findings,
            requirements: DemoData.requirements,
            history: snapshot.history,
            extractedDocuments: extractions
        )
    }
}

enum WorkspaceFlowError: LocalizedError {
    case targetMissing
    case requirementsMissing
    case noRequirementsExtracted
    case noApplicantDocuments

    var errorDescription: String? {
        switch self {
        case .targetMissing:
            "학교, 프로그램, 입학 학기를 입력해 주세요."
        case .requirementsMissing:
            "공식 모집요강 파일을 한 개 이상 추가해 주세요."
        case .noRequirementsExtracted:
            "모집요강에서 요건을 찾지 못했습니다. 텍스트가 포함된 공식 문서인지 확인해 주세요."
        case .noApplicantDocuments:
            "필요 서류 유형을 찾지 못했습니다. 분석 결과를 확인하거나 다른 모집요강을 추가해 주세요."
        }
    }
}
