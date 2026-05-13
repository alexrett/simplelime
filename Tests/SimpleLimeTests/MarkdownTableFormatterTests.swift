import XCTest
@testable import SimpleLime

final class MarkdownTableFormatterTests: XCTestCase {
    func testFormatsMarkdownTableBlocks() {
        let input =
        """
        before
        |name|role|
        |---|:---:|
        |Ada|engineer|
        |Li|PM|
        after
        """

        let output =
        """
        before
        | name |   role   |
        | ---- | :------: |
        | Ada  | engineer |
        | Li   |    PM    |
        after
        """

        XCTAssertEqual(MarkdownTableFormatter.format(input), output)
    }

    func testPreservesIndentedTablesAndTrailingNewline() {
        let input = "  | a | bb |\n  | --- | ---: |\n  | x | 12 |\n"
        let output = "  | a   |  bb |\n  | --- | --: |\n  | x   |  12 |\n"

        XCTAssertEqual(MarkdownTableFormatter.format(input), output)
    }

    func testLeavesNonTablePipeTextUntouched() {
        let input = "Use foo | bar inline.\n| missing separator | row |"

        XCTAssertEqual(MarkdownTableFormatter.format(input), input)
    }
}
