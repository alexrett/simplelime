import XCTest
@testable import SimpleLime

private typealias SLTextRange = SimpleLime.TextRange

@MainActor
final class EditorStoreDiffTests: XCTestCase {
    func testCompareSelectedBufferWithPreviousTabCreatesDiffScratchBuffer() {
        var old = EditorBuffer.scratch(index: 1)
        old.title = "old.txt"
        old.text = "alpha\nbeta\n"
        old.language = .plain

        var new = EditorBuffer.scratch(index: 2)
        new.title = "new.txt"
        new.text = "alpha\nbravo\n"
        new.language = .plain
        new.selectionRanges = [SLTextRange(location: 0, length: 0)]

        let store = EditorStore(
            initialBuffers: [old, new],
            selectedID: new.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.compareSelectedBufferWithPreviousTab()

        XCTAssertEqual(store.buffers.count, 3)
        XCTAssertEqual(store.selectedBuffer?.title, "Diff: old.txt vs new.txt")
        XCTAssertEqual(store.selectedBuffer?.kind, .scratch)
        XCTAssertEqual(store.selectedBuffer?.language, .plain)
        XCTAssertTrue(store.selectedBuffer?.text.contains("-beta") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("+bravo") == true)
    }

    func testCompareSelectedFirstTabReportsActionableError() {
        let buffer = EditorBuffer.scratch(index: 1)
        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.compareSelectedBufferWithPreviousTab()

        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.lastError, "Select a tab after the file you want to compare against.")
    }

    func testCompareSelectedBufferWithChosenFileCreatesDiffScratchBuffer() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let otherURL = temporaryDirectory.appendingPathComponent("other.txt")
        try "alpha\nbravo\n".write(to: otherURL, atomically: true, encoding: .utf8)

        var current = EditorBuffer.scratch(index: 1)
        current.title = "current.txt"
        current.text = "alpha\nbeta\n"
        current.language = .plain

        let store = EditorStore(
            initialBuffers: [current],
            selectedID: current.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.compareSelectedBuffer(withFileAt: otherURL)

        XCTAssertEqual(store.buffers.count, 2)
        XCTAssertEqual(store.selectedBuffer?.title, "Diff: current.txt vs other.txt")
        XCTAssertEqual(store.selectedBuffer?.kind, .scratch)
        XCTAssertTrue(store.selectedBuffer?.text.contains("--- current.txt") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("+++ other.txt") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("-beta") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("+bravo") == true)
    }

    func testCompareSelectedLargePreviewWithoutSourceReportsActionableError() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let otherURL = temporaryDirectory.appendingPathComponent("other.txt")
        try "other\n".write(to: otherURL, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "large.json"
        buffer.text = "{}"
        buffer.language = .json
        buffer.isLargeFileMode = true
        buffer.savePolicy = .readOnly

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.compareSelectedBuffer(withFileAt: otherURL)

        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.lastError, "Large-file previews without a source file path cannot be diffed.")
    }

    func testCompareSelectedLargeFilePreviewUsesSourceFileForBoundedDiff() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let currentURL = temporaryDirectory.appendingPathComponent("current.json")
        let otherURL = temporaryDirectory.appendingPathComponent("other.json")
        try (String(repeating: #"{"same":true}"# + "\n", count: 2_200) + #"{"current":true}"# + "\n")
            .write(to: currentURL, atomically: true, encoding: .utf8)
        try (String(repeating: #"{"same":true}"# + "\n", count: 2_200) + #"{"other":true}"# + "\n")
            .write(to: otherURL, atomically: true, encoding: .utf8)

        var current = EditorBuffer.scratch(index: 1)
        current.title = "current.json"
        current.kind = .file
        current.filePath = currentURL.path
        current.text = "[SimpleLime large-file preview: chunk only]"
        current.language = .json
        current.isLargeFileMode = true
        current.savePolicy = .readOnly

        let store = EditorStore(
            initialBuffers: [current],
            selectedID: current.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.compareSelectedBuffer(withFileAt: otherURL)

        XCTAssertEqual(store.buffers.count, 2)
        XCTAssertEqual(store.selectedBuffer?.title, "Diff: current.json vs other.json")
        XCTAssertTrue(store.selectedBuffer?.text.contains("Diff preview limited to 1 MB and 2,000 lines per side.") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("current.json showing") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("other.json showing") == true)
        XCTAssertFalse(store.selectedBuffer?.text.contains("chunk only") == true)
        XCTAssertNil(store.lastError)
    }

    func testCompareLargeFilePreviewTabsUsesSourceFilesInsteadOfVisibleChunks() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let oldURL = temporaryDirectory.appendingPathComponent("old.json")
        let newURL = temporaryDirectory.appendingPathComponent("new.json")
        try "alpha\nold source\n".write(to: oldURL, atomically: true, encoding: .utf8)
        try "alpha\nnew source\n".write(to: newURL, atomically: true, encoding: .utf8)

        var old = EditorBuffer.scratch(index: 1)
        old.title = "old.json"
        old.kind = .file
        old.filePath = oldURL.path
        old.text = "old chunk only\n"
        old.language = .json
        old.isLargeFileMode = true
        old.savePolicy = .readOnly

        var new = EditorBuffer.scratch(index: 2)
        new.title = "new.json"
        new.kind = .file
        new.filePath = newURL.path
        new.text = "new chunk only\n"
        new.language = .json
        new.isLargeFileMode = true
        new.savePolicy = .readOnly

        let store = EditorStore(
            initialBuffers: [old, new],
            selectedID: new.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.compareSelectedBufferWithPreviousTab()

        XCTAssertEqual(store.buffers.count, 3)
        XCTAssertEqual(store.selectedBuffer?.title, "Diff: old.json vs new.json")
        XCTAssertTrue(store.selectedBuffer?.text.contains("-old source") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("+new source") == true)
        XCTAssertFalse(store.selectedBuffer?.text.contains("chunk only") == true)
        XCTAssertNil(store.lastError)
    }

    func testCompareWithOversizedFileCreatesBoundedPreviewDiff() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let otherURL = temporaryDirectory.appendingPathComponent("other.txt")
        let largeText = String(repeating: "line\n", count: 2_000) + "tail change\n"
        try largeText.write(to: otherURL, atomically: true, encoding: .utf8)

        var current = EditorBuffer.scratch(index: 1)
        current.title = "current.txt"
        current.text = "small\n"

        let store = EditorStore(
            initialBuffers: [current],
            selectedID: current.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.compareSelectedBuffer(withFileAt: otherURL)

        XCTAssertEqual(store.buffers.count, 2)
        XCTAssertEqual(store.selectedBuffer?.title, "Diff: current.txt vs other.txt")
        XCTAssertTrue(store.selectedBuffer?.text.contains("Diff preview limited to 1 MB and 2,000 lines per side.") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("other.txt showing") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("+line") == true)
        XCTAssertNil(store.lastError)
    }

    func testCompareOversizedPreviousTabCreatesBoundedPreviewDiff() {
        var old = EditorBuffer.scratch(index: 1)
        old.title = "old.txt"
        old.text = String(repeating: "same\n", count: 2_000) + "old tail\n"

        var new = EditorBuffer.scratch(index: 2)
        new.title = "new.txt"
        new.text = String(repeating: "same\n", count: 2_000) + "new tail\n"

        let store = EditorStore(
            initialBuffers: [old, new],
            selectedID: new.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.compareSelectedBufferWithPreviousTab()

        XCTAssertEqual(store.buffers.count, 3)
        XCTAssertEqual(store.selectedBuffer?.title, "Diff: old.txt vs new.txt")
        XCTAssertTrue(store.selectedBuffer?.text.contains("Diff preview limited to 1 MB and 2,000 lines per side.") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("No differences in the rendered preview.") == true)
        XCTAssertNil(store.lastError)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-diff-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
