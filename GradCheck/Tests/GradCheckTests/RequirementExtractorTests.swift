import XCTest
@testable import GradCheck

final class RequirementExtractorTests: XCTestCase {
    func testExtractsSOPFormatConstraintsWithSourcePage() {
        let content = ExtractedDocument(
            pages: ["Overview", "Statement of Purpose: PDF, maximum 2 pages and max 1,000 words."],
            provider: "test",
            sourcePageNumbers: [1, 4]
        )

        let items = RequirementExtractor().extract(from: content, sourceName: "requirements.pdf")
        let sop = items.first { $0.relatedDocumentType == .sop }

        XCTAssertEqual(sop?.page, 4)
        XCTAssertEqual(sop?.maximumPages, 2)
        XCTAssertEqual(sop?.maximumWords, 1_000)
        XCTAssertEqual(sop?.requiredFileExtension, "pdf")
    }

    func testMergesConstraintsSplitAcrossContinuationLines() {
        let content = ExtractedDocument(
            pages: [
                """
                Statement of Purpose is required.
                Submit the file as PDF.
                Maximum 2 pages.
                No more than 1,000 words.
                """
            ],
            provider: "test",
            sourcePageNumbers: [6]
        )

        let items = RequirementExtractor().extract(from: content, sourceName: "program.pdf")
        let sopItems = items.filter { $0.relatedDocumentType == .sop }

        XCTAssertEqual(sopItems.count, 1)
        XCTAssertEqual(sopItems.first?.page, 6)
        XCTAssertEqual(sopItems.first?.maximumPages, 2)
        XCTAssertEqual(sopItems.first?.maximumWords, 1_000)
        XCTAssertEqual(sopItems.first?.requiredFileExtension, "pdf")
        XCTAssertTrue(sopItems.first?.detail.contains("required") == true)
        XCTAssertTrue(sopItems.first?.detail.contains("Maximum 2 pages") == true)
    }

    func testMergedConditionalLineKeepsHumanReviewStatus() {
        let content = ExtractedDocument(
            pages: [
                """
                Statement of Purpose is required.
                Optional for applicants to the certificate track.
                """
            ],
            provider: "test"
        )

        let sop = RequirementExtractor()
            .extract(from: content, sourceName: "program.pdf")
            .first { $0.relatedDocumentType == .sop }

        XCTAssertEqual(sop?.status, .humanReview)
        XCTAssertTrue(sop?.detail.contains("Optional") == true)
    }
}
