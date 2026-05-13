import XCTest
@testable import SimpleLime

final class StructuredTextFolderTests: XCTestCase {
    func testMarkdownRangesFollowHeadingsAndIgnoreFencedHeadings() {
        let text = """
        # A
        intro
        ## B
        body
        ```
        # ignored
        ```
        # C
        end
        """

        let ranges = StructuredTextFolder.foldableRanges(in: text, language: .markdown)

        XCTAssertTrue(ranges.contains(StructuredFoldRange(startLine: 1, endLine: 7, title: "A")))
        XCTAssertTrue(ranges.contains(StructuredFoldRange(startLine: 3, endLine: 7, title: "B")))
        XCTAssertTrue(ranges.contains(StructuredFoldRange(startLine: 8, endLine: 9, title: "C")))
        XCTAssertFalse(ranges.contains { $0.title == "ignored" })
    }

    func testJSONRangesIgnoreBracesInsideStrings() {
        let text = """
        {
          "message": "{ not a block }",
          "items": [
            {
              "name": "one"
            }
          ]
        }
        """

        let ranges = StructuredTextFolder.foldableRanges(in: text, language: .json)

        XCTAssertTrue(ranges.contains(StructuredFoldRange(startLine: 1, endLine: 8, title: "{")))
        XCTAssertTrue(ranges.contains(StructuredFoldRange(startLine: 3, endLine: 7, title: "\"items\": [")))
        XCTAssertTrue(ranges.contains(StructuredFoldRange(startLine: 4, endLine: 6, title: "{")))
        XCTAssertEqual(ranges.count, 3)
    }

    func testYAMLRangesFollowIndentedBlocks() {
        let text = """
        root:
          child:
            value: 1
          sibling: true
        next: 2
        """

        let ranges = StructuredTextFolder.foldableRanges(in: text, language: .yaml)

        XCTAssertTrue(ranges.contains(StructuredFoldRange(startLine: 1, endLine: 4, title: "root:")))
        XCTAssertTrue(ranges.contains(StructuredFoldRange(startLine: 2, endLine: 3, title: "child:")))
    }

    func testFoldedTextKeepsFirstLineAndSummarizesHiddenLines() {
        let text = """
        # A
        intro
        ## B
        body
        """
        let folded = StructuredTextFolder.foldedText(
            for: text,
            foldedRanges: [StructuredFoldRange(startLine: 1, endLine: 4, title: "A")]
        )

        XCTAssertEqual(folded, "# A  ... 3 lines folded\n")
    }

    func testFoldedLineNumberMappingSkipsHiddenLines() {
        let foldedRanges = [
            StructuredFoldRange(startLine: 2, endLine: 4, title: "A"),
            StructuredFoldRange(startLine: 6, endLine: 8, title: "B")
        ]

        XCTAssertEqual(
            (1...9).map {
                StructuredTextFolder.displayLineNumber(forSourceLine: $0, foldedRanges: foldedRanges)
            },
            [1, 2, 2, 2, 3, 4, 4, 4, 5]
        )
        XCTAssertEqual(
            (1...5).map {
                StructuredTextFolder.sourceLineNumber(forDisplayLine: $0, foldedRanges: foldedRanges)
            },
            [1, 2, 5, 6, 9]
        )
    }
}
