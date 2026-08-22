import Foundation
import XCTest
@testable import GradCheck

@MainActor
final class AppViewModelTests: XCTestCase {
    func testRegistersMultipleRequirementSourcesAndReplacesOnlySameFilename() async throws {
        let state = makeWorkspace()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let universityURL = try write(
            "Graduate Admissions application requirements: Official transcript must be submitted as PDF.",
            named: "university.txt",
            in: root
        )
        let programURL = try write(
            "Statement of Purpose is required.\nMaximum 2 pages.",
            named: "program.txt",
            in: root
        )

        state.importDocuments([universityURL], as: .requirements)
        try await waitForImport(toFinishIn: state)
        state.importDocuments([programURL], as: .requirements)
        try await waitForImport(toFinishIn: state)

        XCTAssertEqual(state.documents.filter { $0.type == .requirements }.count, 2)
        XCTAssertEqual(Set(state.requirements.map(\.sourceName)), ["university.txt", "program.txt"])

        try "Statement of Purpose is required.\nMaximum 3 pages.".write(
            to: programURL,
            atomically: true,
            encoding: .utf8
        )
        state.importDocuments([programURL], as: .requirements)
        try await waitForImport(toFinishIn: state)

        XCTAssertEqual(state.documents.filter { $0.type == .requirements }.count, 2)
        XCTAssertEqual(state.requirements.filter { $0.sourceName == "program.txt" }.count, 1)
        XCTAssertEqual(
            state.requirements.first { $0.sourceName == "program.txt" }?.maximumPages,
            3
        )
        XCTAssertTrue(state.requirements.contains { $0.sourceName == "university.txt" })

        let missingDirectory = root.appendingPathComponent("missing", isDirectory: true)
        let missingReselection = missingDirectory.appendingPathComponent("program.txt")
        state.importDocuments([missingReselection], as: .requirements)
        try await waitForImport(toFinishIn: state)

        XCTAssertEqual(state.documents.filter { $0.type == .requirements }.count, 2)
        XCTAssertEqual(
            state.requirements.first { $0.sourceName == "program.txt" }?.maximumPages,
            3
        )
    }

    func testRemovingOneRequirementDocumentKeepsOtherSourceItems() async throws {
        let state = makeWorkspace()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try write("Official transcript is required as PDF.", named: "school.txt", in: root)
        let second = try write("Statement of Purpose is required.", named: "program.txt", in: root)

        state.importDocuments([first], as: .requirements)
        try await waitForImport(toFinishIn: state)
        state.importDocuments([second], as: .requirements)
        try await waitForImport(toFinishIn: state)

        let schoolDocument = try XCTUnwrap(
            state.documents.first { $0.type == .requirements && $0.filename == "school.txt" }
        )
        state.removeDocument(schoolDocument)

        XCTAssertFalse(state.requirements.contains { $0.sourceName == "school.txt" })
        XCTAssertTrue(state.requirements.contains { $0.sourceName == "program.txt" })
        XCTAssertEqual(state.documents.filter { $0.type == .requirements }.count, 1)
    }

    func testBulkImportClassifiesFourGenericDocumentsFromContent() async throws {
        let state = makeWorkspace()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fixtures: [(String, String)] = [
            ("cv", "CURRICULUM VITAE\nEDUCATION\nRESEARCH EXPERIENCE\nSELECTED PUBLICATIONS"),
            ("sop", "STATEMENT OF PURPOSE\nI am applying to the MIT EECS PhD program."),
            ("transcript", "OFFICIAL TRANSCRIPT\nCourse Credits Grade\nCumulative GPA: 3.82"),
            ("score", "TOEFL iBT SCORE REPORT\nTotal Score: 108\nTest Date: October 12, 2026")
        ]
        let urls = try fixtures.map { folder, content in
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try write(content, named: "document.txt", in: directory)
        }

        state.importDocuments(urls)
        try await waitForImport(toFinishIn: state)

        let importedTypes = Set(state.documents.filter(\.type.isCore).map(\.type))
        XCTAssertEqual(importedTypes, Set([.cv, .sop, .transcript, .englishScore]))
        XCTAssertFalse(state.documents.contains { $0.type == .other })
    }

    func testFailedCoreReplacementPreservesExistingDocument() async throws {
        let state = makeWorkspace()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cvURL = try write(
            "CURRICULUM VITAE\nEDUCATION\nRESEARCH EXPERIENCE",
            named: "document.txt",
            in: root
        )
        state.importDocuments([cvURL])
        try await waitForImport(toFinishIn: state)
        let existing = try XCTUnwrap(state.documents.first { $0.type == .cv })

        let missingURL = root.appendingPathComponent("missing.txt")
        state.importDocuments([missingURL], as: .cv)
        try await waitForImport(toFinishIn: state)

        XCTAssertEqual(state.documents.filter { $0.type == .cv }.map(\.id), [existing.id])
        XCTAssertNotNil(state.errorMessage)
    }

    func testRealFileInsideSampleCountsAsUserWorkspaceData() async throws {
        let state = AppViewModel(loadSavedState: false, environment: [:])
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try write(
            "CURRICULUM VITAE\nEDUCATION\nRESEARCH EXPERIENCE",
            named: "my-cv.txt",
            in: root
        )

        state.importDocuments([url], as: .cv)
        try await waitForImport(toFinishIn: state)

        XCTAssertTrue(state.workspace.isSample)
        XCTAssertTrue(state.hasUserWorkspaceData)
    }

    func testCreatingWorkspaceCancelsInFlightAudit() async throws {
        let state = AppViewModel(loadSavedState: false, environment: [:])
        state.runAudit()
        XCTAssertTrue(state.isAuditing)

        state.addWorkspace(
            draft: WorkspaceDraft(
                school: "Stanford University",
                program: "Computer Science",
                degree: "MS",
                intake: "Fall 2028",
                applicantName: ""
            ),
            analysis: requirementAnalysis(type: .sop, source: "stanford.txt")
        )
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(state.workspace.school, "Stanford University")
        XCTAssertNil(state.workspace.lastAuditedAt)
        XCTAssertFalse(state.isAuditing)
        XCTAssertFalse(state.hasCurrentAudit)
        XCTAssertTrue(state.findings.isEmpty)
    }

    func testRevisedSyntheticSampleRestoresWithoutPersistingRawUserDocuments() async throws {
        let suiteName = "GradCheckTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsApplicationRepository(defaults: defaults)
        let dependencies = AppDependencies(
            documentAnalyzer: DocumentPipeline(environment: [:]),
            requirementsAnalyzer: RequirementExtractor(),
            auditor: AuditEngine(),
            repository: repository
        )

        let state = AppViewModel(dependencies: dependencies)
        state.applyRevisedSampleSOP()

        let unauditedRestore = AppViewModel(dependencies: dependencies)
        XCTAssertTrue(unauditedRestore.documents.contains { $0.filename == "JiyoonKim_SOP_revised.pdf" })
        XCTAssertFalse(unauditedRestore.hasCurrentAudit)

        unauditedRestore.runAudit()
        try await waitForAudit(toFinishIn: unauditedRestore)
        let auditedRestore = AppViewModel(dependencies: dependencies)

        XCTAssertTrue(auditedRestore.documents.contains { $0.filename == "JiyoonKim_SOP_revised.pdf" })
        XCTAssertTrue(auditedRestore.hasCurrentAudit)
        XCTAssertEqual(auditedRestore.blockedCount, 1)
    }

    func testAddingMultipleRequirementBackedWorkspacesPreservesEachSession() {
        let state = AppViewModel(loadSavedState: false, environment: [:])
        let first = requirementAnalysis(type: .sop, source: "mit.txt")
        state.addWorkspace(
            draft: WorkspaceDraft(
                school: "MIT",
                program: "EECS",
                degree: "PhD",
                intake: "Fall 2027",
                applicantName: ""
            ),
            analysis: first
        )
        let firstID = state.selectedWorkspaceID

        let second = requirementAnalysis(type: .portfolio, source: "risd.txt")
        state.addWorkspace(
            draft: WorkspaceDraft(
                school: "RISD",
                program: "Industrial Design",
                degree: "MFA",
                intake: "Fall 2028",
                applicantName: ""
            ),
            analysis: second
        )
        let secondID = state.selectedWorkspaceID

        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(state.workspaces.count, 3) // two user workspaces plus the sample
        XCTAssertEqual(state.requiredDocumentTypes, [.portfolio])

        state.selectWorkspace(firstID)
        XCTAssertEqual(state.workspace.school, "MIT")
        XCTAssertEqual(state.requiredDocumentTypes, [.sop])

        state.selectWorkspace(secondID)
        XCTAssertEqual(state.workspace.school, "RISD")
        XCTAssertEqual(state.requiredDocumentTypes, [.portfolio])
    }

    func testRequirementDerivedReadinessHonorsRequiredRecommendationCount() {
        let requirements = [
            RequirementItem(
                title: "추천서 3부",
                detail: "Three letters of recommendation are required.",
                scope: .program,
                status: .ready,
                sourceName: "program.txt",
                relatedDocumentType: .recommendation,
                requiredCount: 3
            )
        ]
        let documents = (1...2).map {
            DocumentItem(type: .recommendation, filename: "letter-\($0).pdf")
        }
        let session = ApplicationSession(
            workspace: DemoData.workspace,
            documents: documents,
            findings: [],
            requirements: requirements,
            history: [],
            extractedDocuments: [:]
        )

        XCTAssertEqual(session.requiredDocumentTypes, [.recommendation])
        XCTAssertEqual(session.requiredDocumentCount, 3)
        XCTAssertEqual(session.readyDocumentCount, 2)
    }

    func testDeletingSelectedWorkspaceSelectsRemainingWorkspace() {
        let state = AppViewModel(loadSavedState: false, environment: [:])
        let sampleID = state.selectedWorkspaceID
        state.addWorkspace(
            draft: WorkspaceDraft(
                school: "Stanford University",
                program: "Computer Science",
                degree: "MS",
                intake: "Fall 2028",
                applicantName: ""
            ),
            analysis: requirementAnalysis(type: .sop, source: "stanford.txt")
        )
        let deletingID = state.selectedWorkspaceID

        state.deleteWorkspace(deletingID)

        XCTAssertEqual(state.workspaces.count, 1)
        XCTAssertEqual(state.selectedWorkspaceID, sampleID)
        XCTAssertEqual(state.destination, .documents)
        XCTAssertFalse(state.workspaces.contains { $0.id == deletingID })
    }

    func testDocumentNavigationOpensSelectedWorkspaceDirectly() {
        let state = AppViewModel(loadSavedState: false, environment: [:])
        let workspaceID = state.selectedWorkspaceID

        state.showWorkspaceDocuments(workspaceID)

        XCTAssertEqual(state.destination, .documents)
        XCTAssertEqual(state.selectedWorkspaceID, workspaceID)
    }

    func testAuditNavigationOpensSelectedWorkspaceDirectly() {
        let state = AppViewModel(loadSavedState: false, environment: [:])
        let workspaceID = state.selectedWorkspaceID

        state.showWorkspaceAudit(workspaceID)

        XCTAssertEqual(state.destination, .audit)
        XCTAssertEqual(state.selectedWorkspaceID, workspaceID)
    }

    func testSidebarWorkspaceSelectionPreservesCurrentDetailDestination() {
        let state = AppViewModel(loadSavedState: false, environment: [:])
        let sampleID = state.selectedWorkspaceID
        state.addWorkspace(
            draft: WorkspaceDraft(
                school: "Stanford University",
                program: "Computer Science",
                degree: "MS",
                intake: "Fall 2028",
                applicantName: ""
            ),
            analysis: requirementAnalysis(type: .sop, source: "stanford.txt")
        )
        let addedID = state.selectedWorkspaceID

        state.showSelectedWorkspaceAudit()
        state.selectWorkspaceFromSidebar(sampleID)

        XCTAssertEqual(state.selectedWorkspaceID, sampleID)
        XCTAssertEqual(state.destination, .audit)

        state.destination = .requirements
        state.selectWorkspaceFromSidebar(addedID)

        XCTAssertEqual(state.selectedWorkspaceID, addedID)
        XCTAssertEqual(state.destination, .documents)
    }

    func testPortfolioOverviewAggregatesAllWorkspacesAndRoutesToFindingOwner() throws {
        let state = AppViewModel(loadSavedState: false, environment: [:])
        state.addWorkspace(
            draft: WorkspaceDraft(
                school: "MIT",
                program: "EECS",
                degree: "PhD",
                intake: "Fall 2027",
                applicantName: ""
            ),
            analysis: requirementAnalysis(type: .sop, source: "mit.txt")
        )

        let summaries = state.workspaceOverviewItems
        XCTAssertEqual(summaries.count, state.workspaces.count)
        XCTAssertEqual(
            state.portfolioRequiredDocumentCount,
            summaries.reduce(0) { $0 + $1.requiredDocumentCount }
        )
        XCTAssertEqual(
            state.portfolioBlockedCount,
            summaries.reduce(0) { $0 + $1.blockedCount }
        )

        let item = try XCTUnwrap(state.portfolioFindingItems.first)
        state.showPortfolioFinding(item)

        XCTAssertEqual(state.selectedWorkspaceID, item.workspaceID)
        XCTAssertEqual(state.selectedFindingID, item.finding.id)
        XCTAssertEqual(state.destination, .audit)
    }

    func testDeletingLastWorkspaceIsRejected() {
        let state = AppViewModel(loadSavedState: false, environment: [:])
        let lastID = state.selectedWorkspaceID

        state.deleteWorkspace(lastID)

        XCTAssertEqual(state.workspaces.count, 1)
        XCTAssertEqual(state.selectedWorkspaceID, lastID)
        XCTAssertNotNil(state.errorMessage)
    }

    func testWorkspaceCreationRejectsMissingRequirementAnalysis() {
        let state = AppViewModel(loadSavedState: false, environment: [:])
        state.addWorkspace(
            draft: WorkspaceDraft(
                school: "MIT",
                program: "EECS",
                degree: "PhD",
                intake: "Fall 2027",
                applicantName: ""
            ),
            analysis: RequirementAnalysisResult(documents: [], requirements: [], extractions: [:])
        )

        XCTAssertEqual(state.workspaces.count, 1)
        XCTAssertNotNil(state.errorMessage)
    }

    private func makeWorkspace() -> AppViewModel {
        let state = AppViewModel(loadSavedState: false, environment: [:])
        state.addWorkspace(
            draft: WorkspaceDraft(
                school: "MIT",
                program: "EECS",
                degree: "PhD",
                intake: "Fall 2027",
                applicantName: "Jiyoon Kim"
            ),
            analysis: requirementAnalysis(type: .sop, source: "program.txt")
        )
        return state
    }

    private func requirementAnalysis(type: DocumentType, source: String) -> RequirementAnalysisResult {
        let document = DocumentItem(type: .requirements, filename: source)
        let requirement = RequirementItem(
            title: type.title,
            detail: "\(type.title) is required.",
            scope: .program,
            status: .ready,
            sourceName: source,
            relatedDocumentType: type
        )
        return RequirementAnalysisResult(
            documents: [document],
            requirements: [requirement],
            extractions: [document.id: ExtractedDocument(pages: [requirement.detail], provider: "test")]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gradcheck-app-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ content: String, named filename: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func waitForImport(toFinishIn state: AppViewModel) async throws {
        for _ in 0..<300 {
            if !state.isImporting { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Document import did not finish in time")
    }

    private func waitForAudit(toFinishIn state: AppViewModel) async throws {
        for _ in 0..<300 {
            if !state.isAuditing { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Audit did not finish in time")
    }
}
