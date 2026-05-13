import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreSaveAsTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-save-as-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testSuggestedSaveFileNameUsesExistingTabTitleAndSelectedType() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "Product Notes.md"
        buffer.text = "# Ignored Heading"
        buffer.language = .markdown

        XCTAssertEqual(EditorStore.suggestedSaveFileName(for: buffer, fileType: .json), "Product Notes.json")
    }

    func testSuggestedSaveFileNameFallsBackToDocumentHeadingForDefaultScratchTitle() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "# Quarterly Plan / Draft\nBody"
        buffer.language = .markdown

        XCTAssertEqual(EditorStore.suggestedSaveFileName(for: buffer, fileType: .markdown), "Quarterly Plan Draft.md")
    }

    func testSaveSelectedWithFileTypeAppliesExtensionAndLanguage() throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "# Draft"
        buffer.language = .plain
        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        let rawURL = temporaryDirectory.appendingPathComponent("draft")
        store.saveSelected(to: rawURL, as: .markdown)

        let markdownURL = temporaryDirectory.appendingPathComponent("draft.md")
        XCTAssertEqual(try String(contentsOf: markdownURL, encoding: .utf8), "# Draft")
        XCTAssertEqual(store.selectedBuffer?.filePath, markdownURL.path)
        XCTAssertEqual(store.selectedBuffer?.language, .markdown)
        XCTAssertEqual(store.selectedBuffer?.isDirty, false)
    }

    func testChangingFileNameExtensionKeepsBaseNameSanitized() {
        XCTAssertEqual(EditorStore.fileName("Draft: One/Two.txt", changingExtensionTo: "md"), "Draft One Two.md")
    }

    func testAISuggestedSaveFileNameIsSanitizedAndRetyped() {
        let response = """
        {"fileName":"Roadmap: Q2/Launch Notes.txt"}
        """

        XCTAssertEqual(
            EditorStore.suggestedSaveFileNameFromAIResponse(response, fileType: .markdown),
            "Roadmap Q2 Launch Notes.md"
        )
    }

    func testAISuggestedSaveFileNameAcceptsPlainTextResponse() {
        XCTAssertEqual(
            EditorStore.suggestedSaveFileNameFromAIResponse("\"Weekly Decisions\"", fileType: .plain),
            "Weekly Decisions.txt"
        )
    }
}
