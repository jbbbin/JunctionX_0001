import XCTest
@testable import GradCheck

final class AuditEngineTests: XCTestCase {
    private let engine = AuditEngine()

    func testEmptyWorkspaceCreatesBlockerForEveryCoreDocument() {
        let workspace = ApplicationWorkspace(
            school: "MIT",
            program: "EECS",
            degree: "PhD",
            intake: "Fall 2027"
        )

        let findings = engine.findings(for: workspace, documents: [], extracted: [:])

        XCTAssertEqual(findings.filter { $0.status == .blocked }.count, 4)
        XCTAssertEqual(Set(findings.map(\.category)), [.completeness])
    }

    func testSyntheticDemoStillProducesTwoEvidenceBackedBlockers() {
        let findings = engine.findings(
            for: DemoData.workspace,
            documents: DemoData.documents,
            extracted: DemoData.extractions(for: DemoData.documents),
            requirements: DemoData.requirements
        )

        XCTAssertEqual(findings.filter { $0.status == .blocked }.count, 2)
        XCTAssertGreaterThanOrEqual(findings.filter { $0.status == .humanReview }.count, 2)
        XCTAssertTrue(findings.filter { $0.status == .blocked }.allSatisfy { finding in
            !finding.evidences.isEmpty && finding.evidences.allSatisfy { !$0.excerpt.hasPrefix("not_stated") }
        })
    }

    func testReplacingSampleSOPResolvesStaleProgramFinding() {
        var documents = DemoData.documents.filter { $0.type != .sop }
        let revisedSOP = DocumentItem(
            type: .sop,
            filename: "JiyoonKim_SOP_revised.pdf",
            pageCount: 2,
            isSample: false
        )
        documents.append(revisedSOP)
        var extracted = DemoData.extractions(for: documents)
        extracted[revisedSOP.id] = ExtractedDocument(
            pages: ["JIYOON KIM\nI am applying to the MIT Electrical Engineering & Computer Science PhD program."],
            provider: "test"
        )

        let findings = engine.findings(for: DemoData.workspace, documents: documents, extracted: extracted)
        let targetFinding = findings.first { $0.category == .target && $0.title.contains("학교와 프로그램명이 일치") }

        XCTAssertEqual(targetFinding?.status, .ready)
        XCTAssertTrue(targetFinding?.evidences.first?.documentName.contains("revised") == true)
        XCTAssertEqual(findings.filter { $0.status == .blocked }.count, 1)
    }

    func testDetectsOtherSchoolInApplicationContext() {
        let workspace = ApplicationWorkspace(
            school: "MIT",
            program: "EECS",
            degree: "PhD",
            intake: "Fall 2027"
        )
        let sop = DocumentItem(type: .sop, filename: "statement.txt", pageCount: 1)
        let extracted = ExtractedDocument(
            pages: ["I am applying to the Stanford Computer Science PhD program to study systems."],
            provider: "test"
        )

        let findings = engine.findings(for: workspace, documents: [sop], extracted: [sop.id: extracted])

        let staleTarget = findings.first { $0.category == .target }
        XCTAssertEqual(staleTarget?.status, .blocked)
        XCTAssertEqual(staleTarget?.evidences.first?.page, 1)
        XCTAssertTrue(staleTarget?.evidences.first?.excerpt.contains("Stanford") == true)
    }

    func testCorrectTargetDoesNotHidePreviousApplicationTarget() {
        let workspace = ApplicationWorkspace(
            school: "MIT",
            program: "Electrical Engineering & Computer Science",
            degree: "PhD",
            intake: "Fall 2027"
        )
        let sop = DocumentItem(type: .sop, filename: "statement.txt", pageCount: 2)
        let content = ExtractedDocument(
            pages: [
                "I am applying to the MIT Electrical Engineering & Computer Science PhD program.",
                "I am applying to the Stanford Computer Science PhD program."
            ],
            provider: "test"
        )

        let findings = engine.findings(for: workspace, documents: [sop], extracted: [sop.id: content])
        let target = findings.first { $0.category == .target && $0.title.contains("다른 학교") }

        XCTAssertEqual(target?.status, .blocked)
        XCTAssertEqual(target?.evidences.compactMap(\.page), [1, 2])
        XCTAssertFalse(findings.contains { $0.category == .target && $0.title.contains("프로그램명이 일치") })
    }

    func testShortProgramAcronymDoesNotMatchInsideAnotherWord() {
        let workspace = ApplicationWorkspace(
            school: "MIT",
            program: "Computer Science",
            degree: "PhD",
            intake: "Fall 2027"
        )
        let sop = DocumentItem(type: .sop, filename: "statement.txt")
        let content = ExtractedDocument(
            pages: ["I am applying to the MIT Physics PhD program."],
            provider: "test"
        )

        let findings = engine.findings(for: workspace, documents: [sop], extracted: [sop.id: content])

        XCTAssertTrue(findings.contains { $0.category == .target && $0.status == .blocked })
        XCTAssertFalse(findings.contains { $0.category == .target && $0.title.contains("프로그램명이 일치") })
    }

    func testFindingsAreOrderedBySeverity() {
        let workspace = ApplicationWorkspace(
            school: "MIT",
            program: "EECS",
            degree: "MS",
            intake: "Fall 2027"
        )
        let cv = DocumentItem(type: .cv, filename: "cv.txt")
        let findings = engine.findings(
            for: workspace,
            documents: [cv],
            extracted: [cv.id: ExtractedDocument(pages: ["MIT EECS"], provider: "test")]
        )

        let ranks = findings.map { $0.status.rank }
        XCTAssertEqual(ranks, ranks.sorted())
    }

    func testMissingTargetStatementNeverBecomesReady() {
        let workspace = ApplicationWorkspace(
            school: "MIT",
            program: "EECS",
            degree: "PhD",
            intake: "Fall 2027"
        )
        let sop = DocumentItem(type: .sop, filename: "sop.txt")
        let content = ExtractedDocument(
            pages: ["My research focuses on dependable distributed systems."],
            provider: "test"
        )

        let findings = engine.findings(for: workspace, documents: [sop], extracted: [sop.id: content])
        let targets = findings.filter { $0.category == .target }

        XCTAssertTrue(targets.contains { $0.status == .humanReview })
        XCTAssertFalse(targets.contains { $0.status == .ready })
    }

    func testClearNameMismatchIsBlockedWithBothSources() {
        let workspace = ApplicationWorkspace(
            school: "MIT",
            program: "EECS",
            degree: "PhD",
            intake: "Fall 2027",
            applicantName: "Alice Kim"
        )
        let cv = DocumentItem(type: .cv, filename: "cv.txt")
        let transcript = DocumentItem(type: .transcript, filename: "transcript.txt")
        let extracted: [UUID: ExtractedDocument] = [
            cv.id: ExtractedDocument(pages: ["ALICE KIM\nEducation"], provider: "test"),
            transcript.id: ExtractedDocument(pages: ["Student: BOB PARK"], provider: "test")
        ]

        let findings = engine.findings(for: workspace, documents: [cv, transcript], extracted: extracted)
        let mismatch = findings.first { $0.category == .identity && $0.status == .blocked }

        XCTAssertNotNil(mismatch)
        XCTAssertEqual(mismatch?.evidences.count, 2)
    }

    func testGraduationMonthMismatchIsBlockedWithPageEvidence() {
        let workspace = ApplicationWorkspace(school: "MIT", program: "EECS", degree: "PhD", intake: "Fall 2027")
        let cv = DocumentItem(type: .cv, filename: "cv.txt")
        let transcript = DocumentItem(type: .transcript, filename: "transcript.txt")
        let extracted: [UUID: ExtractedDocument] = [
            cv.id: ExtractedDocument(pages: ["B.S. in Computer Science · Korea University · Feb 2025"], provider: "test"),
            transcript.id: ExtractedDocument(pages: ["Degree conferred: Bachelor of Science · August 22, 2025"], provider: "test")
        ]

        let findings = engine.findings(for: workspace, documents: [cv, transcript], extracted: extracted)
        let mismatch = findings.first { $0.category == .education && $0.title.contains("졸업 시기") }

        XCTAssertEqual(mismatch?.status, .blocked)
        XCTAssertEqual(mismatch?.evidences.compactMap(\.page), [1, 1])
    }

    func testEnglishScoreAndDateBecomeEvidenceBackedReady() {
        let workspace = ApplicationWorkspace(school: "MIT", program: "EECS", degree: "PhD", intake: "Fall 2027")
        let score = DocumentItem(type: .englishScore, filename: "toefl.txt")
        let content = ExtractedDocument(
            pages: ["TOEFL iBT Total Score: 108\nTest Date: October 12, 2026"],
            provider: "test"
        )

        let findings = engine.findings(for: workspace, documents: [score], extracted: [score.id: content])
        let ready = findings.first { $0.category == .score && $0.title.contains("영어 점수") }

        XCTAssertEqual(ready?.status, .ready)
        XCTAssertEqual(ready?.evidences.count, 2)
    }

    func testEnglishScoreWithoutDateRequiresHumanReview() {
        let workspace = ApplicationWorkspace(school: "MIT", program: "EECS", degree: "PhD", intake: "Fall 2027")
        let score = DocumentItem(type: .englishScore, filename: "toefl.txt")
        let content = ExtractedDocument(pages: ["TOEFL iBT Total Score: 108"], provider: "test")

        let findings = engine.findings(for: workspace, documents: [score], extracted: [score.id: content])

        XCTAssertTrue(findings.contains { $0.category == .score && $0.status == .humanReview && $0.title.contains("시험일") })
        XCTAssertFalse(findings.contains { $0.category == .score && $0.status == .ready && $0.title.contains("시험일") })
    }

    func testSameGPAWithDifferentScalesIsBlocked() {
        let workspace = ApplicationWorkspace(school: "MIT", program: "EECS", degree: "PhD", intake: "Fall 2027")
        let cv = DocumentItem(type: .cv, filename: "cv.txt")
        let transcript = DocumentItem(type: .transcript, filename: "transcript.txt")
        let extracted: [UUID: ExtractedDocument] = [
            cv.id: ExtractedDocument(pages: ["Cumulative GPA: 3.82 / 4.50"], provider: "test"),
            transcript.id: ExtractedDocument(pages: ["Cumulative GPA: 3.82 / 4.00"], provider: "test")
        ]

        let findings = engine.findings(for: workspace, documents: [cv, transcript], extracted: extracted)

        XCTAssertTrue(findings.contains { $0.category == .score && $0.status == .blocked && $0.title.contains("만점 기준") })
        XCTAssertFalse(findings.contains { $0.category == .score && $0.status == .ready && $0.title.contains("GPA 값을") })
    }

    func testMissingAcademicFieldBecomesHumanReview() {
        let workspace = ApplicationWorkspace(school: "MIT", program: "EECS", degree: "PhD", intake: "Fall 2027")
        let cv = DocumentItem(type: .cv, filename: "cv.txt")
        let transcript = DocumentItem(type: .transcript, filename: "transcript.txt")
        let extracted: [UUID: ExtractedDocument] = [
            cv.id: ExtractedDocument(pages: ["B.S. in Computer Science · Korea University · Feb 2025"], provider: "test"),
            transcript.id: ExtractedDocument(pages: ["Degree conferred: Bachelor of Science · August 22, 2025"], provider: "test")
        ]

        let findings = engine.findings(for: workspace, documents: [cv, transcript], extracted: extracted)

        XCTAssertTrue(findings.contains { $0.category == .education && $0.status == .humanReview && $0.title.contains("학교명") })
    }

    func testUncertainRequirementBecomesHumanReviewFinding() {
        let workspace = ApplicationWorkspace(school: "MIT", program: "EECS", degree: "PhD", intake: "Fall 2027")
        let requirement = RequirementItem(
            title: "공식 요건 직접 확인",
            detail: "English proficiency may be waived in limited cases.",
            scope: .program,
            status: .humanReview,
            sourceName: "requirements.pdf",
            page: 3
        )

        let findings = engine.findings(for: workspace, documents: [], extracted: [:], requirements: [requirement])

        XCTAssertTrue(findings.contains { $0.status == .humanReview && $0.evidences.first?.page == 3 })
    }

    func testGRERequirementDoesNotMatchTheWordDegree() {
        let workspace = ApplicationWorkspace(school: "MIT", program: "EECS", degree: "PhD", intake: "Fall 2027")
        let transcript = DocumentItem(type: .transcript, filename: "transcript.txt")
        let requirement = RequirementItem(
            title: "GRE",
            detail: "GRE policy must be verified.",
            scope: .program,
            status: .humanReview,
            sourceName: "requirements.pdf",
            page: 7
        )
        let extracted = [
            transcript.id: ExtractedDocument(pages: ["Degree conferred: Bachelor of Science"], provider: "test")
        ]

        let findings = engine.findings(
            for: workspace,
            documents: [transcript],
            extracted: extracted,
            requirements: [requirement]
        )
        let gre = findings.first { $0.title.contains("GRE") }

        XCTAssertEqual(gre?.status, .humanReview)
        XCTAssertTrue(gre?.summary.contains("업로드 문서를 확인하지 못했습니다") == true)
    }
}
