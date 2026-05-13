import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreFoldingTests: XCTestCase {
    func testToggleFoldAtSelectionAddsAndRemovesNearestFoldableRange() {
        let buffer = makeBuffer(
            text: """
            # A
            intro
            ## B
            body
            """,
            language: .markdown,
            selectionLine: "body"
        )
        let store = makeStore(buffer: buffer)

        store.toggleStructuredFoldAtSelection()

        XCTAssertEqual(
            store.foldedRanges(for: store.selectedBuffer!),
            [StructuredFoldRange(startLine: 3, endLine: 4, title: "B")]
        )
        XCTAssertFalse(store.isWysiwygModeEnabled)
        XCTAssertFalse(store.isPreviewVisible)

        store.toggleStructuredFoldAtSelection()

        XCTAssertTrue(store.foldedRanges(for: store.selectedBuffer!).isEmpty)
    }

    func testUnfoldAllClearsSelectedBufferFolds() {
        let buffer = makeBuffer(
            text: """
            {
              "items": [
                1
              ]
            }
            """,
            language: .json,
            selectionLine: "\"items\""
        )
        let store = makeStore(buffer: buffer)

        store.toggleStructuredFoldAtSelection()
        XCTAssertFalse(store.foldedRanges(for: store.selectedBuffer!).isEmpty)

        store.unfoldAllStructuredBlocks()

        XCTAssertTrue(store.foldedRanges(for: store.selectedBuffer!).isEmpty)
    }

    func testEditingTextClearsExistingFolds() {
        let buffer = makeBuffer(
            text: """
            root:
              child: value
            next: value
            """,
            language: .yaml,
            selectionLine: "child"
        )
        let store = makeStore(buffer: buffer)

        store.toggleStructuredFoldAtSelection()
        XCTAssertFalse(store.foldedRanges(for: store.selectedBuffer!).isEmpty)

        store.updateSelectedText("root:\n  child: changed\n")

        XCTAssertTrue(store.foldedRanges(for: store.selectedBuffer!).isEmpty)
    }

    func testGutterDisplayLineMappingTogglesVisibleSourceBlockAfterFold() {
        let buffer = makeBuffer(
            text: """
            # A
            intro
            # B
            body
            # C
            tail
            """,
            language: .markdown,
            selectionLine: "# A"
        )
        let store = makeStore(buffer: buffer)

        store.toggleStructuredFoldAtSelection()
        let firstFold = StructuredFoldRange(startLine: 1, endLine: 2, title: "A")
        XCTAssertEqual(store.foldedRanges(for: store.selectedBuffer!), [firstFold])

        let displayLineForSecondHeading = StructuredTextFolder.displayLineNumber(
            forSourceLine: 3,
            foldedRanges: [firstFold]
        )
        let sourceLineFromGutter = StructuredTextFolder.sourceLineNumber(
            forDisplayLine: displayLineForSecondHeading,
            foldedRanges: [firstFold]
        )
        store.toggleStructuredFold(containingLine: sourceLineFromGutter, in: store.selectedBuffer!.id)

        XCTAssertEqual(
            store.foldedRanges(for: store.selectedBuffer!),
            [
                firstFold,
                StructuredFoldRange(startLine: 3, endLine: 4, title: "B")
            ]
        )
    }

    private func makeStore(buffer: EditorBuffer) -> EditorStore {
        EditorStore(
            initialBuffers: [buffer],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func makeBuffer(text: String, language: EditorLanguage, selectionLine: String) -> EditorBuffer {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = text
        buffer.language = language
        let location = (text as NSString).range(of: selectionLine).location
        buffer.selectionRanges = [TextRange(location: location == NSNotFound ? 0 : location, length: 0)]
        return buffer
    }
}
