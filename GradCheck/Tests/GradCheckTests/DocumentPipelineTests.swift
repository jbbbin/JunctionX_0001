import Foundation
import XCTest
@testable import GradCheck

final class DocumentPipelineTests: XCTestCase {
    func testExtractsPlainTextWithoutNetworkConnection() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gradcheck-pipeline-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "MIT EECS application statement".write(to: url, atomically: true, encoding: .utf8)

        let pipeline = DocumentPipeline(environment: [:])
        let result = try await pipeline.extract(from: url)

        XCTAssertEqual(result.pageCount, 1)
        XCTAssertTrue(result.text.contains("MIT EECS"))
        XCTAssertTrue(result.provider.contains("온디바이스"))
        XCTAssertFalse(pipeline.isUpstageConnected)
    }

    func testUpstageElementsAreGroupedByActualSourcePage() throws {
        let result = try parseUpstageFixture(
            #"""
            {
              "content": { "text": "global fallback must not win" },
              "usage": { "pages": 3 },
              "elements": [
                {
                  "page": 3,
                  "content": {
                    "text": "Page three first",
                    "markdown": "# ignored markdown"
                  }
                },
                {
                  "page": 1,
                  "content": { "markdown": "# Page one" }
                },
                {
                  "page": 3,
                  "content": { "html": "<p>Page three second</p>" }
                }
              ]
            }
            """#
        )

        XCTAssertEqual(result.pages, ["# Page one", "Page three first\n\n<p>Page three second</p>"])
        XCTAssertEqual(result.sourcePageNumbers, [1, 3])
        XCTAssertFalse(result.text.contains("global fallback"))
    }

    func testUpstageElementWithoutPageKeepsUnknownProvenance() throws {
        let result = try parseUpstageFixture(
            #"""
            {
              "elements": [
                { "page": "2", "content": { "text": "Known page" } },
                { "content": { "text": "Unknown page" } }
              ]
            }
            """#
        )

        XCTAssertEqual(result.pages, ["Known page", "Unknown page"])
        XCTAssertEqual(result.sourcePageNumbers, [2, nil])
    }

    func testUpstageSinglePageGlobalContentUsesConfirmedUsagePage() throws {
        let result = try parseUpstageFixture(
            #"""
            {
              "content": {
                "text": "One page text",
                "markdown": "# ignored markdown"
              },
              "usage": { "pages": 1 }
            }
            """#
        )

        XCTAssertEqual(result.pages, ["One page text"])
        XCTAssertEqual(result.sourcePageNumbers, [1])
    }

    func testUpstageGlobalNumberedMarkersPreserveSourcePagesWhenUsageMatches() throws {
        let result = try parseUpstageFixture(
            #"""
            {
              "content": {
                "markdown": "--- page 7 ---\nSeventh page\n--- page 8 ---\nEighth page"
              },
              "usage": { "pages": 2 }
            }
            """#
        )

        XCTAssertEqual(result.pages, ["Seventh page", "Eighth page"])
        XCTAssertEqual(result.sourcePageNumbers, [7, 8])
    }

    func testUpstageSingleNumberedMarkerKeepsItsExplicitSourcePage() throws {
        let result = try parseUpstageFixture(
            #"""
            {
              "content": { "text": "--- page 7 ---\nOnly selected page" },
              "usage": { "pages": 1 }
            }
            """#
        )

        XCTAssertEqual(result.pages, ["Only selected page"])
        XCTAssertEqual(result.sourcePageNumbers, [7])
    }

    func testUpstageGlobalSplitKeepsNilPagesWhenUsageDoesNotMatch() throws {
        let result = try parseUpstageFixture(
            #"""
            {
              "content": {
                "markdown": "--- page 1 ---\nFirst page\n--- page 2 ---\nSecond page"
              },
              "usage": { "pages": 3 }
            }
            """#
        )

        XCTAssertEqual(result.pages, ["First page", "Second page"])
        XCTAssertEqual(result.sourcePageNumbers, [nil, nil])
    }

    func testUpstageUnsplitGlobalContentDoesNotInventPageForMultiPageUsage() throws {
        let result = try parseUpstageFixture(
            #"""
            {
              "content": { "text": "No trustworthy page delimiter" },
              "usage": { "pages": 2 }
            }
            """#
        )

        XCTAssertEqual(result.pages, ["No trustworthy page delimiter"])
        XCTAssertEqual(result.sourcePageNumbers, [nil])
    }

    private func parseUpstageFixture(_ json: String) throws -> ExtractedDocument {
        try UpstageDocumentService.extractedDocument(from: Data(json.utf8))
    }
}
