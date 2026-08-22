import XCTest
@testable import GradCheck

final class DocumentTypeInferenceTests: XCTestCase {
    func testGenericFilenamesAreClassifiedFromDocumentContent() {
        let fixtures: [(String, DocumentType)] = [
            (
                "CURRICULUM VITAE\nEDUCATION\nRESEARCH EXPERIENCE\nSELECTED PUBLICATIONS",
                .cv
            ),
            (
                "STATEMENT OF PURPOSE\nI am applying to the MIT EECS PhD program.",
                .sop
            ),
            (
                "OFFICIAL TRANSCRIPT\nStudent Name: JIYOON KIM\nCourse Credits Grade\nCumulative GPA: 3.82",
                .transcript
            ),
            (
                "TOEFL iBT SCORE REPORT\nTotal Score: 108\nTest Date: October 12, 2026",
                .englishScore
            )
        ]

        for (content, expected) in fixtures {
            XCTAssertEqual(DocumentType.infer(from: "document.pdf", content: content), expected)
        }
    }

    func testContentCanCorrectAMisleadingCoreFilename() {
        let content = "STATEMENT OF PURPOSE\nI am applying to the MIT EECS PhD program."

        XCTAssertEqual(DocumentType.infer(from: "old_resume.pdf", content: content), .sop)
    }

    func testAdmissionsFilenameRemainsRequirementsWhenItMentionsOneCoreDocument() {
        let content = "Statement of Purpose must be submitted as a PDF with the application."

        XCTAssertEqual(DocumentType.infer(from: "graduate_admissions.pdf", content: content), .requirements)
    }
}
