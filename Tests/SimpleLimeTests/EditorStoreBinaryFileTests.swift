import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreBinaryFileTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-binary-open-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testOpenImageCreatesReadOnlyPreviewBufferWithoutTextDecode() throws {
        let url = temporaryDirectory.appendingPathComponent("shot.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        let store = makeStore()

        store.openFile(at: url)

        XCTAssertEqual(store.selectedBuffer?.filePath, url.path)
        XCTAssertEqual(store.selectedBuffer?.language, .image)
        XCTAssertEqual(store.selectedBuffer?.savePolicy, .readOnly)
        XCTAssertEqual(store.selectedBuffer?.text, "")
        XCTAssertEqual(store.selectedBuffer?.isDirty, false)
        XCTAssertNil(store.lastError)
    }

    func testOpenPDFCreatesReadOnlyPreviewBufferWithoutTextDecode() throws {
        let url = temporaryDirectory.appendingPathComponent("brief.pdf")
        try Data("%PDF-1.7\n".utf8).write(to: url)
        let store = makeStore()

        store.openFile(at: url)

        XCTAssertEqual(store.selectedBuffer?.filePath, url.path)
        XCTAssertEqual(store.selectedBuffer?.language, .pdf)
        XCTAssertEqual(store.selectedBuffer?.savePolicy, .readOnly)
        XCTAssertEqual(store.selectedBuffer?.text, "")
        XCTAssertEqual(store.selectedBuffer?.isDirty, false)
        XCTAssertNil(store.lastError)
    }

    func testOpenUnknownBinaryCreatesReadOnlyHexPreviewBufferWithoutTextDecode() throws {
        let url = temporaryDirectory.appendingPathComponent("payload.dat")
        try Data([0x00, 0xFF, 0x01, 0x41]).write(to: url)
        let store = makeStore()

        store.openFile(at: url)

        XCTAssertEqual(store.selectedBuffer?.filePath, url.path)
        XCTAssertEqual(store.selectedBuffer?.language, .hex)
        XCTAssertEqual(store.selectedBuffer?.savePolicy, .readOnly)
        XCTAssertEqual(store.selectedBuffer?.text, "")
        XCTAssertEqual(store.selectedBuffer?.isDirty, false)
        XCTAssertNil(store.lastError)
    }

    func testOpenTextReadableUnknownFileStillOpensAsEditablePlainText() async throws {
        let url = temporaryDirectory.appendingPathComponent("payload.dat")
        try Data("plain text stays editable\n".utf8).write(to: url)
        let store = makeStore()

        store.openFile(at: url)
        let buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        XCTAssertEqual(buffer.language, .plain)
        XCTAssertEqual(buffer.savePolicy, .normal)
        XCTAssertEqual(buffer.text, "plain text stays editable\n")
        XCTAssertEqual(buffer.isDirty, false)
        XCTAssertNil(store.lastError)
    }

    private func makeStore() -> EditorStore {
        EditorStore(
            initialBuffers: [EditorBuffer.scratch(index: 1)],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func waitForLoadedSelectedBuffer(in store: EditorStore, filePath: String) async throws -> EditorBuffer {
        for _ in 0..<100 {
            if let buffer = store.selectedBuffer,
               buffer.filePath == filePath,
               buffer.text == "plain text stays editable\n" {
                return buffer
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for text file to load")
        throw CancellationError()
    }
}
