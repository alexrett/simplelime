import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreFinderTagTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-store-finder-tag-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testStoreAddsAndClearsFinderTagsForSelectedFile() throws {
        let url = temporaryDirectory.appendingPathComponent("note.md")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.filePath = url.path
        buffer.title = url.lastPathComponent

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.addFinderTagToSelectedFile("Work")

        XCTAssertEqual(store.selectedFinderTags, ["Work"])

        store.clearFinderTagsForSelectedFile()

        XCTAssertEqual(store.selectedFinderTags, [])
    }

    func testStoreReportsActionableErrorWhenTaggingScratch() {
        let store = EditorStore(
            initialBuffers: [EditorBuffer.scratch(index: 1)],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.addFinderTagToSelectedFile("Work")

        XCTAssertEqual(store.lastError, "Save this buffer to a file before adding Finder tags.")
    }

    func testLargeFilePreviewDoesNotReadFinderTagsFromStatusBar() throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        try "{}".write(to: url, atomically: true, encoding: .utf8)
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.filePath = url.path
        buffer.title = url.lastPathComponent
        buffer.isLargeFileMode = true

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        XCTAssertEqual(store.selectedFinderTags, [])
    }
}
