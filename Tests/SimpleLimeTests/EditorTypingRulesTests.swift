import XCTest
@testable import SimpleLime

final class EditorTypingRulesTests: XCTestCase {
    func testQuotesAutoCloseOnlyAtWhitespaceBoundaryOrSelection() {
        let text = "hello world" as NSString

        XCTAssertFalse(
            EditorTypingRules.shouldAutoCloseQuote("'", text: text, range: NSRange(location: 5, length: 0))
        )
        XCTAssertFalse(
            EditorTypingRules.shouldAutoCloseQuote("\"", text: text, range: NSRange(location: 11, length: 0))
        )
        XCTAssertTrue(
            EditorTypingRules.shouldAutoCloseQuote("\"", text: text, range: NSRange(location: 6, length: 0))
        )
        XCTAssertTrue(
            EditorTypingRules.shouldAutoCloseQuote("'", text: text, range: NSRange(location: 0, length: 0))
        )
        XCTAssertTrue(
            EditorTypingRules.shouldAutoCloseQuote("'", text: text, range: NSRange(location: 0, length: 5))
        )
    }

    func testMarkdownListLinesAreDetectedFromAnyCursorPosition() {
        let text = "- item\nplain\n  1. nested\n> quote" as NSString

        XCTAssertTrue(
            EditorTypingRules.containsMarkdownListLine(text: text, ranges: [NSRange(location: 2, length: 0)])
        )
        XCTAssertFalse(
            EditorTypingRules.containsMarkdownListLine(text: text, ranges: [NSRange(location: 8, length: 0)])
        )
        XCTAssertTrue(
            EditorTypingRules.containsMarkdownListLine(text: text, ranges: [NSRange(location: 16, length: 0)])
        )
        XCTAssertTrue(
            EditorTypingRules.containsMarkdownListLine(text: text, ranges: [NSRange(location: text.length - 1, length: 0)])
        )
    }
}
