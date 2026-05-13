import AppKit
import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreDrawingTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-drawing-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testNewDrawingBoardCreatesWhiteboardScratch() {
        let store = makeStore()

        store.newDrawingBoard()

        XCTAssertEqual(store.selectedBuffer?.title, "Drawing Board 1")
        XCTAssertEqual(store.selectedBuffer?.language, .drawing)
        XCTAssertEqual(store.selectedBuffer?.kind, .scratch)
        XCTAssertEqual(store.selectedBuffer?.text, "")
        XCTAssertEqual(store.selectedBuffer?.isDirty, false)
    }

    func testDrawingBoardPersistsStrokeTextThroughNormalUpdate() {
        let store = makeStore()
        store.newDrawingBoard()
        let bufferID = try! XCTUnwrap(store.selectedBufferID)
        let stroke = WhiteboardStroke(
            ink: .green,
            lineWidth: 6,
            points: [
                WhiteboardPoint(x: 0.25, y: 0.25),
                WhiteboardPoint(x: 0.75, y: 0.75)
            ]
        )
        let text = WhiteboardDocument.empty.appending(stroke).encodedText()

        store.updateText(text, in: bufferID)

        XCTAssertEqual(WhiteboardDocument.decode(from: store.selectedBuffer?.text ?? "").strokes.count, 1)
        XCTAssertEqual(store.selectedBuffer?.isDirty, true)
    }

    func testDrawingBoardSavesAndReopensAsSLDraw() async throws {
        let store = makeStore()
        store.newDrawingBoard()
        let stroke = WhiteboardStroke(
            ink: .purple,
            lineWidth: 3,
            points: [
                WhiteboardPoint(x: 0.1, y: 0.1),
                WhiteboardPoint(x: 0.9, y: 0.9)
            ]
        )
        let text = WhiteboardDocument.empty.appending(stroke).encodedText()
        store.updateSelectedText(text)

        let rawURL = temporaryDirectory.appendingPathComponent("sketch")
        store.saveSelected(to: rawURL, as: .drawing)

        let drawingURL = temporaryDirectory.appendingPathComponent("sketch.sldraw")
        XCTAssertEqual(try String(contentsOf: drawingURL, encoding: .utf8), text)
        XCTAssertEqual(store.selectedBuffer?.language, .drawing)

        let reopenedStore = makeStore()
        reopenedStore.openFile(at: drawingURL)
        let reopened = try await waitForLoadedSelectedBuffer(in: reopenedStore, filePath: drawingURL.path)

        XCTAssertEqual(reopened.language, .drawing)
        XCTAssertEqual(WhiteboardDocument.decode(from: reopened.text).strokes.count, 1)
    }

    func testDrawingBoardCanCreateMarkdownWidgetScratch() {
        let store = makeStore()
        store.newDrawingBoard()
        let board = WhiteboardDocument.empty
            .appending(.sticky(rect: WhiteboardRect(x: 0.1, y: 0.1, width: 0.2, height: 0.14), text: "Widget"))
        store.updateSelectedText(board.encodedText())

        store.insertDrawingWidgetIntoMarkdown()

        XCTAssertEqual(store.selectedBuffer?.language, .markdown)
        XCTAssertTrue(store.selectedBuffer?.text.contains("```sldraw") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("Widget") == true)
    }

    func testDrawingBoardCanCopyPNGToPasteboard() throws {
        let store = makeStore()
        store.newDrawingBoard()
        let board = WhiteboardDocument.empty
            .appending(.sticky(rect: WhiteboardRect(x: 0.1, y: 0.1, width: 0.2, height: 0.14), text: "Copy"))
        store.updateSelectedText(board.encodedText())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("simplelime-drawing-store-copy-\(UUID().uuidString)"))

        store.copySelectedDrawingAsPNG(to: pasteboard)

        let data = try XCTUnwrap(pasteboard.data(forType: .png))
        XCTAssertTrue(data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
        XCTAssertEqual(store.networkShare.statusMessage, "Copied Drawing Board 1 as PNG.")
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
        for _ in 0..<200 {
            if let buffer = store.selectedBuffer,
               buffer.filePath == filePath,
               !buffer.text.isEmpty {
                return buffer
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for drawing file to load")
        return try XCTUnwrap(store.selectedBuffer)
    }
}
