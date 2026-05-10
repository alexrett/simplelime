import AppKit
import XCTest
@testable import SimpleLime

@MainActor
final class SyntaxHighlighterTests: XCTestCase {
    func testMarkdownFenceContentDoesNotBecomeOneInlineCodeRange() {
        let markdown =
            """
            ```mermaid
            graph LR
              A --> B
            ```

            `inline`
            """
        let textView = NSTextView()
        textView.string = markdown

        SyntaxHighlighter.apply(to: textView, language: .markdown, fontSize: 14)

        let nsText = markdown as NSString
        let fencedContentRange = nsText.range(of: "graph LR")
        let inlineCodeRange = nsText.range(of: "`inline`")

        XCTAssertFalse(color(at: fencedContentRange.location, in: textView)?.isEqual(NSColor.systemPurple) == true)
        XCTAssertTrue(color(at: inlineCodeRange.location, in: textView)?.isEqual(NSColor.systemPurple) == true)
    }

    func testMarkdownPatternsAreIgnoredInsideFencesAndAppliedOutside() {
        let markdown =
            """
            ```markdown
            # Not a heading
            - Not a list item
            ```

            # Real heading
            - Real list item
            """
        let textView = NSTextView()
        textView.string = markdown

        SyntaxHighlighter.apply(to: textView, language: .markdown, fontSize: 14)

        let nsText = markdown as NSString
        let fencedHeadingRange = nsText.range(of: "# Not a heading")
        let realHeadingRange = nsText.range(of: "# Real heading")
        let fencedListRange = nsText.range(of: "- Not a list item")
        let realListRange = nsText.range(of: "- Real list item")

        XCTAssertFalse(color(at: fencedHeadingRange.location, in: textView)?.isEqual(NSColor.systemBlue) == true)
        XCTAssertTrue(color(at: realHeadingRange.location, in: textView)?.isEqual(NSColor.systemBlue) == true)
        XCTAssertFalse(color(at: fencedListRange.location, in: textView)?.isEqual(NSColor.systemOrange) == true)
        XCTAssertTrue(color(at: realListRange.location, in: textView)?.isEqual(NSColor.systemOrange) == true)
    }

    func testMarkdownCodeFenceCanHighlightNestedLanguageWithoutBleedingPastFence() {
        let markdown =
            """
            ```swift
            struct Note {
              let title: String
            }
            ```

            plain
            """
        let textView = NSTextView()
        textView.string = markdown

        SyntaxHighlighter.apply(to: textView, language: .markdown, fontSize: 14)

        let nsText = markdown as NSString
        let keywordRange = nsText.range(of: "struct")
        let afterFenceRange = nsText.range(of: "plain")

        XCTAssertTrue(color(at: keywordRange.location, in: textView)?.isEqual(NSColor.systemBlue) == true)
        XCTAssertFalse(color(at: afterFenceRange.location, in: textView)?.isEqual(NSColor.systemBlue) == true)
    }

    private func color(at location: Int, in textView: NSTextView) -> NSColor? {
        textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }
}
