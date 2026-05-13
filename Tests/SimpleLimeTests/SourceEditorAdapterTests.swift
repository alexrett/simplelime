import XCTest
@testable import SimpleLime

final class SourceEditorAdapterTests: XCTestCase {
    func testNativeSTTextViewEngineDeclaresCurrentSourceEditorContract() {
        let engine = SourceEditorEngine.nativeSTTextView

        XCTAssertEqual(engine.title, "Native STTextView")
        XCTAssertFalse(engine.isPrototypeReplacement)
        XCTAssertTrue(engine.supports(.textEditing))
        XCTAssertTrue(engine.supports(.multipleSelections))
        XCTAssertTrue(engine.supports(.columnSelection))
        XCTAssertTrue(engine.supports(.selectionReporting))
        XCTAssertTrue(engine.supports(.commandRouting))
        XCTAssertTrue(engine.supports(.visibleRangeReporting))
        XCTAssertTrue(engine.supports(.syntaxHighlighting))
        XCTAssertTrue(engine.supports(.structuredFolding))
        XCTAssertTrue(engine.supports(.comments))
        XCTAssertTrue(engine.supports(.collaborationSelections))
        XCTAssertTrue(engine.supports(.findReplaceBridge))
        XCTAssertTrue(engine.supports(.minimapSource))
        XCTAssertTrue(engine.supports(.macrosTemplates))
        XCTAssertTrue(engine.supports(.formattingCommands))
        XCTAssertTrue(engine.supports(.largeFileSearchJump))
        XCTAssertTrue(engine.supports(.readOnlyTemporaryMode))
        XCTAssertTrue(engine.supports(.diagnostics))
        XCTAssertTrue(engine.supports(.largeFileChunkEditing))
        XCTAssertFalse(engine.supports(.largeFileFullEditing))
        XCTAssertEqual(SourceEditorFeature.largeFileFullEditing.title, "Large-file full editing")
    }

    func testCodeMirrorPrototypeDeclaresLimitedReplacementContract() {
        let engine = SourceEditorEngine.codeMirrorWebViewPrototype

        XCTAssertEqual(engine.title, "CodeMirror 6 WebView Prototype")
        XCTAssertTrue(engine.isPrototypeReplacement)
        XCTAssertTrue(engine.supports(.textEditing))
        XCTAssertTrue(engine.supports(.multipleSelections))
        XCTAssertTrue(engine.supports(.selectionReporting))
        XCTAssertTrue(engine.supports(.commandRouting))
        XCTAssertTrue(engine.supports(.visibleRangeReporting))
        XCTAssertTrue(engine.supports(.syntaxHighlighting))
        XCTAssertTrue(engine.supports(.comments))
        XCTAssertTrue(engine.supports(.collaborationSelections))
        XCTAssertTrue(engine.supports(.findReplaceBridge))
        XCTAssertTrue(engine.supports(.formattingCommands))
        XCTAssertTrue(engine.supports(.readOnlyTemporaryMode))
        XCTAssertTrue(engine.supports(.diagnostics))
        XCTAssertFalse(engine.supports(.structuredFolding))
        XCTAssertFalse(engine.supports(.macrosTemplates))
        XCTAssertFalse(engine.supports(.largeFileFullEditing))
    }

    func testSourceEditorWebSelectionPreservesMultipleSelectionsWithinTextBounds() {
        let selections = SourceEditorWebSelection.normalizedRanges(
            [
                TextRange(location: 2, length: 4),
                TextRange(location: 10, length: 20),
                TextRange(location: 40, length: 0)
            ],
            textLength: 18
        )

        XCTAssertEqual(
            selections,
            [
                TextRange(location: 2, length: 4),
                TextRange(location: 10, length: 8),
                TextRange(location: 18, length: 0)
            ]
        )
        XCTAssertEqual(
            SourceEditorWebSelection.normalizedRanges([], textLength: 12),
            [.zero]
        )
    }

    func testSourceEditorConfigurationCapturesRenderPathAndReadOnlyState() {
        let configuration = SourceEditorConfiguration(
            language: .json,
            fontSize: 15,
            wrapsLines: true,
            columnGuide: 88,
            syntaxHighlightingEnabled: false,
            isEditable: false,
            focusModeEnabled: true,
            typewriterModeEnabled: false
        )

        XCTAssertEqual(configuration.engine, .nativeSTTextView)
        XCTAssertEqual(configuration.renderPath, "Native STTextView source editor")
        XCTAssertTrue(configuration.isReadOnly)
        XCTAssertEqual(configuration.language, .json)
        XCTAssertEqual(configuration.fontSize, 15)
        XCTAssertTrue(configuration.wrapsLines)
        XCTAssertEqual(configuration.columnGuide, 88)
        XCTAssertFalse(configuration.syntaxHighlightingEnabled)
        XCTAssertTrue(configuration.focusModeEnabled)
        XCTAssertFalse(configuration.typewriterModeEnabled)
    }

    func testSourceEditorConfigurationCanSelectPrototypeEngine() {
        let configuration = SourceEditorConfiguration(
            engine: .codeMirrorWebViewPrototype,
            language: .javascript,
            fontSize: 14,
            wrapsLines: false,
            columnGuide: 100,
            syntaxHighlightingEnabled: true,
            isEditable: true,
            focusModeEnabled: false,
            typewriterModeEnabled: false
        )

        XCTAssertEqual(configuration.engine, .codeMirrorWebViewPrototype)
        XCTAssertEqual(configuration.renderPath, "CodeMirror 6 WebView Prototype source editor")
        XCTAssertFalse(configuration.isReadOnly)
    }

    func testCodeMirrorHostSelectionBridgeScrollsHostDrivenSelectionIntoView() {
        let html = CodeMirrorSourceEditorView.htmlForTesting

        XCTAssertTrue(html.contains("selectionSignature(hostState)"), html)
        XCTAssertTrue(html.contains("scrollPrimarySelectionIntoView"), html)
        XCTAssertTrue(html.contains("EditorView.scrollIntoView"), html)
        XCTAssertTrue(html.contains("scrollTextareaSelectionIntoView"), html)
    }

    func testCodeMirrorColumnGuideRendersThroughWebViewAndTextareaFallback() {
        let html = CodeMirrorSourceEditorView.htmlForTesting

        XCTAssertTrue(html.contains("columnGuideExtension(hostState)"), html)
        XCTAssertTrue(html.contains(".cm-content::before"), html)
        XCTAssertTrue(html.contains("applyTextareaColumnGuide"), html)
        XCTAssertTrue(html.contains("sl-has-column-guide"), html)
    }

    func testCodeMirrorModeFlagsReachWebViewAndTextareaFallback() {
        let html = CodeMirrorSourceEditorView.htmlForTesting

        XCTAssertTrue(html.contains("focusModeEnabled"), html)
        XCTAssertTrue(html.contains("typewriterModeEnabled"), html)
        XCTAssertTrue(html.contains("focusModeExtension(hostState)"), html)
        XCTAssertTrue(html.contains("typewriterModeExtension(hostState)"), html)
        XCTAssertTrue(html.contains("sl-focus-dimmed"), html)
        XCTAssertTrue(html.contains("applyTextareaEditorModes"), html)
        XCTAssertTrue(html.contains("sl-typewriter-mode"), html)
        XCTAssertTrue(html.contains("sl-focus-mode"), html)
    }

    func testCodeMirrorFoldedRangesRenderReadOnlyDisplayWithoutClaimingFullFoldingSupport() {
        let html = CodeMirrorSourceEditorView.htmlForTesting

        XCTAssertTrue(html.contains("foldedRanges"), html)
        XCTAssertTrue(html.contains("FoldedBlockWidget"), html)
        XCTAssertTrue(html.contains("foldedRangeExtension(hostState, doc)"), html)
        XCTAssertTrue(html.contains("Decoration.replace"), html)
        XCTAssertTrue(html.contains("foldedTextForTextarea"), html)
        XCTAssertTrue(html.contains("hostStateIsEditable"), html)
        XCTAssertTrue(html.contains("sl-folded-block"), html)
        XCTAssertFalse(SourceEditorEngine.codeMirrorWebViewPrototype.supports(.structuredFolding))
    }

    func testCodeMirrorSelectionCommandsAndReadOnlyGuardAreRoutedDirectly() {
        let html = CodeMirrorSourceEditorView.htmlForTesting

        XCTAssertTrue(html.contains("function expandSelectionToLine(view)"), html)
        XCTAssertTrue(html.contains("function splitSelectionIntoLines(view)"), html)
        XCTAssertTrue(html.contains("function moveSelectedLines(view, direction)"), html)
        XCTAssertTrue(html.contains("function toggleLineComments(view)"), html)
        XCTAssertTrue(html.contains("function lineCommentPrefixForLanguage(language)"), html)
        XCTAssertTrue(html.contains("const canMutate = hostStateIsEditable(currentState);"), html)
        XCTAssertTrue(html.contains("if (command === \"expandSelectionToLine\") return expandSelectionToLine(editorView);"), html)
        XCTAssertTrue(html.contains("if (command === \"splitSelectionIntoLines\") return splitSelectionIntoLines(editorView);"), html)
        XCTAssertTrue(html.contains("if (!canMutate) return false;"), html)
        XCTAssertTrue(html.contains("if (command === \"toggleComment\") return toggleLineComments(editorView);"), html)
        XCTAssertTrue(html.contains("if (command === \"moveLineUp\") return moveSelectedLines(editorView, -1);"), html)
        XCTAssertTrue(html.contains("if (command === \"moveLineDown\") return moveSelectedLines(editorView, 1);"), html)
    }

    func testSourceEditorDecorationsKeepCommentsAndCollaboratorsTogether() {
        let commentID = UUID()
        let collaborator = RemoteCollaborator(
            deviceID: "mac-1",
            name: "Mac",
            selectionRanges: [TextRange(location: 2, length: 3)],
            colorIndex: 1,
            lastSeenAt: Date(timeIntervalSince1970: 10)
        )
        let comment = DocumentComment(
            id: commentID,
            documentKey: "doc",
            range: TextRange(location: 1, length: 4),
            quote: "text"
        )

        let decorations = SourceEditorDecorations(
            comments: [comment],
            activeCommentID: commentID,
            collaborators: [collaborator]
        )

        XCTAssertEqual(decorations.comments, [comment])
        XCTAssertEqual(decorations.activeCommentID, commentID)
        XCTAssertEqual(decorations.collaborators, [collaborator])
    }

    func testSourceEditorDecorationsProduceWebDecorationPayload() {
        let activeCommentID = UUID()
        let resolvedComment = DocumentComment(
            documentKey: "doc",
            range: TextRange(location: 0, length: 4),
            quote: "gone",
            resolvedAt: Date(timeIntervalSince1970: 1)
        )
        let activeComment = DocumentComment(
            id: activeCommentID,
            documentKey: "doc",
            range: TextRange(location: 6, length: 7),
            quote: "comment"
        )
        let collaborator = RemoteCollaborator(
            deviceID: "peer",
            name: "Peer",
            selectionRanges: [
                TextRange(location: 15, length: 5),
                TextRange(location: 40, length: 0)
            ],
            colorIndex: 2,
            lastSeenAt: Date(timeIntervalSince1970: 1)
        )
        let decorations = SourceEditorDecorations(
            comments: [resolvedComment, activeComment],
            activeCommentID: activeCommentID,
            collaborators: [collaborator]
        )

        let webDecorations = decorations.webDecorations(textLength: 32)

        XCTAssertEqual(webDecorations.map(\.kind), [
            .activeComment,
            .collaboratorSelection,
            .collaboratorCaret
        ])
        XCTAssertEqual(webDecorations[0].range, TextRange(location: 6, length: 7))
        XCTAssertEqual(webDecorations[1].range, TextRange(location: 15, length: 5))
        XCTAssertEqual(webDecorations[1].label, "Peer")
        XCTAssertTrue((webDecorations[1].color ?? "").hasPrefix("rgb("))
        XCTAssertEqual(webDecorations[2].range, TextRange(location: 32, length: 0))
    }

    func testAcceptanceGateFailsUnsafeLargeNormalBufferAndRequiresLiveLatencyGate() {
        let checks = SourceEditorAcceptanceGate.evaluate(
            SourceEditorAcceptanceGateContext(
                language: .json,
                isLargeFileMode: false,
                fileSizeBytes: 1_000_000,
                loadedByteCount: 1_000_000,
                lineCount: 25_000,
                wouldUseLargeFileMode: true,
                isMiniMapVisible: true,
                canSaveLargeFileChunkBack: false,
                hasLargeFileSourcePath: true
            )
        )

        XCTAssertEqual(checks.first { $0.title == "Open large files without UI blocking" }?.status, .fail)
        XCTAssertEqual(checks.first { $0.title == "Clear large-file policy" }?.status, .fail)
        XCTAssertEqual(checks.first { $0.title == "Typing latency under 32 ms p95" }?.status, .manual)
        XCTAssertEqual(checks.first { $0.title == "Full-file virtual editing" }?.status, .fail)
    }

    func testAcceptanceGateDocumentsLargeVirtualPreviewLimitations() {
        let checks = SourceEditorAcceptanceGate.evaluate(
            SourceEditorAcceptanceGateContext(
                language: .json,
                isLargeFileMode: true,
                fileSizeBytes: 1_000_000,
                loadedByteCount: 16_384,
                lineCount: 400,
                wouldUseLargeFileMode: true,
                isMiniMapVisible: false,
                canSaveLargeFileChunkBack: true,
                hasLargeFileSourcePath: true
            )
        )

        XCTAssertEqual(checks.first { $0.title == "Open large files without UI blocking" }?.status, .pass)
        XCTAssertEqual(checks.first { $0.title == "Whole-file navigation" }?.status, .pass)
        XCTAssertEqual(checks.first { $0.title == "Feature contract preservation" }?.status, .warning)
        XCTAssertEqual(checks.first { $0.title == "Full-file virtual editing" }?.status, .fail)
        XCTAssertTrue(
            checks
                .first { $0.title == "Clear large-file policy" }?
                .evidence
                .contains("save-back metadata is present") ?? false
        )
    }
}
