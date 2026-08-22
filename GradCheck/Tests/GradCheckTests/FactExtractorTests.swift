import XCTest
@testable import GradCheck

final class FactExtractorTests: XCTestCase {
    private let extractor = FactExtractor()

    func testKeepsSourcePageNumberAndOriginalExcerpt() {
        let document = DocumentItem(type: .transcript, filename: "transcript.txt")
        let content = ExtractedDocument(
            pages: ["Student Name: KIM, JI YOON"],
            provider: "test",
            sourcePageNumbers: [7]
        )

        let facts = extractor.extract(document: document, content: content)

        XCTAssertEqual(facts.names.first?.page, 7)
        XCTAssertEqual(facts.names.first?.excerpt, "Student Name: KIM, JI YOON")
    }

    func testNameOrderAndSyllableSpacingArePlausibleNotExact() {
        XCTAssertEqual(extractor.nameComparison("Jiyoon Kim", "KIM, JI YOON"), .plausible)
        XCTAssertEqual(extractor.nameComparison("Jiyoon Kim", "Jiyoon Kim"), .exact)
        XCTAssertEqual(extractor.nameComparison("Jiyoon Kim", "Bob Park"), .different)
    }

    func testEducationPhDWithoutApplicationContextIsNotTargetDegree() {
        let document = DocumentItem(type: .cv, filename: "cv.txt")
        let content = ExtractedDocument(
            pages: ["Education\nPhD in Physics, Stanford University, 2024"],
            provider: "test"
        )

        let facts = extractor.extract(document: document, content: content)

        XCTAssertTrue(facts.targetDegrees.isEmpty)
    }

    func testExtractsCumulativeGPAButNotMajorGPA() {
        let document = DocumentItem(type: .transcript, filename: "transcript.txt")
        let content = ExtractedDocument(
            pages: ["Major GPA: 3.95\nCumulative GPA: 3.82 / 4.50"],
            provider: "test"
        )

        let facts = extractor.extract(document: document, content: content)

        XCTAssertEqual(facts.gpas.count, 1)
        XCTAssertEqual(facts.gpas.first?.value, "3.82 / 4.50")
        XCTAssertEqual(facts.gpas.first?.normalized, "3.82/4.5")
    }

    func testCVDateRangeUsesTheLastMonthAsGraduationDate() {
        let document = DocumentItem(type: .cv, filename: "cv.txt")
        let content = ExtractedDocument(
            pages: ["B.S. in Computer Science · Korea University · Sep 2021 – Feb 2025"],
            provider: "test"
        )

        let facts = extractor.extract(document: document, content: content)

        XCTAssertEqual(facts.graduationDates.first?.normalized, "2025-02")
    }

    func testTranscriptConferredDateKeepsDayPrecision() {
        let document = DocumentItem(type: .transcript, filename: "transcript.txt")
        let content = ExtractedDocument(
            pages: ["Degree conferred: Bachelor of Science · August 22, 2025"],
            provider: "test"
        )

        let facts = extractor.extract(document: document, content: content)

        XCTAssertEqual(facts.graduationDates.first?.normalized, "2025-08-22")
    }
}
