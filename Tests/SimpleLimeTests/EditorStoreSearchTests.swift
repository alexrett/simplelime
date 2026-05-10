import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreSearchTests: XCTestCase {
    func testWholeWordAndMatchCaseSelectAllMatches() {
        let store = makeStore(text: "alpha Alpha alphabet alpha")
        store.findQuery = "alpha"
        store.findWholeWord = true

        store.selectAllMatches()

        XCTAssertEqual(
            store.selectedBuffer?.selectionRanges,
            [
                TextRange(location: 0, length: 5),
                TextRange(location: 6, length: 5),
                TextRange(location: 21, length: 5)
            ]
        )
        XCTAssertEqual(store.findStatusText, "1 of 3")

        store.findMatchesCase = true
        store.selectAllMatches()

        XCTAssertEqual(
            store.selectedBuffer?.selectionRanges,
            [
                TextRange(location: 0, length: 5),
                TextRange(location: 21, length: 5)
            ]
        )
        XCTAssertEqual(store.findStatusText, "1 of 2")
    }

    func testRegexReplaceAllUsesCaptureGroupsAndMatchCase() {
        let store = makeStore(text: "item-12 item-9 ITEM-7")
        store.findUsesRegex = true
        store.findMatchesCase = true
        store.findQuery = #"(item)-(\d+)"#
        store.replaceText = #"$1[$2]"#

        store.replaceAll()

        XCTAssertEqual(store.selectedBuffer?.text, "item[12] item[9] ITEM-7")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [TextRange(location: 0, length: 8)])
    }

    func testInvalidRegexReportsStatusAndDoesNotMoveSelection() {
        let store = makeStore(text: "alpha beta")
        store.findUsesRegex = true
        store.findQuery = "("

        store.findNext()

        XCTAssertEqual(store.findValidationError, "Invalid regex")
        XCTAssertEqual(store.findStatusText, "Invalid regex")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [.zero])
    }

    func testCommandPaletteHidesFindPanelBeforeTakingInput() {
        let store = makeStore(text: "alpha beta")

        store.showFind()
        store.showCommandPalette()

        XCTAssertEqual(store.findPanelMode, .hidden)
        XCTAssertTrue(store.isCommandPaletteVisible)
    }

    func testGlobalSearchIncludesDocumentCatalogFilesAndOpensResult() async throws {
        let rootURL = try makeTemporaryDirectory()
        let docsURL = rootURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        let targetURL = docsURL.appendingPathComponent("guide.md")
        try "intro\nfolder needle\nend".write(to: targetURL, atomically: true, encoding: .utf8)

        let store = makeStore(text: "open tab")
        store.openFolder(at: rootURL)
        try await waitForCatalog(in: store)

        store.findQuery = "needle"
        let result = try XCTUnwrap(store.globalSearchResults.first)

        XCTAssertEqual(result.bufferTitle, "docs/guide.md")
        XCTAssertEqual(result.filePath.map(standardPath), standardPath(targetURL))
        XCTAssertEqual(result.lineNumber, 2)
        XCTAssertEqual(result.range, TextRange(location: 13, length: 6))

        store.selectSearchResult(result)

        XCTAssertEqual(store.selectedBuffer?.filePath.map(standardPath), standardPath(targetURL))
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [TextRange(location: 13, length: 6)])
        XCTAssertEqual(store.selectedBuffer?.text, "intro\nfolder needle\nend")
    }

    func testGlobalReplaceUpdatesOpenBuffersAndClosedCatalogFiles() async throws {
        let rootURL = try makeTemporaryDirectory()
        let openURL = rootURL.appendingPathComponent("open.md")
        let closedURL = rootURL.appendingPathComponent("closed.md")
        try "disk TODO should stay until saved".write(to: openURL, atomically: true, encoding: .utf8)
        try "closed TODO and TODO".write(to: closedURL, atomically: true, encoding: .utf8)

        let store = makeStore(
            buffers: [
                makeFileBuffer(url: openURL, text: "open TODO and TODO")
            ]
        )
        store.openFolder(at: rootURL)
        try await waitForCatalog(in: store)

        store.findQuery = "TODO"
        store.replaceText = "DONE"

        let replacementCount = store.replaceAllGlobalMatches()

        XCTAssertEqual(replacementCount, 4)
        XCTAssertEqual(store.globalReplaceStatusText, "Replaced 4 matches in 2 documents")
        XCTAssertEqual(store.selectedBuffer?.text, "open DONE and DONE")
        XCTAssertEqual(store.selectedBuffer?.isDirty, true)
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [TextRange(location: 5, length: 4)])
        XCTAssertEqual(try String(contentsOf: openURL), "disk TODO should stay until saved")
        XCTAssertEqual(try String(contentsOf: closedURL), "closed DONE and DONE")
    }

    func testGlobalReplaceUsesRegexCaptureGroupsAndWholeWord() async throws {
        let rootURL = try makeTemporaryDirectory()
        let targetURL = rootURL.appendingPathComponent("numbers.md")
        try "item-12 item-9 ITEM-7 item-88x".write(to: targetURL, atomically: true, encoding: .utf8)

        let store = makeStore(text: "scratch")
        store.openFolder(at: rootURL)
        try await waitForCatalog(in: store)

        store.findUsesRegex = true
        store.findMatchesCase = true
        store.findWholeWord = true
        store.findQuery = #"(item)-(\d+)"#
        store.replaceText = #"$1[$2]"#

        let replacementCount = store.replaceAllGlobalMatches()

        XCTAssertEqual(replacementCount, 2)
        XCTAssertEqual(try String(contentsOf: targetURL), "item[12] item[9] ITEM-7 item-88x")
    }

    private func makeStore(text: String) -> EditorStore {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = text
        buffer.language = .plain
        return makeStore(buffers: [buffer])
    }

    private func makeStore(buffers: [EditorBuffer]) -> EditorStore {
        return EditorStore(
            initialBuffers: buffers,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func makeFileBuffer(url: URL, text: String) -> EditorBuffer {
        let now = Date()
        return EditorBuffer(
            id: UUID(),
            title: url.lastPathComponent,
            kind: .file,
            filePath: url.path,
            text: text,
            language: EditorLanguage.detect(fileName: url.lastPathComponent, text: text),
            createdAt: now,
            updatedAt: now,
            isDirty: false,
            selectionRanges: [.zero]
        )
    }

    private func waitForCatalog(in store: EditorStore) async throws {
        for _ in 0..<40 {
            if !store.documentCatalogNodes.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Document catalog did not load")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-search-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func standardPath(_ url: URL) -> String {
        standardPath(url.path)
    }

    private func standardPath(_ path: String) -> String {
        if path.hasPrefix("/private/var/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}
