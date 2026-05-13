import XCTest
@testable import SimpleLime

final class TextDiffTests: XCTestCase {
    func testUnifiedDiffMarksInsertedAndDeletedLines() {
        let diff = TextDiff.unifiedDiff(
            from: .init(title: "old.txt", text: "alpha\nbeta\ngamma\n"),
            to: .init(title: "new.txt", text: "alpha\nbravo\ngamma\n")
        )

        XCTAssertTrue(diff.contains("--- old.txt"), diff)
        XCTAssertTrue(diff.contains("+++ new.txt"), diff)
        XCTAssertTrue(diff.contains(" alpha"), diff)
        XCTAssertTrue(diff.contains("-beta"), diff)
        XCTAssertTrue(diff.contains("+bravo"), diff)
        XCTAssertTrue(diff.contains(" gamma"), diff)
    }

    func testUnifiedDiffReportsNoDifferences() {
        XCTAssertEqual(
            TextDiff.unifiedDiff(
                from: .init(title: "one", text: "same\n"),
                to: .init(title: "two", text: "same\n")
            ),
            "No differences between one and two.\n"
        )
    }

    func testUnifiedDiffPreviewReportsTruncatedInputs() {
        let diff = TextDiff.unifiedDiffPreview(
            from: .init(
                title: "old.txt",
                text: "same\n",
                originalByteCount: 10_000,
                originalLineCount: nil,
                isTruncated: true
            ),
            to: .init(
                title: "new.txt",
                text: "same\n",
                originalByteCount: 5,
                originalLineCount: 1,
                isTruncated: false
            ),
            limitDescription: "1 MB and 2,000 lines per side"
        )

        XCTAssertTrue(diff.contains("Diff preview limited to 1 MB and 2,000 lines per side."), diff)
        XCTAssertTrue(diff.contains("old.txt showing"), diff)
        XCTAssertTrue(diff.contains("No differences in the rendered preview."), diff)
    }
}
