import XCTest
@testable import SimpleLime

final class MarkdownPreviewParserTests: XCTestCase {
    func testVisualFixturePreviewParserRecognizesTyporaStyleBlocks() throws {
        let fixtureURL = repositoryRootURL()
            .appendingPathComponent("docs/markdown-visual-fixture.md")
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)
        let document = MarkdownPreviewParser.parseDocument(markdown)

        XCTAssertTrue(document.blocks.contains { block in
            if case .frontMatter(let value) = block.kind {
                return value.contains("title: SimpleLime Markdown Visual Fixture")
            }
            return false
        })
        XCTAssertTrue(document.blocks.contains { block in
            if case .toc = block.kind { return true }
            return false
        })
        XCTAssertEqual(document.blocks.filter { block in
            if case .diagram = block.kind { return true }
            return false
        }.count, 2)
        XCTAssertTrue(document.blocks.contains { block in
            if case .math(let value) = block.kind {
                return value.contains("\\frac")
            }
            return false
        })
        XCTAssertTrue(document.blocks.contains { block in
            if case .table(let table) = block.kind {
                return table.headers == ["Feature", "Expected rendering", "Status"]
                    && table.alignments == [.leading, .center, .trailing]
            }
            return false
        })
        XCTAssertTrue(document.blocks.contains { block in
            if case .htmlMedia(let media) = block.kind {
                return media.tag == "video" && media.source == "https://example.com/movie.mp4"
            }
            return false
        })
        XCTAssertTrue(document.blocks.contains { block in
            if case .htmlMedia(let media) = block.kind {
                return media.tag == "iframe" && media.source == "https://example.com"
            }
            return false
        })
        XCTAssertEqual(document.blocks.filter { block in
            if case .footnoteDefinition = block.kind { return true }
            return false
        }.count, 2)
        XCTAssertEqual(document.blocks.filter { block in
            if case .linkReference = block.kind { return true }
            return false
        }.count, 2)

        let imageSources = document.blocks.compactMap { block -> String? in
            if case .image(let image) = block.kind {
                return image.source
            }
            return nil
        }
        XCTAssertTrue(imageSources.contains("assets/simplelime-sample.svg"))
        XCTAssertTrue(imageSources.contains("assets/image with spaces.svg"))
        XCTAssertTrue(imageSources.contains("assets/simplelime-wide.svg"))
        XCTAssertEqual(document.references["docs-ref"]?.source, "https://example.com/docs")
        XCTAssertEqual(document.references["sample-image"]?.source, "assets/simplelime-wide.svg")

        XCTAssertTrue(document.blocks.contains { block in
            if case .unorderedList(let items) = block.kind {
                return items.contains { $0.text == "Nested unordered child" && $0.indentLevel == 1 }
                    && items.contains { $0.text == "Nested child with ==highlight==" && $0.indentLevel == 1 }
            }
            return false
        })
        XCTAssertTrue(document.blocks.contains { block in
            if case .orderedList(let items) = block.kind {
                return items.contains { $0.text == "Nested ordered child" && $0.indentLevel == 1 }
                    && items.contains { $0.text == "Nested ordered sibling" && $0.indentLevel == 1 }
            }
            return false
        })
    }

    func testInlineRendererResolvesReferencesAutolinksAndSafeHTML() {
        let references = [
            "docs ref": MarkdownLinkReference(
                label: "Docs Ref",
                key: "docs ref",
                source: "https://example.com/docs",
                title: "Docs"
            ),
            "sample image": MarkdownLinkReference(
                label: "sample image",
                key: "sample image",
                source: "assets/image with spaces.svg",
                title: nil
            )
        ]

        let markdown = MarkdownPreviewInlineRenderer.markdown(
            "Read [docs][Docs Ref], see ![Sample][sample image], open <https://example.com>, use <u>underline</u>, press <kbd>Cmd K</kbd>, math $a+b$, mark ==new==, and footnote[^one].",
            references: references
        )

        XCTAssertTrue(markdown.contains("[docs](https://example.com/docs)"), markdown)
        XCTAssertTrue(markdown.contains("[Sample](<assets/image with spaces.svg>)"), markdown)
        XCTAssertTrue(markdown.contains("[https://example.com](https://example.com)"), markdown)
        XCTAssertTrue(markdown.contains("underline"), markdown)
        XCTAssertTrue(markdown.contains("Cmd K"), markdown)
        XCTAssertTrue(markdown.contains("math a+b"), markdown)
        XCTAssertTrue(markdown.contains("mark new"), markdown)
        XCTAssertTrue(markdown.contains("footnote[one]"), markdown)
        XCTAssertFalse(markdown.contains("<u>"), markdown)
        XCTAssertFalse(markdown.contains("<kbd>"), markdown)
        XCTAssertFalse(markdown.contains("$a+b$"), markdown)
        XCTAssertFalse(markdown.contains("==new=="), markdown)
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
