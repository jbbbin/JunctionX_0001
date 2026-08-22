import Foundation
import XCTest
@testable import GradCheck

@MainActor
final class AppStateImportTests: XCTestCase {
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
        let state = AppState(loadSavedState: false, environment: [:])
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
        let state = AppState(loadSavedState: false, environment: [:])
        state.runAudit()
        XCTAssertTrue(state.isAuditing)

        state.createWorkspace(
            school: "Stanford University",
            program: "Computer Science",
            degree: "MS",
            intake: "Fall 2028",
            applicantName: ""
        )
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(state.workspace.school, "Stanford University")
        XCTAssertNil(state.workspace.lastAuditedAt)
        XCTAssertFalse(state.isAuditing)
        XCTAssertFalse(state.hasCurrentAudit)
        XCTAssertEqual(state.findings.filter { $0.status == .blocked }.count, 4)
    }

    func testRevisedSyntheticSampleRestoresWithoutPersistingRawUserDocuments() async throws {
        let defaults = UserDefaults.standard
        let storageKey = "GradCheck.workspace.v2"
        let legacyKey = "GradCheck.workspace.v1"
        let previous = defaults.object(forKey: storageKey)
        let previousLegacy = defaults.object(forKey: legacyKey)
        defer {
            if let previous { defaults.set(previous, forKey: storageKey) } else { defaults.removeObject(forKey: storageKey) }
            if let previousLegacy { defaults.set(previousLegacy, forKey: legacyKey) } else { defaults.removeObject(forKey: legacyKey) }
        }

        let state = AppState(loadSavedState: false, environment: [:])
        state.applyRevisedSampleSOP()

        let unauditedRestore = AppState(loadSavedState: true, environment: [:])
        XCTAssertTrue(unauditedRestore.documents.contains { $0.filename == "JiyoonKim_SOP_revised.pdf" })
        XCTAssertFalse(unauditedRestore.hasCurrentAudit)

        unauditedRestore.runAudit()
        try await waitForAudit(toFinishIn: unauditedRestore)
        let auditedRestore = AppState(loadSavedState: true, environment: [:])

        XCTAssertTrue(auditedRestore.documents.contains { $0.filename == "JiyoonKim_SOP_revised.pdf" })
        XCTAssertTrue(auditedRestore.hasCurrentAudit)
        XCTAssertEqual(auditedRestore.blockedCount, 1)
    }

    private func makeWorkspace() -> AppState {
        let state = AppState(loadSavedState: false, environment: [:])
        state.createWorkspace(
            school: "MIT",
            program: "EECS",
            degree: "PhD",
            intake: "Fall 2027",
            applicantName: "Jiyoon Kim"
        )
        return state
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

    private func waitForImport(toFinishIn state: AppState) async throws {
        for _ in 0..<300 {
            if !state.isImporting { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Document import did not finish in time")
    }

    private func waitForAudit(toFinishIn state: AppState) async throws {
        for _ in 0..<300 {
            if !state.isAuditing { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Audit did not finish in time")
    }
}
