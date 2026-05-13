import XCTest
@testable import SimpleLime

private typealias SLTextRange = SimpleLime.TextRange

@MainActor
final class EditorStorePanelLayoutTests: XCTestCase {
    func testRightSidebarPanelsAreMutuallyExclusive() throws {
        let store = makeStore()

        store.showCommentsPanel()
        XCTAssertEqual(activeRightPanelCount(in: store), 1)
        XCTAssertTrue(store.isCommentsPanelVisible)

        store.showStatsPanel()
        XCTAssertEqual(activeRightPanelCount(in: store), 1)
        XCTAssertTrue(store.isStatsPanelVisible)
        XCTAssertFalse(store.isCommentsPanelVisible)

        store.showMacrosPanel()
        XCTAssertEqual(activeRightPanelCount(in: store), 1)
        XCTAssertTrue(store.isMacrosPanelVisible)
        XCTAssertFalse(store.isStatsPanelVisible)

        store.showCompanionPanel()
        XCTAssertEqual(activeRightPanelCount(in: store), 1)
        XCTAssertTrue(store.isCompanionPanelVisible)
        XCTAssertFalse(store.isMacrosPanelVisible)

        store.toggleMacrosPanel()
        XCTAssertEqual(activeRightPanelCount(in: store), 1)
        XCTAssertTrue(store.isMacrosPanelVisible)
        XCTAssertFalse(store.isCompanionPanelVisible)

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-panel-layout-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let specURL = temporaryDirectory.appendingPathComponent("feature.md")
        try "# Feature\n".write(to: specURL, atomically: true, encoding: .utf8)
        store.documentCatalogRootPath = temporaryDirectory.path
        store.documentCatalogNodes = [
            DocumentCatalogNode(url: specURL, isDirectory: false)
        ]
        store.refreshPOModeAnalysisForDocumentCatalog()
        XCTAssertEqual(activeRightPanelCount(in: store), 1)
        XCTAssertTrue(store.isPOModePanelVisible)
        XCTAssertFalse(store.isMacrosPanelVisible)

        store.toggleMacrosPanel()
        XCTAssertEqual(activeRightPanelCount(in: store), 1)
        XCTAssertTrue(store.isMacrosPanelVisible)
        XCTAssertFalse(store.isPOModePanelVisible)

        store.toggleScribePanel()
        XCTAssertEqual(activeRightPanelCount(in: store), 1)
        XCTAssertTrue(store.isScribePanelVisible)
        XCTAssertFalse(store.isMacrosPanelVisible)

        store.toggleMacrosPanel()
        XCTAssertEqual(activeRightPanelCount(in: store), 1)
        XCTAssertTrue(store.isMacrosPanelVisible)
        XCTAssertFalse(store.isScribePanelVisible)

        store.toggleMacrosPanel()
        XCTAssertEqual(activeRightPanelCount(in: store), 0)
    }

    func testAddingCommentSwitchesRightSidebarToComments() {
        let store = makeStore(text: "hello", selection: SLTextRange(location: 0, length: 5))
        store.showTasksPanel()

        _ = store.addCommentToSelection(body: "Check")

        XCTAssertTrue(store.isCommentsPanelVisible)
        XCTAssertFalse(store.isTasksPanelVisible)
        XCTAssertEqual(activeRightPanelCount(in: store), 1)
    }

    func testLeftSidebarDocumentCatalogAndOutlineAreMutuallyExclusive() {
        let store = makeStore()
        store.isDocumentCatalogVisible = false
        store.isOutlineVisible = false

        store.toggleDocumentCatalog()
        XCTAssertTrue(store.isDocumentCatalogVisible)
        XCTAssertFalse(store.isOutlineVisible)

        store.toggleMarkdownOutline()
        XCTAssertTrue(store.isOutlineVisible)
        XCTAssertFalse(store.isDocumentCatalogVisible)

        store.toggleDocumentCatalog()
        XCTAssertTrue(store.isDocumentCatalogVisible)
        XCTAssertFalse(store.isOutlineVisible)
    }

    private func makeStore(text: String = "", selection: SLTextRange = .zero) -> EditorStore {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = text
        buffer.selectionRanges = [selection]
        return EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func activeRightPanelCount(in store: EditorStore) -> Int {
        [
            store.isAIPanelVisible,
            store.isNetworkPanelVisible,
            store.isCommentsPanelVisible,
            store.isCompanionPanelVisible,
            store.isTasksPanelVisible,
            store.isPOModePanelVisible,
            store.isScribePanelVisible,
            store.isStatsPanelVisible,
            store.isMacrosPanelVisible
        ].filter { $0 }.count
    }
}
