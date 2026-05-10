import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreDocumentCatalogTests: XCTestCase {
    func testJumpToLineUpdatesSelectionForMiniMapNavigation() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "notes.md"
        buffer.text = "one\ntwo\nthree"
        buffer.language = .markdown

        let store = EditorStore(
            initialBuffers: [buffer],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.jumpToLine(3)

        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [TextRange(location: 8, length: 0)])
    }

    func testOpenFolderBuildsDocumentCatalogAndSkipsIgnoredDirectories() async throws {
        let rootURL = try makeTemporaryDirectory()
        try write("root", to: rootURL.appendingPathComponent("README.md"))
        try write("plain", to: rootURL.appendingPathComponent("notes.txt"))
        try write("binary", to: rootURL.appendingPathComponent("image.png"))

        let docsURL = rootURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        try write("# Nested", to: docsURL.appendingPathComponent("nested.md"))

        let ignoredURL = rootURL.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: ignoredURL, withIntermediateDirectories: true)
        try write("ignored", to: ignoredURL.appendingPathComponent("ignored.md"))

        let store = EditorStore(
            initialBuffers: [EditorBuffer.scratch(index: 1)],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.openFolder(at: rootURL)
        try await waitForCatalog(in: store)

        let flattened = flatten(store.documentCatalogNodes)
        XCTAssertTrue(flattened.contains(standardPath(rootURL.appendingPathComponent("README.md"))), flattened.description)
        XCTAssertTrue(flattened.contains(standardPath(rootURL.appendingPathComponent("notes.txt"))), flattened.description)
        XCTAssertTrue(flattened.contains(standardPath(docsURL.appendingPathComponent("nested.md"))), flattened.description)
        XCTAssertFalse(flattened.contains(standardPath(rootURL.appendingPathComponent("image.png"))), flattened.description)
        XCTAssertFalse(flattened.contains(standardPath(ignoredURL.appendingPathComponent("ignored.md"))), flattened.description)
        XCTAssertEqual(store.documentCatalogRootPath, rootURL.path)
        XCTAssertTrue(store.isDocumentCatalogVisible)
    }

    func testOpenFilesTreatsDirectoryURLsAsDocumentCatalogRoots() async throws {
        let rootURL = try makeTemporaryDirectory()
        let targetURL = rootURL.appendingPathComponent("markdown-visual-fixture.md")
        try write("# Fixture", to: targetURL)

        let store = EditorStore(
            initialBuffers: [EditorBuffer.scratch(index: 1)],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.openFiles(at: [rootURL])
        try await waitForCatalog(in: store)

        XCTAssertEqual(store.documentCatalogRootPath, rootURL.path)
        XCTAssertTrue(store.isDocumentCatalogVisible)
        XCTAssertTrue(flatten(store.documentCatalogNodes).contains(standardPath(targetURL)))
        XCTAssertNil(store.buffers.first { $0.filePath == rootURL.path })
    }

    func testDocumentCatalogFileMatchesUseFuzzyPathSearch() async throws {
        let rootURL = try makeTemporaryDirectory()
        try write("root", to: rootURL.appendingPathComponent("README.md"))

        let docsURL = rootURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        let targetURL = docsURL.appendingPathComponent("markdown-visual-fixture.md")
        try write("# Fixture", to: targetURL)
        try write("other", to: docsURL.appendingPathComponent("release-notes.txt"))

        let store = EditorStore(
            initialBuffers: [EditorBuffer.scratch(index: 1)],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.openFolder(at: rootURL)
        try await waitForCatalog(in: store)

        let matches = store.documentCatalogFileMatches(for: "mvf")

        XCTAssertEqual(matches.first?.url.standardizedFileURL, targetURL.standardizedFileURL)
        XCTAssertEqual(matches.first?.displayPath, "docs/markdown-visual-fixture.md")

        let substringMatches = store.documentCatalogFileMatches(for: "fixture")
        XCTAssertEqual(substringMatches.first?.url.standardizedFileURL, targetURL.standardizedFileURL)
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

    private func flatten(_ nodes: [DocumentCatalogNode]) -> Set<String> {
        var paths = Set<String>()

        func visit(_ node: DocumentCatalogNode) {
            paths.insert(standardPath(node.url))
            node.children.forEach(visit)
        }

        nodes.forEach(visit)
        return paths
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-catalog-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func standardPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path.hasPrefix("/private/var/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}
