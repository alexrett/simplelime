import XCTest
@testable import SimpleLime

private typealias SLTextRange = SimpleLime.TextRange

@MainActor
final class EditorStoreTextTransformTests: XCTestCase {
    func testInlineTransformsApplyToSelectedTextOnly() {
        XCTAssertEqual(
            transformedText("Keep Mixed", selection: SLTextRange(location: 5, length: 5), using: .uppercase),
            "Keep MIXED"
        )
        XCTAssertEqual(
            transformedText("Keep MIXED", selection: SLTextRange(location: 5, length: 5), using: .lowercase),
            "Keep mixed"
        )
        XCTAssertEqual(
            transformedText("Keep mixed words", selection: SLTextRange(location: 5, length: 11), using: .titlecase),
            "Keep Mixed Words"
        )
        XCTAssertEqual(
            transformedText("Keep AbC", selection: SLTextRange(location: 5, length: 3), using: .swapCase),
            "Keep aBc"
        )
        XCTAssertEqual(
            transformedText("Keep abc", selection: SLTextRange(location: 5, length: 3), using: .reverseSelection),
            "Keep cba"
        )
    }

    func testLineTransformsUseSelectedLinesAndPreserveTrailingNewline() {
        let store = makeStore(
            text: "outside\nbeta\nalpha\nbeta\noutside\n",
            selection: SLTextRange(location: 8, length: 16)
        )

        store.performTextTransform(.sortLines)

        XCTAssertEqual(store.selectedBuffer?.text, "outside\nalpha\nbeta\nbeta\noutside\n")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [SLTextRange(location: 8, length: 16)])

        store.performTextTransform(.uniqueLines)

        XCTAssertEqual(store.selectedBuffer?.text, "outside\nalpha\nbeta\noutside\n")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [SLTextRange(location: 8, length: 11)])
    }

    func testTrimJoinAndDuplicateLineFallbacks() {
        XCTAssertEqual(
            transformedText("one  \ntwo\t\n", using: .trimTrailingWhitespace),
            "one\ntwo\n"
        )
        XCTAssertEqual(
            transformedText(" one \n two\n\n three ", using: .joinLines),
            "one two three"
        )

        let store = makeStore(text: "one\ntwo\nthree", selection: SLTextRange(location: 5, length: 0))
        store.performTextTransform(.duplicateLine)

        XCTAssertEqual(store.selectedBuffer?.text, "one\ntwo\ntwo\nthree")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [SLTextRange(location: 8, length: 4)])
    }

    func testJSONFormatAndMinifyFallbacks() {
        let formatted = transformedText("{\"one\":1,\"two\":[true]}", using: .formatJSON)
        XCTAssertTrue(formatted.contains("\"one\" : 1"), formatted)
        XCTAssertTrue(formatted.contains("\"two\" : ["), formatted)
        XCTAssertTrue(formatted.hasSuffix("\n"))

        XCTAssertEqual(
            transformedText("{\n  \"one\" : 1,\n  \"two\" : [\n    true\n  ]\n}\n", using: .minifyJSON),
            "{\"one\":1,\"two\":[true]}"
        )
    }

    func testInvalidJSONTransformLeavesTextUntouchedAndReportsError() {
        let store = makeStore(text: "{invalid", selection: nil)

        store.performTextTransform(.formatJSON)

        XCTAssertEqual(store.selectedBuffer?.text, "{invalid")
        XCTAssertEqual(store.lastError?.hasPrefix("Could not format JSON:"), true)
    }

    func testMarkdownTableTransformFormatsSelectedTable() {
        let store = makeStore(
            text: "intro\n|a|bb|\n|---|---:|\n|x|12|\noutro",
            selection: SLTextRange(location: 6, length: 25)
        )

        store.performTextTransform(.formatMarkdownTables)

        XCTAssertEqual(
            store.selectedBuffer?.text,
            "intro\n| a   |  bb |\n| --- | --: |\n| x   |  12 |\noutro"
        )
    }

    private func transformedText(_ text: String, selection: SLTextRange? = nil, using transform: TextTransform) -> String {
        let store = makeStore(text: text, selection: selection)
        store.performTextTransform(transform)
        return store.selectedBuffer?.text ?? ""
    }

    private func makeStore(text: String, selection: SLTextRange? = nil) -> EditorStore {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = text
        buffer.selectionRanges = [selection ?? .zero]

        return EditorStore(
            initialBuffers: [buffer],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }
}
