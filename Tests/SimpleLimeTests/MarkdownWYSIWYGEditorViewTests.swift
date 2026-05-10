import AppKit
import WebKit
import XCTest
@testable import SimpleLime

@MainActor
final class MarkdownWYSIWYGEditorViewTests: XCTestCase {
    func testNormalizingHeadingDoesNotMoveCaretToStart() async throws {
        let webView = try await makeWebView()

        try await evaluate(
            """
            window.simplelimeTest.normalizePlainTextWithCaretAtEnd("# Hello");
            """,
            in: webView
        )
        try await waitForEditorFrame()

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let offset = try await evaluateInt("window.simplelimeTest.lastRestoredCaretOffset();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(html.contains("<h1>Hello</h1>"), html)
        XCTAssertEqual(markdown, "# Hello")
        XCTAssertGreaterThan(offset, 0)
    }

    func testNormalizingMermaidFenceDoesNotMoveCaretToStart() async throws {
        let webView = try await makeWebView()

        try await evaluate(
            """
            window.simplelimeTest.normalizePlainTextWithCaretAtEnd("```mermaid\\ngraph TD\\n  A-->B\\n```");
            """,
            in: webView
        )
        try await waitForEditorFrame()

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let offset = try await evaluateInt("window.simplelimeTest.lastRestoredCaretOffset();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(html.contains("data-md-block=\"diagram\""), html)
        XCTAssertTrue(markdown.contains("```mermaid"), markdown)
        XCTAssertGreaterThan(offset, 0)
    }

    func testTypingMermaidAndMathAutoNormalizesWithoutModeToggle() async throws {
        let webView = try await makeWebView()
        let markdown = Self.javaScriptLiteral(
            """
            ```mermaid
            graph TD
              A-->B
            ```

            $$
            a^2 + b^2 = c^2
            $$
            """
        )

        try await evaluate(
            """
            window.simplelimeTest.setPlainText(\(markdown));
            document.querySelector('#editor').dispatchEvent(new Event('input', { bubbles: true }));
            """,
            in: webView
        )
        try await waitForAutoNormalization()

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let savedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        let diagramHasVisibleContent = try await evaluateBool(
            """
            Boolean(
              document.querySelector('.diagram-render svg') ||
              (document.querySelector('.diagram-render')?.textContent || '').trim().length > 0
            );
            """,
            in: webView
        )
        let mathHasVisibleContent = try await evaluateBool(
            """
            Boolean(
              document.querySelector('.math-render .katex') ||
              (document.querySelector('.math-render')?.textContent || '').trim().length > 0
            );
            """,
            in: webView
        )

        XCTAssertTrue(html.contains("data-md-block=\"diagram\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"math\""), html)
        XCTAssertTrue(savedMarkdown.contains("```mermaid"), savedMarkdown)
        XCTAssertTrue(diagramHasVisibleContent, html)
        XCTAssertTrue(mathHasVisibleContent, html)
    }

    func testTypewriterModeTogglesWysiwygBodyClassWithoutReload() async throws {
        let webView = try await makeWebView(markdown: "A first line\\n\\nA second line", typewriterModeEnabled: true)

        let initiallyEnabled = try await evaluateBool(
            "document.body.classList.contains('typewriter');",
            in: webView
        )

        try await evaluate("window.simplelimeSetTypewriter(false);", in: webView)
        let disabled = try await evaluateBool(
            "document.body.classList.contains('typewriter');",
            in: webView
        )

        try await evaluate("window.simplelimeSetTypewriter(true);", in: webView)
        let enabledAgain = try await evaluateBool(
            "document.body.classList.contains('typewriter');",
            in: webView
        )

        XCTAssertTrue(initiallyEnabled)
        XCTAssertFalse(disabled)
        XCTAssertTrue(enabledAgain)
    }

    func testOfflineMathFallbackRendersStructuredFormula() async throws {
        let webView = try await makeWebView()

        let inline = try await evaluateString(
            #"window.simplelimeTest.fallbackMathHTML("a^2 + \\frac{b}{c} + \\sqrt{x} + \\alpha", false);"#,
            in: webView
        )
        let display = try await evaluateString(
            #"window.simplelimeTest.fallbackMathHTML("\\frac{x_1}{y^2}", true);"#,
            in: webView
        )

        XCTAssertTrue(inline.contains("math-frac"), inline)
        XCTAssertTrue(inline.contains("<sup>2</sup>"), inline)
        XCTAssertTrue(inline.contains("math-sqrt"), inline)
        XCTAssertTrue(inline.contains("α"), inline)
        XCTAssertTrue(display.contains("math-fallback display"), display)
        XCTAssertTrue(display.contains("<sub>1</sub>"), display)
    }

    func testOfflineMermaidFallbackDrawsGraphAndSequenceSVG() async throws {
        let webView = try await makeWebView()
        let graphSource = Self.javaScriptLiteral(
            """
            graph LR
              A[Start] --> B(Result)
            """
        )
        let sequenceSource = Self.javaScriptLiteral(
            """
            sequenceDiagram
              Alice->>Bob: Hello
              Bob-->>Alice: Hi
            """
        )

        let graphSVG = try await evaluateString("window.simplelimeTest.fallbackDiagramSVG(\(graphSource), 'mermaid');", in: webView)
        let sequenceSVG = try await evaluateString("window.simplelimeTest.fallbackDiagramSVG(\(sequenceSource), 'mermaid');", in: webView)

        XCTAssertTrue(graphSVG.contains("data-simplelime-diagram=\"graph\""), graphSVG)
        XCTAssertTrue(graphSVG.contains("Start"), graphSVG)
        XCTAssertTrue(graphSVG.contains("Result"), graphSVG)
        XCTAssertTrue(sequenceSVG.contains("data-simplelime-diagram=\"sequence\""), sequenceSVG)
        XCTAssertTrue(sequenceSVG.contains("Alice"), sequenceSVG)
        XCTAssertTrue(sequenceSVG.contains("Hello"), sequenceSVG)
    }

    func testNormalizingRawHTMLImageRendersFileURLAndDoesNotMoveCaretToStart() async throws {
        let imageURL = try makeTemporaryPNG(named: "Simulator Screenshot - iPhone 17 Pro - 2026-04-03 at 16.05.18.png")
        let webView = try await makeWebView()
        let imagePath = Self.javaScriptLiteral(imageURL.path)

        try await evaluate(
            """
            window.simplelimeTest.normalizePlainTextWithCaretAtEnd("<img src=\\"" + \(imagePath) + "\\" alt=\\"Local\\" style=\\"zoom:25%;\\" />");
            """,
            in: webView
        )
        try await waitForEditorFrame()
        try await waitForImagesToLoad(in: webView)

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        let selectionIsAfterImage = try await evaluateBool(
            """
            (() => {
              const selection = window.getSelection();
              const imageFigure = document.querySelector('figure');
              if (!selection || !selection.rangeCount || !imageFigure) return false;
              const selectionRange = selection.getRangeAt(0);
              const imageRange = document.createRange();
              imageRange.selectNode(imageFigure);
              return selectionRange.compareBoundaryPoints(Range.START_TO_END, imageRange) >= 0;
            })();
            """,
            in: webView
        )

        XCTAssertTrue(html.contains("data-md-block=\"html-image\""), html)
        XCTAssertTrue(html.contains("simplelime-image://local?path="), html)
        XCTAssertTrue(markdown.contains("<img src=\"\(imageURL.path)\""), markdown)
        XCTAssertTrue(selectionIsAfterImage, html)
    }

    func testWysiwygSelectionOffsetCanBeAppliedFromMiniMapJump() async throws {
        let webView = try await makeWebView(markdown: "First\n\nSecond line\n\nThird")

        try await evaluate("window.simplelimeTest.setSelectionTextOffset(8);", in: webView)
        let offset = try await evaluateInt("window.simplelimeTest.selectionTextOffset();", in: webView)

        XCTAssertEqual(offset, 8)
    }

    func testWysiwygSelectionReportsMarkdownRangeLengthForComments() async throws {
        let webView = try await makeWebView(markdown: "Hello world")

        try await evaluate("window.simplelimeTest.selectText('p', 6, 11);", in: webView)
        let location = try await evaluateInt("window.simplelimeTest.selectionTextRange().location;", in: webView)
        let length = try await evaluateInt("window.simplelimeTest.selectionTextRange().length;", in: webView)

        XCTAssertEqual(location, 6)
        XCTAssertEqual(length, 5)
    }

    func testWysiwygSelectionRangeMeasurementDoesNotLeakCaretTokenIntoHeading() async throws {
        let webView = try await makeWebView(markdown: "## Images")

        try await evaluate("window.simplelimeTest.selectText('h2', 0, 6);", in: webView)
        let location = try await evaluateInt("window.simplelimeTest.selectionTextRange().location;", in: webView)
        let length = try await evaluateInt("window.simplelimeTest.selectionTextRange().length;", in: webView)

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertEqual(location, 3)
        XCTAssertEqual(length, 6)
        XCTAssertFalse(html.contains("simplelime-caret"), html)
        XCTAssertEqual(markdown, "## Images")
    }

    func testWysiwygCommentHighlightsRenderWithoutChangingMarkdown() async throws {
        let comment = DocumentComment(
            documentKey: "scratch:test",
            range: SimpleLime.TextRange(location: 6, length: 6),
            quote: "marked"
        )
        let webView = try await makeWebView(markdown: "Hello marked text", comments: [comment], activeCommentID: comment.id)

        let count = try await evaluateInt("window.simplelimeTest.commentHighlightCount();", in: webView)
        let highlightedText = try await evaluateString(
            "document.querySelector('.comment-highlight.is-active')?.textContent || '';",
            in: webView
        )
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(highlightedText, "marked")
        XCTAssertEqual(markdown, "Hello marked text")
    }

    func testWysiwygHeadingCommentHighlightsHeadingNotGeneratedTOC() async throws {
        let markdown = """
        # Fixture

        [toc]

        ## Images

        Body
        """
        let location = (markdown as NSString).range(of: "Images").location
        let comment = DocumentComment(
            documentKey: "scratch:test",
            range: SimpleLime.TextRange(location: location, length: 6),
            quote: "Images"
        )
        let webView = try await makeWebView(markdown: markdown, comments: [comment], activeCommentID: comment.id)

        let highlightedInHeading = try await evaluateBool(
            "document.querySelector('h2 .comment-highlight')?.textContent === 'Images';",
            in: webView
        )
        let highlightedInTOC = try await evaluateBool(
            "Boolean(document.querySelector('[data-md-block=\"toc\"] .comment-highlight'));",
            in: webView
        )
        let headingText = try await evaluateString("document.querySelector('h2')?.textContent || '';", in: webView)
        let savedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(highlightedInHeading)
        XCTAssertFalse(highlightedInTOC)
        XCTAssertEqual(headingText, "Images")
        XCTAssertEqual(savedMarkdown, markdown)
    }

    func testWysiwygWholeHeadingLineCommentStillRendersAsHeading() async throws {
        let markdown = """
        # Fixture

        ## Images

        Body
        """
        let location = (markdown as NSString).range(of: "## Images").location
        let comment = DocumentComment(
            documentKey: "scratch:test",
            range: SimpleLime.TextRange(location: location, length: "## Images".count),
            quote: "## Images"
        )
        let webView = try await makeWebView(markdown: markdown, comments: [comment], activeCommentID: comment.id)

        let highlightedInHeading = try await evaluateBool(
            "document.querySelector('h2 .comment-highlight')?.textContent === 'Images';",
            in: webView
        )
        let renderedAsHeading = try await evaluateBool("Boolean(document.querySelector('h2'));", in: webView)
        let savedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(highlightedInHeading)
        XCTAssertTrue(renderedAsHeading)
        XCTAssertEqual(savedMarkdown, markdown)
    }

    func testWysiwygImageAltCommentHighlightsVisibleCaption() async throws {
        let markdown = #"![Relative local SVG](assets/simplelime-sample.svg "Relative local SVG")"#
        let location = (markdown as NSString).range(of: "Relative").location
        let comment = DocumentComment(
            documentKey: "scratch:test",
            range: SimpleLime.TextRange(location: location, length: "Relative".count),
            quote: "Relative"
        )
        let webView = try await makeWebView(markdown: markdown, comments: [comment], activeCommentID: comment.id)

        let highlightedCaption = try await evaluateBool(
            "document.querySelector('figure[data-md-block=\"image\"] figcaption .comment-highlight')?.textContent === 'Relative';",
            in: webView
        )
        let imageAlt = try await evaluateString(
            "document.querySelector('figure[data-md-block=\"image\"] img')?.getAttribute('alt') || '';",
            in: webView
        )
        let savedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(highlightedCaption)
        XCTAssertEqual(imageAlt, "Relative local SVG")
        XCTAssertEqual(savedMarkdown, markdown)
    }

    func testWysiwygRemoteCollaboratorSelectionRendersWithoutChangingMarkdown() async throws {
        let collaborator = RemoteCollaborator(
            deviceID: "peer-1",
            name: "Peer Mac",
            selectionRanges: [TextRange(location: 6, length: 5)],
            colorIndex: 1,
            lastSeenAt: Date()
        )
        let webView = try await makeWebView(markdown: "Hello world", collaborators: [collaborator])

        let highlightedText = try await evaluateString(
            "document.querySelector('.collab-selection')?.textContent || '';",
            in: webView
        )
        let title = try await evaluateString(
            "document.querySelector('.collab-selection')?.getAttribute('title') || '';",
            in: webView
        )
        let savedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertEqual(highlightedText, "world")
        XCTAssertEqual(title, "Peer Mac")
        XCTAssertEqual(savedMarkdown, "Hello world")
    }

    func testApplyingSelectionOffsetScrollsWysiwygViewportToCaret() async throws {
        let body = (1...120)
            .map { "Paragraph \($0)" }
            .joined(separator: "\n\n")
        let markdown = "\(body)\n\nTarget line"
        let webView = try await makeWebView(markdown: markdown)

        try await evaluate("window.scrollTo(0, 0);", in: webView)
        let initialScrollY = try await evaluateInt("Math.round(Math.max(window.scrollY, document.documentElement.scrollTop, document.body.scrollTop));", in: webView)
        XCTAssertEqual(initialScrollY, 0)

        try await evaluate("window.simplelimeTest.setSelectionTextOffset(\(markdown.utf16.count));", in: webView)
        try await waitForEditorFrame()
        try await waitForEditorFrame()

        let scrolledToSelection = try await evaluateBool(
            """
            (() => {
              const selection = window.getSelection();
              if (!selection || !selection.rangeCount) return false;
              const range = selection.getRangeAt(0);
              const node = range.startContainer;
              const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
              const rect = range.getClientRects()[0] || element?.getBoundingClientRect?.();
              const scrollY = Math.max(window.scrollY, document.documentElement.scrollTop, document.body.scrollTop);
              return scrollY > 0 && rect && rect.top >= 0 && rect.top < window.innerHeight;
            })();
            """,
            in: webView
        )
        let scrollDiagnostic = try await evaluateString(
            """
            JSON.stringify((() => {
              const selection = window.getSelection();
              const range = selection?.rangeCount ? selection.getRangeAt(0) : null;
              const node = range?.startContainer;
              const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
              const rect = range?.getClientRects?.()[0] || element?.getBoundingClientRect?.();
              return {
                scrollY: window.scrollY,
                documentScrollTop: document.documentElement.scrollTop,
                bodyScrollTop: document.body.scrollTop,
                bodyScrollHeight: document.body.scrollHeight,
                documentScrollHeight: document.documentElement.scrollHeight,
                innerHeight: window.innerHeight,
                rectTop: rect?.top ?? null,
                rectBottom: rect?.bottom ?? null,
                offset: window.simplelimeTest.selectionTextOffset()
              };
            })())
            """,
            in: webView
        )

        XCTAssertTrue(scrolledToSelection, scrollDiagnostic)
    }

    func testFindNextSelectionOffsetScrollsWysiwygViewportToMatch() async throws {
        let body = (1...120)
            .map { "Paragraph \($0)" }
            .joined(separator: "\n\n")
        let markdown = "\(body)\n\nNeedle target"
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = markdown
        buffer.language = .markdown
        buffer.selectionRanges = [.zero]
        let store = EditorStore(
            initialBuffers: [buffer],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
        store.findQuery = "Needle"
        store.findNext()

        let foundRange = try XCTUnwrap(store.selectedBuffer?.selectionRanges.first)
        XCTAssertEqual((markdown as NSString).substring(with: foundRange.nsRange), "Needle")

        let webView = try await makeWebView(markdown: markdown)
        try await evaluate("window.scrollTo(0, 0);", in: webView)
        try await evaluate("window.simplelimeTest.setSelectionTextOffset(\(foundRange.location));", in: webView)
        try await waitForEditorFrame()
        try await waitForEditorFrame()

        let scrolledToFindMatch = try await evaluateBool(
            """
            (() => {
              const selection = window.getSelection();
              if (!selection || !selection.rangeCount) return false;
              const range = selection.getRangeAt(0);
              const node = range.startContainer;
              const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
              const rect = range.getClientRects()[0] || element?.getBoundingClientRect?.();
              const scrollY = Math.max(window.scrollY, document.documentElement.scrollTop, document.body.scrollTop);
              return window.simplelimeTest.selectionTextOffset() === \(foundRange.location) &&
                scrollY > 0 &&
                rect &&
                rect.top >= 0 &&
                rect.top < window.innerHeight;
            })();
            """,
            in: webView
        )
        let diagnostic = try await evaluateString(
            """
            JSON.stringify((() => {
              const selection = window.getSelection();
              const range = selection?.rangeCount ? selection.getRangeAt(0) : null;
              const node = range?.startContainer;
              const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
              const rect = range?.getClientRects?.()[0] || element?.getBoundingClientRect?.();
              return {
                expectedOffset: \(foundRange.location),
                actualOffset: window.simplelimeTest.selectionTextOffset(),
                scrollY: window.scrollY,
                documentScrollTop: document.documentElement.scrollTop,
                bodyScrollTop: document.body.scrollTop,
                innerHeight: window.innerHeight,
                rectTop: rect?.top ?? null,
                rectBottom: rect?.bottom ?? null
              };
            })())
            """,
            in: webView
        )

        XCTAssertTrue(scrolledToFindMatch, diagnostic)
    }

    func testRenderedSelectionReportsMarkdownSourceOffset() async throws {
        let markdown =
            """
            # Heading

            Intro with **bold** text.

            Final Needle target
            """
        let expectedOffset = try XCTUnwrap(markdown.range(of: "Needle")).lowerBound.utf16Offset(in: markdown)
        let webView = try await makeWebView(markdown: markdown)

        try await evaluate(
            """
            (() => {
              const textNode = Array.from(document.querySelectorAll('#editor p'))
                .flatMap(paragraph => Array.from(paragraph.childNodes))
                .find(node => node.nodeType === Node.TEXT_NODE && node.textContent.includes('Needle'));
              const range = document.createRange();
              range.setStart(textNode, textNode.textContent.indexOf('Needle'));
              range.collapse(true);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
            })();
            """,
            in: webView
        )

        let actualOffset = try await evaluateInt("window.simplelimeTest.selectionTextOffset();", in: webView)

        XCTAssertEqual(actualOffset, expectedOffset)
    }

    func testSelectionOffsetInsideRenderedAtomicBlocksDoesNotEnterHiddenSource() async throws {
        let markdown =
            """
            Intro

            ```mermaid
            graph TD
              A-->B
            ```

            $$
            a^2 + b^2 = c^2
            $$

            After
            """
        let webView = try await makeWebView(markdown: markdown)

        try await evaluate("window.simplelimeTest.setSelectionTextOffset(\(markdown.firstRange(of: "graph TD")!.lowerBound.utf16Offset(in: markdown) + 2));", in: webView)
        let diagramSelectionIsVisible = try await evaluateBool(
            """
            (() => {
              const selection = window.getSelection();
              if (!selection || !selection.rangeCount) return false;
              const node = selection.anchorNode;
              const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
              if (element?.closest('figure[data-md-block="diagram"] > pre, .diagram-render, .math-render')) return false;
              const figure = document.querySelector('figure[data-md-block="diagram"]');
              const selectionRange = selection.getRangeAt(0);
              const figureRange = document.createRange();
              figureRange.selectNode(figure);
              return selectionRange.compareBoundaryPoints(Range.START_TO_END, figureRange) >= 0;
            })();
            """,
            in: webView
        )

        try await evaluate("window.simplelimeTest.setSelectionTextOffset(\(markdown.firstRange(of: "a^2")!.lowerBound.utf16Offset(in: markdown) + 2));", in: webView)
        let mathSelectionIsVisible = try await evaluateBool(
            """
            (() => {
              const selection = window.getSelection();
              if (!selection || !selection.rangeCount) return false;
              const node = selection.anchorNode;
              const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
              if (element?.closest('figure[data-md-block="math"] > pre, .diagram-render, .math-render')) return false;
              const figure = document.querySelector('figure[data-md-block="math"]');
              const selectionRange = selection.getRangeAt(0);
              const figureRange = document.createRange();
              figureRange.selectNode(figure);
              return selectionRange.compareBoundaryPoints(Range.START_TO_END, figureRange) >= 0;
            })();
            """,
            in: webView
        )

        XCTAssertTrue(diagramSelectionIsVisible)
        XCTAssertTrue(mathSelectionIsVisible)
    }

    func testAbsoluteMarkdownImageWithSpacesLoadsThroughLocalImageScheme() async throws {
        let imageURL = try makeTemporaryPNG(named: "wortkessel image 11.png")
        let webView = try await makeWebView()
        let markdownImage = Self.javaScriptLiteral("![wortkessel image 11](\(imageURL.path))")

        try await evaluate(
            """
            window.simplelimeTest.normalizePlainTextWithCaretAtEnd(\(markdownImage));
            """,
            in: webView
        )
        try await waitForEditorFrame()
        try await waitForImagesToLoad(in: webView)

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(html.contains("data-md-block=\"image\""), html)
        XCTAssertTrue(html.contains("simplelime-image://local?path="), html)
        XCTAssertFalse(html.contains("<figcaption>wortkessel image 11</figcaption>"), html)
        XCTAssertTrue(markdown.contains("![wortkessel image 11](\(imageURL.path))"), markdown)
    }

    func testRelativeMarkdownImageLoadsThroughLocalImageScheme() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let imageURL = try makeTemporaryPNG(named: "relative image.png", directoryURL: directoryURL)
        let webView = try await makeWebView(baseURL: directoryURL)

        try await evaluate(
            """
            window.simplelimeTest.normalizePlainTextWithCaretAtEnd("![Relative](relative image.png)");
            """,
            in: webView
        )
        try await waitForEditorFrame()
        try await waitForImagesToLoad(in: webView)

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(html.contains("data-md-block=\"image\""), html)
        XCTAssertTrue(html.contains("simplelime-image://local?path="), html)
        XCTAssertTrue(markdown.contains("![Relative](relative image.png)"), markdown)

        let decodedPath = LocalImageSchemeHandler.filePath(from: URL(string: try await evaluateString("document.querySelector('figure img').src;", in: webView))!)
        XCTAssertEqual(decodedPath, imageURL.path)
    }

    func testTypingMarkdownImageAutoNormalizesAndLoadsWithoutModeToggle() async throws {
        let imageURL = try makeTemporaryPNG(named: "live typed image.png")
        let webView = try await makeWebView()
        let markdownImage = Self.javaScriptLiteral("![Live typed image](\(imageURL.path))")

        try await evaluate(
            """
            window.simplelimeTest.setPlainText(\(markdownImage));
            document.querySelector('#editor').dispatchEvent(new Event('input', { bubbles: true }));
            """,
            in: webView
        )
        try await waitForAutoNormalization()
        try await waitForImagesToLoad(in: webView)

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        let imageLoaded = try await evaluateBool("document.querySelector('figure img')?.naturalWidth > 0;", in: webView)

        XCTAssertTrue(html.contains("data-md-block=\"image\""), html)
        XCTAssertTrue(html.contains("simplelime-image://local?path="), html)
        XCTAssertTrue(markdown.contains("![Live typed image](\(imageURL.path))"), markdown)
        XCTAssertTrue(imageLoaded, html)
    }

    func testInsertedRelativeImageMarkdownLoadsFromDocumentAssets() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let assetsURL = directoryURL.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        _ = try makeTemporaryPNG(named: "pasted-image.png", directoryURL: assetsURL)

        let webView = try await makeWebView(baseURL: directoryURL)
        try await evaluate(
            """
            window.simplelimeTest.insertImageMarkdown('assets/pasted-image.png', 'pasted image');
            """,
            in: webView
        )
        try await waitForAutoNormalization()
        try await waitForImagesToLoad(in: webView)

        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        let source = try await evaluateString("document.querySelector('figure img').getAttribute('src');", in: webView)

        XCTAssertTrue(markdown.contains("![pasted image](assets/pasted-image.png)"), markdown)
        XCTAssertTrue(source.contains("simplelime-image://local?path="), source)
    }

    func testPastedImageDataURLIsSavedToAssetsWithRelativeMarkdownPath() throws {
        let directoryURL = try makeTemporaryDirectory()
        let imageURL = try makeTemporaryPNG(named: "Screenshot From Clipboard.PNG")
        let data = try Data(contentsOf: imageURL)
        let dataURL = "data:image/png;base64,\(data.base64EncodedString())"

        let relativePath = try MarkdownWYSIWYGEditorView.savePastedImage(
            dataURL: dataURL,
            originalName: "Screenshot From Clipboard.PNG",
            mimeType: "image/png",
            baseURL: directoryURL
        )

        XCTAssertEqual(relativePath, "assets/screenshot-from-clipboard.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(relativePath).path))
    }

    func testTableCalloutAndMathNormalizeWithoutCaretReset() async throws {
        let webView = try await makeWebView()
        let markdown = Self.javaScriptLiteral(
            """
            | Word | Translation |
            | --- | --- |
            | der Apfel | apple |

            > [!NOTE]
            > Check plural forms

            $$
            a^2 + b^2 = c^2
            $$
            """
        )

        try await evaluate(
            """
            window.simplelimeTest.normalizePlainTextWithCaretAtEnd(\(markdown));
            """,
            in: webView
        )
        try await waitForEditorFrame()

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let offset = try await evaluateInt("window.simplelimeTest.lastRestoredCaretOffset();", in: webView)

        XCTAssertTrue(html.contains("data-md-block=\"table\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"callout\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"math\""), html)
        XCTAssertGreaterThan(offset, 0)
    }

    func testEditingRenderedHeadingUpdatesMarkdown() async throws {
        let webView = try await makeWebView(markdown: "# Old title\n\nBody")

        try await evaluate(
            """
            document.querySelector('h1').textContent = 'New title';
            """,
            in: webView
        )

        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        XCTAssertTrue(markdown.contains("# New title"), markdown)
        XCTAssertTrue(markdown.contains("Body"), markdown)
    }

    func testEditingRenderedTableCellUpdatesMarkdown() async throws {
        let webView = try await makeWebView(
            markdown:
            """
            | Word | Translation |
            | --- | --- |
            | der Apfel | apple |
            """
        )

        try await evaluate(
            """
            document.querySelector('tbody td:nth-child(2)').textContent = 'apple fruit';
            """,
            in: webView
        )

        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        XCTAssertTrue(markdown.contains("| der Apfel | apple fruit |"), markdown)
    }

    func testTableToolbarActionsUpdateMarkdownStructureAndAlignment() async throws {
        let webView = try await makeWebView(
            markdown:
            """
            | Word | Translation |
            | --- | --- |
            | der Apfel | apple |
            """
        )

        let selected = try await evaluateBool("window.simplelimeTest.selectText('tbody td:nth-child(2)', 0, 5);", in: webView)
        XCTAssertTrue(selected)
        let aligned = try await evaluateBool("window.simplelimeTest.tableAction('alignRight');", in: webView)
        let addedColumn = try await evaluateBool("window.simplelimeTest.tableAction('addColumnAfter');", in: webView)
        let reselected = try await evaluateBool("window.simplelimeTest.selectText('tbody td:nth-child(2)', 0, 5);", in: webView)
        let addedRow = try await evaluateBool("window.simplelimeTest.tableAction('addRowAfter');", in: webView)
        XCTAssertTrue(aligned)
        XCTAssertTrue(addedColumn)
        XCTAssertTrue(reselected)
        XCTAssertTrue(addedRow)

        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        let toolbarVisible = try await evaluateBool("document.querySelector('#table-toolbar').classList.contains('is-visible');", in: webView)

        XCTAssertTrue(markdown.contains("| Word | Translation | Column |"), markdown)
        XCTAssertTrue(markdown.contains("| --- | ---: | ---: |"), markdown)
        XCTAssertTrue(markdown.contains("| der Apfel | apple |  |"), markdown)
        XCTAssertTrue(markdown.contains("|  |  |  |"), markdown)
        XCTAssertTrue(toolbarVisible)
    }

    func testNestedListsRenderAndRoundTripWithIndentation() async throws {
        let source =
            """
            - Parent
              - Child
              - [x] Nested task
            - Sibling

            1. First
              1. Ordered child
              2. Ordered sibling
            2. Second
            """
        let webView = try await makeWebView(markdown: source)

        let nestedListCount = try await evaluateInt("document.querySelectorAll('li > ul, li > ol').length;", in: webView)
        let nestedTaskChecked = try await evaluateBool("document.querySelector('li li input[type=\"checkbox\"]')?.checked === true;", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertEqual(nestedListCount, 2)
        XCTAssertTrue(nestedTaskChecked)
        XCTAssertTrue(markdown.contains("- Parent\n  - Child\n  - [x] Nested task\n- Sibling"), markdown)
        XCTAssertTrue(markdown.contains("1. First\n  1. Ordered child\n  2. Ordered sibling\n2. Second"), markdown)
    }

    func testTabAndShiftTabIndentListItemWithoutMovingFocus() async throws {
        let webView = try await makeWebView(
            markdown:
            """
            - Parent
            - Child
            - Sibling
            """
        )

        let selectedChild = try await evaluateBool("window.simplelimeTest.setCaretInListItem(1);", in: webView)
        XCTAssertTrue(selectedChild)
        let tabPrevented = try await evaluateBool("window.simplelimeTest.dispatchKey('Tab');", in: webView)
        let nestedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        let focusStayedInEditor = try await evaluateBool("document.activeElement === document.querySelector('#editor');", in: webView)

        XCTAssertTrue(tabPrevented)
        XCTAssertTrue(focusStayedInEditor)
        XCTAssertTrue(nestedMarkdown.contains("- Parent\n  - Child\n- Sibling"), nestedMarkdown)

        let selectedNestedChild = try await evaluateBool("window.simplelimeTest.setCaretInListItem(1);", in: webView)
        XCTAssertTrue(selectedNestedChild)
        let shiftTabPrevented = try await evaluateBool("window.simplelimeTest.dispatchKey('Tab', { shiftKey: true });", in: webView)
        let outdentedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(shiftTabPrevented)
        XCTAssertTrue(outdentedMarkdown.contains("- Parent\n- Child\n- Sibling"), outdentedMarkdown)
    }

    func testCommandBracketIndentsAndOutdentsListItem() async throws {
        let webView = try await makeWebView(
            markdown:
            """
            - Parent
            - Child
            """
        )

        let selectedChild = try await evaluateBool("window.simplelimeTest.setCaretInListItem(1);", in: webView)
        XCTAssertTrue(selectedChild)
        let indentPrevented = try await evaluateBool("window.simplelimeTest.dispatchKey(']', { metaKey: true });", in: webView)
        let nestedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(indentPrevented)
        XCTAssertTrue(nestedMarkdown.contains("- Parent\n  - Child"), nestedMarkdown)

        let selectedNestedChild = try await evaluateBool("window.simplelimeTest.setCaretInListItem(1);", in: webView)
        XCTAssertTrue(selectedNestedChild)
        let outdentPrevented = try await evaluateBool("window.simplelimeTest.dispatchKey('[', { metaKey: true });", in: webView)
        let outdentedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(outdentPrevented)
        XCTAssertTrue(outdentedMarkdown.contains("- Parent\n- Child"), outdentedMarkdown)
    }

    func testListIndentNoopKeysStayInsideEditor() async throws {
        let webView = try await makeWebView(
            markdown:
            """
            - First
            - Second
            """
        )

        let selectedFirst = try await evaluateBool("window.simplelimeTest.setCaretInListItem(0);", in: webView)
        XCTAssertTrue(selectedFirst)
        let firstTabPrevented = try await evaluateBool("window.simplelimeTest.dispatchKey('Tab');", in: webView)
        let afterFirstTab = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        let focusAfterFirstTab = try await evaluateBool("document.activeElement === document.querySelector('#editor');", in: webView)

        XCTAssertTrue(firstTabPrevented)
        XCTAssertTrue(focusAfterFirstTab)
        XCTAssertEqual(afterFirstTab, "- First\n- Second")

        let selectedFirstAgain = try await evaluateBool("window.simplelimeTest.setCaretInListItem(0);", in: webView)
        XCTAssertTrue(selectedFirstAgain)
        let topShiftTabPrevented = try await evaluateBool("window.simplelimeTest.dispatchKey('Tab', { shiftKey: true });", in: webView)
        let afterShiftTab = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        let focusAfterShiftTab = try await evaluateBool("document.activeElement === document.querySelector('#editor');", in: webView)

        XCTAssertTrue(topShiftTabPrevented)
        XCTAssertTrue(focusAfterShiftTab)
        XCTAssertEqual(afterShiftTab, "- First\n- Second")
    }

    func testEnterOnEmptyListItemExitsList() async throws {
        let webView = try await makeWebView(
            markdown:
            """
            - Parent
            - Child
            """
        )

        try await evaluate(
            """
            const item = document.querySelectorAll('li')[1];
            item.textContent = '';
            window.simplelimeTest.setCaretInListItem(1);
            """,
            in: webView
        )

        let enterPrevented = try await evaluateBool("window.simplelimeTest.dispatchKey('Enter');", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        let caretOutsideList = try await evaluateBool(
            """
            (() => {
              const selection = window.getSelection();
              if (!selection || !selection.rangeCount) return false;
              const node = selection.anchorNode;
              const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
              return !element?.closest('li');
            })();
            """,
            in: webView
        )

        XCTAssertTrue(enterPrevented)
        XCTAssertEqual(markdown, "- Parent")
        XCTAssertTrue(caretOutsideList)
    }

    func testEnterOnNestedListItemCreatesSameLevelBulletAndKeepsFocus() async throws {
        let webView = try await makeWebView(
            markdown:
            """
            - Parent
              - Child
            - Sibling
            """
        )

        let selectedChild = try await evaluateBool("window.simplelimeTest.setCaretInListItem(1);", in: webView)
        XCTAssertTrue(selectedChild)
        let enterPrevented = try await evaluateBool("window.simplelimeTest.dispatchKey('Enter');", in: webView)
        let focusStayedInEditor = try await evaluateBool("document.activeElement === document.querySelector('#editor');", in: webView)
        let nestedItemCount = try await evaluateInt("document.querySelectorAll('li li').length;", in: webView)

        XCTAssertTrue(enterPrevented)
        XCTAssertTrue(focusStayedInEditor)
        XCTAssertEqual(nestedItemCount, 2)

        try await evaluate(
            """
            document.execCommand('insertText', false, 'New child');
            document.querySelector('#editor').dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: 'New child' }));
            """,
            in: webView
        )
        try await waitForEditorFrame()

        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        XCTAssertEqual(markdown, "- Parent\n  - Child\n  - New child\n- Sibling")
    }

    func testEnterOnTaskListCreatesUncheckedSiblingTask() async throws {
        let webView = try await makeWebView(markdown: "- [x] Done")

        let selectedTask = try await evaluateBool("window.simplelimeTest.setCaretInListItem(0);", in: webView)
        XCTAssertTrue(selectedTask)
        let enterPrevented = try await evaluateBool("window.simplelimeTest.dispatchKey('Enter');", in: webView)
        let uncheckedSibling = try await evaluateBool("document.querySelectorAll('li[data-task=\"unchecked\"]').length === 1;", in: webView)

        XCTAssertTrue(enterPrevented)
        XCTAssertTrue(uncheckedSibling)

        try await evaluate(
            """
            document.execCommand('insertText', false, 'Next');
            document.querySelector('#editor').dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: 'Next' }));
            """,
            in: webView
        )
        try await waitForEditorFrame()

        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        XCTAssertEqual(markdown, "- [x] Done\n- [ ] Next")
    }

    func testTogglingRenderedTaskCheckboxUpdatesMarkdown() async throws {
        let webView = try await makeWebView(markdown: "- [ ] Finish WYSIWYG")

        try await evaluate(
            """
            const checkbox = document.querySelector('input[type="checkbox"]');
            checkbox.checked = true;
            checkbox.dispatchEvent(new Event('change', { bubbles: true }));
            """,
            in: webView
        )

        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        XCTAssertEqual(markdown, "- [x] Finish WYSIWYG")
    }

    func testRenderedInlineFormattingRoundTripsToMarkdown() async throws {
        let webView = try await makeWebView(
            markdown: "This is **bold**, *italic*, `code`, and [link](https://example.com)."
        )

        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        XCTAssertEqual(markdown, "This is **bold**, *italic*, `code`, and [link](https://example.com).")
    }

    func testTyporaInlineExtensionsRoundTripToMarkdown() async throws {
        let webView = try await makeWebView(
            markdown: "Use ~~old~~ ==new== H~2~O x^2^ $a+b$ and footnote[^fn]."
        )

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(html.contains("<del>old</del>"), html)
        XCTAssertTrue(html.contains("<mark>new</mark>"), html)
        XCTAssertTrue(html.contains("<sub>2</sub>"), html)
        XCTAssertTrue(html.contains("<sup>2</sup>"), html)
        XCTAssertTrue(html.contains("data-md-inline=\"math\""), html)
        XCTAssertTrue(html.contains("data-md-footnote-ref=\"fn\""), html)
        XCTAssertEqual(markdown, "Use ~~old~~ ==new== H~2~O x^2^ $a+b$ and footnote[^fn].")
    }

    func testReferenceLinksImagesAndAutolinksRoundTrip() async throws {
        let imageURL = try makeTemporaryPNG(named: "reference image.png")
        let webView = try await makeWebView(
            markdown:
            """
            Read [docs][Docs Ref], open <https://example.com>, and see ![Diagram][diagram].

            [Docs Ref]: https://example.com/docs "Docs"
            [diagram]: \(imageURL.path) "Diagram"
            """
        )
        try await waitForImagesToLoad(in: webView)

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(html.contains("data-md-reference-label=\"Docs Ref\""), html)
        XCTAssertTrue(html.contains("data-md-reference-label=\"diagram\""), html)
        XCTAssertTrue(html.contains("simplelime-image://local?path="), html)
        XCTAssertTrue(html.contains("href=\"https://example.com\""), html)
        XCTAssertTrue(markdown.contains("[docs][Docs Ref]"), markdown)
        XCTAssertTrue(markdown.contains("![Diagram][diagram]"), markdown)
        XCTAssertTrue(markdown.contains("[Docs Ref]: https://example.com/docs \"Docs\""), markdown)
        XCTAssertTrue(markdown.contains("[diagram]: \(imageURL.path) \"Diagram\""), markdown)
    }

    func testMarkdownVisualFixtureRendersCoreBlocksAndLocalImages() async throws {
        let rootURL = repositoryRootURL()
        let fixtureURL = rootURL.appendingPathComponent("docs/markdown-visual-fixture.md")
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)
        let webView = try await makeWebView(markdown: markdown, baseURL: fixtureURL.deletingLastPathComponent())

        try await waitForEditorFrame()
        try await waitForImagesToLoad(in: webView)

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let imageCount = try await evaluateInt("document.images.length;", in: webView)
        let brokenImages = try await evaluateInt(
            "Array.from(document.images).filter(image => !image.complete || image.naturalWidth === 0).length;",
            in: webView
        )
        let localImageSources = try await evaluateString(
            "Array.from(document.images).map(image => image.src).filter(src => src.startsWith('simplelime-image://')).join('\\n');",
            in: webView
        )

        XCTAssertTrue(html.contains("data-md-block=\"front-matter\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"toc\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"table\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"diagram\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"math\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"html-image\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"html-media\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"footnote-def\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"link-reference\""), html)
        XCTAssertTrue(html.contains("data-md-footnote-ref=\"inline\""), html)
        XCTAssertTrue(html.contains("data-md-reference-label=\"docs-ref\""), html)
        XCTAssertGreaterThanOrEqual(imageCount, 5)
        XCTAssertEqual(brokenImages, 0, html)
        XCTAssertTrue(localImageSources.contains("simplelime-image://local?path="), localImageSources)
        XCTAssertTrue(localImageSources.contains("image%20with%20spaces.svg"), localImageSources)
    }

    func testTypingVisualFixtureAutoNormalizesWithoutModeToggleOrCaretReset() async throws {
        let rootURL = repositoryRootURL()
        let fixtureURL = rootURL.appendingPathComponent("docs/markdown-visual-fixture.md")
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)
        let webView = try await makeWebView(baseURL: fixtureURL.deletingLastPathComponent())
        let markdownLiteral = Self.javaScriptLiteral(markdown)

        try await evaluate(
            """
            window.simplelimeTest.setPlainText(\(markdownLiteral));
            window.simplelimeTest.setCaretToEnd();
            document.querySelector('#editor').dispatchEvent(new Event('input', { bubbles: true }));
            """,
            in: webView
        )
        try await waitForAutoNormalization()
        try await waitForImagesToLoad(in: webView)

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let savedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        let restoredOffset = try await evaluateInt("window.simplelimeTest.lastRestoredCaretOffset();", in: webView)
        let selectionOffset = try await evaluateInt("window.simplelimeTest.selectionTextOffset();", in: webView)
        let brokenImages = try await evaluateInt(
            "Array.from(document.images).filter(image => !image.complete || image.naturalWidth === 0).length;",
            in: webView
        )
        let diagramHasVisibleContent = try await evaluateBool(
            """
            Boolean(
              document.querySelector('.diagram-render svg') ||
              (document.querySelector('.diagram-render')?.textContent || '').trim().length > 0
            );
            """,
            in: webView
        )
        let mathHasVisibleContent = try await evaluateBool(
            """
            Boolean(
              document.querySelector('.math-render .katex') ||
              (document.querySelector('.math-render')?.textContent || '').trim().length > 0
            );
            """,
            in: webView
        )

        XCTAssertTrue(html.contains("data-md-block=\"front-matter\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"diagram\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"math\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"html-image\""), html)
        XCTAssertEqual(brokenImages, 0, html)
        XCTAssertTrue(diagramHasVisibleContent, html)
        XCTAssertTrue(mathHasVisibleContent, html)
        XCTAssertTrue(savedMarkdown.contains("![Image with spaces](assets/image with spaces.svg"), savedMarkdown)
        XCTAssertTrue(savedMarkdown.contains("```mermaid"), savedMarkdown)
        XCTAssertTrue(savedMarkdown.contains("[^inline]: Footnote definition"), savedMarkdown)
        XCTAssertGreaterThan(restoredOffset, markdown.count / 2)
        XCTAssertGreaterThan(selectionOffset, markdown.count / 2)
    }

    func testSafeInlineHTMLAndMediaRoundTrip() async throws {
        let mediaHTML = #"<video src="https://example.com/movie.mp4" controls></video>"#
        let webView = try await makeWebView(
            markdown:
            """
            Use <u>underline</u> and <kbd>Cmd K</kbd>.

            \(mediaHTML)
            """
        )

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(html.contains("<u>underline</u>"), html)
        XCTAssertTrue(html.contains("<kbd>Cmd K</kbd>"), html)
        XCTAssertTrue(html.contains("data-md-block=\"html-media\""), html)
        XCTAssertTrue(html.contains("<video"), html)
        XCTAssertTrue(markdown.contains("<u>underline</u>"), markdown)
        XCTAssertTrue(markdown.contains("<kbd>Cmd K</kbd>"), markdown)
        XCTAssertTrue(markdown.contains(mediaHTML), markdown)
    }

    func testFrontMatterAndFootnotesAutoNormalizeWithoutModeToggle() async throws {
        let webView = try await makeWebView()
        let markdown = Self.javaScriptLiteral(
            """
            ---
            title: Notes
            tags:
              - typora
            ---

            Body with footnote[^one].

            [^one]: Footnote text
            """
        )

        try await evaluate(
            """
            window.simplelimeTest.setPlainText(\(markdown));
            document.querySelector('#editor').dispatchEvent(new Event('input', { bubbles: true }));
            """,
            in: webView
        )
        try await waitForAutoNormalization()

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let savedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(html.contains("data-md-block=\"front-matter\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"footnote-def\""), html)
        XCTAssertTrue(html.contains("data-md-footnote-ref=\"one\""), html)
        XCTAssertTrue(savedMarkdown.contains("---\ntitle: Notes"), savedMarkdown)
        XCTAssertTrue(savedMarkdown.contains("[^one]: Footnote text"), savedMarkdown)
    }

    func testBoldCommandOnRenderedSelectionUpdatesMarkdown() async throws {
        let webView = try await makeWebView(markdown: "make bold")

        let selected = try await evaluateBool("window.simplelimeTest.selectText('p', 5, 9);", in: webView)
        XCTAssertTrue(selected)

        try await evaluate("window.simplelimeCommand('bold');", in: webView)
        try await waitForEditorFrame()

        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        XCTAssertEqual(markdown, "make **bold**")
    }

    func testInlineFormattingCommandsRenderAndRoundTrip() async throws {
        let expectations: [(command: String, source: String, start: Int, end: Int, htmlNeedle: String, markdown: String)] = [
            ("strikethrough", "old word", 0, 3, "<del>old</del>", "~~old~~ word"),
            ("highlight", "new word", 0, 3, "<mark>new</mark>", "==new== word"),
            ("subscript", "H2O", 1, 2, "<sub>2</sub>", "H~2~O"),
            ("superscript", "x2", 1, 2, "<sup>2</sup>", "x^2^")
        ]

        for expectation in expectations {
            let webView = try await makeWebView(markdown: expectation.source)
            let selected = try await evaluateBool(
                "window.simplelimeTest.selectText('p', \(expectation.start), \(expectation.end));",
                in: webView
            )
            XCTAssertTrue(selected, expectation.command)

            try await evaluate("window.simplelimeCommand('\(expectation.command)');", in: webView)
            try await waitForEditorFrame()

            let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
            let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

            XCTAssertTrue(html.contains(expectation.htmlNeedle), "\(expectation.command): \(html)")
            XCTAssertEqual(markdown, expectation.markdown, expectation.command)
        }
    }

    func testInsertStructureCommandsRenderAndRoundTrip() async throws {
        let expectations: [(command: String, htmlNeedle: String, markdownNeedle: String)] = [
            ("link", "href=\"https://example.com\"", "[link](https://example.com)"),
            ("image", "data-md-block=\"image\"", "![image](image.png)"),
            ("table", "data-md-block=\"table\"", "| Column 1 | Column 2 |"),
            ("mathBlock", "data-md-block=\"math\"", "$$\nx = y\n$$"),
            ("mermaidDiagram", "data-md-block=\"diagram\"", "```mermaid\ngraph TD\n  A-->B\n```")
        ]

        for expectation in expectations {
            let webView = try await makeWebView()
            try await evaluate("window.simplelimeTest.setSelectionTextOffset(0);", in: webView)
            try await evaluate("window.simplelimeCommand('\(expectation.command)');", in: webView)
            try await waitForAutoNormalization()

            let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
            let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

            XCTAssertTrue(html.contains(expectation.htmlNeedle), "\(expectation.command): \(html)")
            XCTAssertTrue(markdown.contains(expectation.markdownNeedle), "\(expectation.command): \(markdown)")
        }
    }

    func testBlockSourceEditorUpdatesMermaidAndMathBlocks() async throws {
        let webView = try await makeWebView(
            markdown:
            """
            ```mermaid
            graph TD
              A-->B
            ```

            $$
            a^2 + b^2 = c^2
            $$
            """
        )

        let openedDiagram = try await evaluateBool(
            "window.simplelimeTest.enterBlockSourceEdit('figure[data-md-block=\"diagram\"]');",
            in: webView
        )
        XCTAssertTrue(openedDiagram)
        let diagramSource = try await evaluateString("window.simplelimeTest.activeBlockSourceValue();", in: webView)
        XCTAssertTrue(diagramSource.contains("graph TD"), diagramSource)

        let nextDiagram = Self.javaScriptLiteral(
            """
            sequenceDiagram
              User->>Editor: Type markdown
              Editor-->>User: Stable visual output
            """
        )
        try await evaluate("window.simplelimeTest.setActiveBlockSourceValue(\(nextDiagram));", in: webView)
        let committedDiagram = try await evaluateBool("window.simplelimeTest.commitActiveBlockSourceEdit();", in: webView)
        XCTAssertTrue(committedDiagram)

        let openedMath = try await evaluateBool(
            "window.simplelimeTest.enterBlockSourceEdit('figure[data-md-block=\"math\"]');",
            in: webView
        )
        XCTAssertTrue(openedMath)
        try await evaluate(#"window.simplelimeTest.setActiveBlockSourceValue("\\frac{x_1}{y^2} = 1");"#, in: webView)
        let committedMath = try await evaluateBool("window.simplelimeTest.commitActiveBlockSourceEdit();", in: webView)
        XCTAssertTrue(committedMath)
        try await waitForAutoNormalization()

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(markdown.contains("```mermaid\nsequenceDiagram"), markdown)
        XCTAssertTrue(markdown.contains("\\frac{x_1}{y^2} = 1"), markdown)
        XCTAssertTrue(html.contains("data-md-block=\"diagram\""), html)
        XCTAssertTrue(html.contains("data-md-block=\"math\""), html)
    }

    func testBlockSourceEditorKeepsTextareaEditableAndEscapeCancels() async throws {
        let webView = try await makeWebView(
            markdown:
            """
            ```mermaid
            graph TD
              A-->B
            ```
            """
        )

        let openedDiagram = try await evaluateBool(
            "window.simplelimeTest.enterBlockSourceEdit('figure[data-md-block=\"diagram\"]');",
            in: webView
        )
        XCTAssertTrue(openedDiagram)

        let textareaEditable = try await evaluateBool(
            """
            (() => {
              const textarea = document.querySelector('.block-source-textarea');
              if (!textarea) return false;
              textarea.focus();
              textarea.setSelectionRange(0, 5);
              const key = new KeyboardEvent('keydown', { key: 'x', bubbles: true, cancelable: true });
              textarea.dispatchEvent(key);
              textarea.setRangeText('flowchart', 0, 5, 'end');
              textarea.dispatchEvent(new Event('input', { bubbles: true }));
              return document.activeElement === textarea &&
                textarea.selectionStart === 'flowchart'.length &&
                key.defaultPrevented === false &&
                textarea.value.startsWith('flowchart');
            })();
            """,
            in: webView
        )
        XCTAssertTrue(textareaEditable)

        let escapeClosedEditor = try await evaluateBool(
            """
            (() => {
              const textarea = document.querySelector('.block-source-textarea');
              if (!textarea) return false;
              const event = new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true });
              textarea.dispatchEvent(event);
              return event.defaultPrevented && !document.querySelector('.block-source-editor');
            })();
            """,
            in: webView
        )
        XCTAssertTrue(escapeClosedEditor)
    }

    func testBlockSourceEditorUpdatesHTMLMediaAndImageMarkdown() async throws {
        let imageURL = try makeTemporaryPNG(named: "source-edit-image.png")
        let webView = try await makeWebView(
            markdown:
            """
            <video src="https://example.com/movie.mp4" controls></video>

            ![Before](\(imageURL.path))
            """
        )

        let openedMedia = try await evaluateBool(
            "window.simplelimeTest.enterBlockSourceEdit('figure[data-md-block=\"html-media\"]');",
            in: webView
        )
        XCTAssertTrue(openedMedia)
        try await evaluate(
            #"window.simplelimeTest.setActiveBlockSourceValue('<iframe src="https://example.com/embed" title="Demo"></iframe>');"#,
            in: webView
        )
        let committedMedia = try await evaluateBool("window.simplelimeTest.commitActiveBlockSourceEdit();", in: webView)
        XCTAssertTrue(committedMedia)

        let openedImage = try await evaluateBool(
            "window.simplelimeTest.enterBlockSourceEdit('figure[data-md-block=\"image\"]');",
            in: webView
        )
        XCTAssertTrue(openedImage)
        let imageMarkdown = Self.javaScriptLiteral("![After](\(imageURL.path))")
        try await evaluate(
            "window.simplelimeTest.setActiveBlockSourceValue(\(imageMarkdown));",
            in: webView
        )
        let committedImage = try await evaluateBool("window.simplelimeTest.commitActiveBlockSourceEdit();", in: webView)
        XCTAssertTrue(committedImage)
        try await waitForImagesToLoad(in: webView)

        let html = try await evaluateString("window.simplelimeTest.editorHTML();", in: webView)
        let markdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(html.contains("<iframe"), html)
        XCTAssertTrue(markdown.contains(#"<iframe src="https://example.com/embed" title="Demo"></iframe>"#), markdown)
        XCTAssertTrue(markdown.contains("![After](\(imageURL.path))"), markdown)
    }

    func testAtomicBoundariesDoNotRoundTripAndArrowKeysCrossRenderedBlocks() async throws {
        let markdown =
            """
            Before

            ```mermaid
            graph TD
              A-->B
            ```

            After
            """
        let webView = try await makeWebView(markdown: markdown)

        let boundaryCount = try await evaluateInt("window.simplelimeTest.atomicBoundaryCount();", in: webView)
        let savedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)
        XCTAssertGreaterThanOrEqual(boundaryCount, 2)
        XCTAssertFalse(savedMarkdown.contains("\u{200B}"), savedMarkdown)
        XCTAssertTrue(savedMarkdown.contains("```mermaid"), savedMarkdown)

        let selectedBeforeParagraphEnd = try await evaluateBool("window.simplelimeTest.selectText('#editor p:first-of-type', 6, 6);", in: webView)
        XCTAssertTrue(selectedBeforeParagraphEnd)
        let arrowDownFromParagraphHandled = try await evaluateBool("window.simplelimeTest.dispatchKey('ArrowDown');", in: webView)
        XCTAssertTrue(arrowDownFromParagraphHandled)
        let caretAfterFromParagraph = try await evaluateBool(
            """
            (() => {
              const selection = window.getSelection();
              const figure = document.querySelector('figure[data-md-block="diagram"]');
              if (!selection || !selection.rangeCount || !figure) return false;
              const selectionRange = selection.getRangeAt(0);
              const figureRange = document.createRange();
              figureRange.selectNode(figure);
              return selectionRange.compareBoundaryPoints(Range.START_TO_END, figureRange) >= 0;
            })();
            """,
            in: webView
        )
        XCTAssertTrue(caretAfterFromParagraph)

        let selectedAfterParagraphStart = try await evaluateBool("window.simplelimeTest.selectText('#editor p:last-of-type', 0, 0);", in: webView)
        XCTAssertTrue(selectedAfterParagraphStart)
        let arrowUpFromParagraphHandled = try await evaluateBool("window.simplelimeTest.dispatchKey('ArrowUp');", in: webView)
        XCTAssertTrue(arrowUpFromParagraphHandled)
        let caretBeforeFromParagraph = try await evaluateBool(
            """
            (() => {
              const selection = window.getSelection();
              const figure = document.querySelector('figure[data-md-block="diagram"]');
              if (!selection || !selection.rangeCount || !figure) return false;
              const selectionRange = selection.getRangeAt(0);
              const figureRange = document.createRange();
              figureRange.selectNode(figure);
              return selectionRange.compareBoundaryPoints(Range.START_TO_START, figureRange) <= 0;
            })();
            """,
            in: webView
        )
        XCTAssertTrue(caretBeforeFromParagraph)

        let placedBefore = try await evaluateBool("window.simplelimeTest.setCaretBeforeBlock('figure[data-md-block=\"diagram\"]');", in: webView)
        let arrowRightHandled = try await evaluateBool("window.simplelimeTest.dispatchKey('ArrowRight');", in: webView)
        XCTAssertTrue(placedBefore)
        XCTAssertTrue(arrowRightHandled)
        let caretAfterDiagram = try await evaluateBool(
            """
            (() => {
              const selection = window.getSelection();
              const figure = document.querySelector('figure[data-md-block="diagram"]');
              if (!selection || !selection.rangeCount || !figure) return false;
              const selectionRange = selection.getRangeAt(0);
              const figureRange = document.createRange();
              figureRange.selectNode(figure);
              return selectionRange.compareBoundaryPoints(Range.START_TO_END, figureRange) >= 0;
            })();
            """,
            in: webView
        )
        XCTAssertTrue(caretAfterDiagram)

        let placedAfter = try await evaluateBool("window.simplelimeTest.setCaretAfterBlock('figure[data-md-block=\"diagram\"]');", in: webView)
        let arrowLeftHandled = try await evaluateBool("window.simplelimeTest.dispatchKey('ArrowLeft');", in: webView)
        XCTAssertTrue(placedAfter)
        XCTAssertTrue(arrowLeftHandled)
        let caretBeforeDiagram = try await evaluateBool(
            """
            (() => {
              const selection = window.getSelection();
              const figure = document.querySelector('figure[data-md-block="diagram"]');
              if (!selection || !selection.rangeCount || !figure) return false;
              const selectionRange = selection.getRangeAt(0);
              const figureRange = document.createRange();
              figureRange.selectNode(figure);
              return selectionRange.compareBoundaryPoints(Range.START_TO_START, figureRange) <= 0;
            })();
            """,
            in: webView
        )
        XCTAssertTrue(caretBeforeDiagram)
    }

    func testArrowUpEscapesParagraphAfterHorizontalRule() async throws {
        let markdown =
            """
            ## Rules And References

            ---

            Reference definitions should be preserved and usable by WYSIWYG paragraphs.
            """
        let webView = try await makeWebView(markdown: markdown)

        let selectedParagraphStart = try await evaluateBool("window.simplelimeTest.selectText('#editor p', 0, 0);", in: webView)
        XCTAssertTrue(selectedParagraphStart)

        let arrowUpHandled = try await evaluateBool("window.simplelimeTest.dispatchKey('ArrowUp');", in: webView)
        XCTAssertTrue(arrowUpHandled)

        let caretEscapedAboveRule = try await evaluateBool(
            """
            (() => {
              const selection = window.getSelection();
              const rule = document.querySelector('hr');
              if (!selection || !selection.rangeCount || !rule) return false;
              const selectionRange = selection.getRangeAt(0);
              const ruleRange = document.createRange();
              ruleRange.selectNode(rule);
              return selectionRange.compareBoundaryPoints(Range.START_TO_START, ruleRange) <= 0;
            })();
            """,
            in: webView
        )
        let savedMarkdown = try await evaluateString("window.simplelimeTest.currentMarkdown();", in: webView)

        XCTAssertTrue(caretEscapedAboveRule)
        XCTAssertEqual(savedMarkdown, markdown)
    }

    func testCommandSlashShortcutIsHandledInWysiwygAndBlockSourceEditor() async throws {
        let webView = try await makeWebView(
            markdown:
            """
            ```mermaid
            graph TD
              A-->B
            ```
            """
        )

        let handledFromEditor = try await evaluateBool(
            "window.simplelimeTest.dispatchKey('/', { metaKey: true });",
            in: webView
        )
        XCTAssertTrue(handledFromEditor)

        let openedDiagram = try await evaluateBool(
            "window.simplelimeTest.enterBlockSourceEdit('figure[data-md-block=\"diagram\"]');",
            in: webView
        )
        XCTAssertTrue(openedDiagram)

        let handledFromSourceEditor = try await evaluateBool(
            """
            (() => {
              const textarea = document.querySelector('.block-source-textarea');
              const event = new KeyboardEvent('keydown', {
                key: '/',
                code: 'Slash',
                bubbles: true,
                cancelable: true,
                metaKey: true
              });
              textarea.dispatchEvent(event);
              return event.defaultPrevented;
            })();
            """,
            in: webView
        )
        XCTAssertTrue(handledFromSourceEditor)
    }

    private func makeWebView(
        markdown: String = "",
        typewriterModeEnabled: Bool = false,
        baseURL: URL = URL(fileURLWithPath: "/", isDirectory: true),
        comments: [DocumentComment] = [],
        activeCommentID: UUID? = nil,
        collaborators: [RemoteCollaborator] = []
    ) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: LocalImageSchemeHandler.scheme)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter

        let html = MarkdownWYSIWYGEditorView.html(
            markdown: markdown,
            fontSize: 14,
            typewriterModeEnabled: typewriterModeEnabled,
            baseURL: baseURL,
            comments: comments,
            activeCommentID: activeCommentID,
            collaborators: collaborators
        )
        try await waiter.load(html: html, baseURL: baseURL, in: webView)
        try await waitUntilTestBridgeIsReady(in: webView)
        return webView
    }

    private func waitUntilTestBridgeIsReady(in webView: WKWebView) async throws {
        for _ in 0..<20 {
            let ready = try await evaluateBool("Boolean(window.simplelimeTest);", in: webView)
            if ready {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("WYSIWYG test bridge did not load")
    }

    private func waitForEditorFrame() async throws {
        try await Task.sleep(nanoseconds: 120_000_000)
    }

    private func waitForAutoNormalization() async throws {
        try await Task.sleep(nanoseconds: 650_000_000)
    }

    private func waitForImagesToLoad(in webView: WKWebView) async throws {
        for _ in 0..<30 {
            let loaded = try await evaluateBool(
                "Array.from(document.images).every(image => image.complete && image.naturalWidth > 0);",
                in: webView
            )
            if loaded {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let html = (try? await evaluateString("document.body.innerHTML;", in: webView)) ?? ""
        XCTFail("Images did not load: \(html)")
    }

    @discardableResult
    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func evaluateString(_ script: String, in webView: WKWebView) async throws -> String {
        let result = try await evaluate(script, in: webView)
        return result as? String ?? String(describing: result ?? "")
    }

    private func evaluateInt(_ script: String, in webView: WKWebView) async throws -> Int {
        let result = try await evaluate(script, in: webView)
        if let int = result as? Int {
            return int
        }
        if let number = result as? NSNumber {
            return number.intValue
        }
        return Int(String(describing: result ?? "")) ?? 0
    }

    private func evaluateBool(_ script: String, in webView: WKWebView) async throws -> Bool {
        let result = try await evaluate(script, in: webView)
        if let bool = result as? Bool {
            return bool
        }
        if let number = result as? NSNumber {
            return number.boolValue
        }
        return false
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTemporaryPNG(named name: String, directoryURL: URL? = nil) throws -> URL {
        let directoryURL = try directoryURL ?? makeTemporaryDirectory()
        let url = directoryURL.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try pngData.write(to: url)
        return url
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func javaScriptLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return "\"\""
        }

        return String(encoded.dropFirst().dropLast())
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(html: String, baseURL: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
