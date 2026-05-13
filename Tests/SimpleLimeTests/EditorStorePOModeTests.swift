import XCTest
@testable import SimpleLime

@MainActor
final class EditorStorePOModeTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-po-mode-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testGeneratePOModeBriefCreatesMarkdownScratchFromOpenedFolder() throws {
        let specURL = temporaryDirectory.appendingPathComponent("feature.md")
        try """
        # Feature

        - [ ] Define acceptance criteria
        TBD: success metric
        """.write(to: specURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.documentCatalogRootPath = temporaryDirectory.path
        store.documentCatalogNodes = [
            DocumentCatalogNode(url: specURL, isDirectory: false)
        ]

        store.generatePOModeBriefForDocumentCatalog()

        XCTAssertEqual(store.selectedBuffer?.title, "PO Mode: \(temporaryDirectory.lastPathComponent)")
        XCTAssertEqual(store.selectedBuffer?.language, .markdown)
        XCTAssertEqual(store.selectedBuffer?.kind, .scratch)
        XCTAssertEqual(store.selectedBuffer?.isDirty, true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("## Mind Map") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("Define acceptance criteria") == true)
        XCTAssertTrue(store.selectedBuffer?.text.contains("TBD: success metric") == true)
    }

    func testGeneratePOModeBriefReportsMissingFolder() {
        let store = makeStore()
        store.closeFolder()

        store.generatePOModeBriefForDocumentCatalog()

        XCTAssertEqual(store.lastError, "Open a documents folder before generating PO mode analysis.")
    }

    func testRefreshPOModeAnalysisShowsInteractivePanel() throws {
        let specURL = temporaryDirectory.appendingPathComponent("feature.md")
        try """
        # Feature

        - [ ] Define acceptance criteria
        TBD: success metric
        """.write(to: specURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.documentCatalogRootPath = temporaryDirectory.path
        store.documentCatalogNodes = [
            DocumentCatalogNode(url: specURL, isDirectory: false)
        ]
        store.showTasksPanel()

        let report = store.refreshPOModeAnalysisForDocumentCatalog()

        XCTAssertEqual(report?.rootName, temporaryDirectory.lastPathComponent)
        XCTAssertEqual(store.poModeReport?.taskCount, 1)
        XCTAssertEqual(store.poModeReport?.gapCount, 1)
        XCTAssertTrue(store.isPOModePanelVisible)
        XCTAssertFalse(store.isTasksPanelVisible)
    }

    func testOpenPOModeReferenceJumpsToExistingFileLine() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("feature.md")
        let buffer = EditorBuffer(
            id: UUID(),
            title: fileURL.lastPathComponent,
            kind: .file,
            filePath: fileURL.path,
            text: "one\ntwo\nthree",
            language: .markdown,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            isDirty: false,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil
        )
        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
        let reference = DocumentFolderAnalysis.LineReference(
            title: "Three",
            relativePath: "feature.md",
            url: fileURL,
            lineNumber: 3,
            excerpt: "three"
        )

        store.openPOModeReference(reference)

        XCTAssertEqual(store.selectedBufferID, buffer.id)
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [TextRange(location: 8, length: 0)])
    }

    func testRunPOModeAIInterpretationSendsReportContextAndStoresResult() async throws {
        let specURL = temporaryDirectory.appendingPathComponent("feature.md")
        try """
        # Checkout

        - [ ] Define payment retry behavior
        Open question: who owns refund notifications?
        """.write(to: specURL, atomically: true, encoding: .utf8)

        let client = POModeFakeHTTPAICompleting(
            response: """
            ## Product Reading
            Checkout needs clearer recovery ownership.

            ## Gaps
            Refund notifications owner is undecided.
            """
        )
        let store = try makeStore(client: client)
        store.documentCatalogRootPath = temporaryDirectory.path
        store.documentCatalogNodes = [
            DocumentCatalogNode(url: specURL, isDirectory: false)
        ]
        _ = store.refreshPOModeAnalysisForDocumentCatalog(showPanel: false)

        store.runPOModeAIInterpretationForDocumentCatalog()
        await waitForPOAIInterpretation(in: store)

        XCTAssertEqual(store.poModeAIInterpretationStatus, "AI interpretation ready.")
        XCTAssertEqual(store.poModeAIInterpretation?.contains("Checkout needs clearer recovery ownership."), true)
        XCTAssertTrue(store.isPOModePanelVisible)
        XCTAssertEqual(client.receivedSystemPrompt?.contains("product owner reviewing a folder"), true)
        XCTAssertEqual(client.receivedPrompt?.contains("Interpret this SimpleLime PO mode report."), true)
        XCTAssertEqual(client.receivedPrompt?.contains("Define payment retry behavior"), true)
        XCTAssertEqual(client.receivedPrompt?.contains("Open question: who owns refund notifications?"), true)
    }

    func testRefreshPOModeAnalysisClearsStaleAIInterpretation() async throws {
        let specURL = temporaryDirectory.appendingPathComponent("feature.md")
        try """
        # Checkout

        - [ ] Define payment retry behavior
        """.write(to: specURL, atomically: true, encoding: .utf8)

        let client = POModeFakeHTTPAICompleting(response: "AI read")
        let store = try makeStore(client: client)
        store.documentCatalogRootPath = temporaryDirectory.path
        store.documentCatalogNodes = [
            DocumentCatalogNode(url: specURL, isDirectory: false)
        ]
        _ = store.refreshPOModeAnalysisForDocumentCatalog(showPanel: false)
        store.runPOModeAIInterpretationForDocumentCatalog()
        await waitForPOAIInterpretation(in: store)
        XCTAssertEqual(store.poModeAIInterpretation, "AI read")

        _ = store.refreshPOModeAnalysisForDocumentCatalog(showPanel: false)

        XCTAssertNil(store.poModeAIInterpretation)
        XCTAssertNil(store.poModeAIInterpretationStatus)
        XCTAssertFalse(store.isPOModeAIInterpretationRunning)
    }

    func testAddPOModeGapsAsWorkspaceTasksFromAnalysis() throws {
        let specURL = temporaryDirectory.appendingPathComponent("feature.md")
        try """
        # Feature

        TBD: success metric
        Open question: who owns retry copy?
        """.write(to: specURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.documentCatalogRootPath = temporaryDirectory.path
        store.documentCatalogNodes = [
            DocumentCatalogNode(url: specURL, isDirectory: false)
        ]

        let addedCount = store.addPOModeGapsAsTasks()

        XCTAssertEqual(addedCount, 2)
        XCTAssertEqual(store.manualTasks.count, 2)
        XCTAssertTrue(store.manualTasks.allSatisfy { $0.scope == .workspace && $0.status == .todo })
        XCTAssertTrue(store.manualTasks.contains { $0.title == "Resolve gap: TBD: success metric (feature.md:3)" })
        XCTAssertTrue(store.manualTasks.contains { $0.title == "Resolve gap: Open question: who owns retry copy? (feature.md:4)" })
        XCTAssertEqual(store.networkShare.statusMessage, "Added 2 PO gap tasks.")
    }

    func testAddPOModeGapsAsTasksSkipsAlreadyCreatedGapTasks() throws {
        let specURL = temporaryDirectory.appendingPathComponent("feature.md")
        try """
        # Feature

        GAP: pricing rules are not documented
        """.write(to: specURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.documentCatalogRootPath = temporaryDirectory.path
        store.documentCatalogNodes = [
            DocumentCatalogNode(url: specURL, isDirectory: false)
        ]

        XCTAssertEqual(store.addPOModeGapsAsTasks(), 1)
        XCTAssertEqual(store.addPOModeGapsAsTasks(), 0)
        XCTAssertEqual(store.manualTasks.count, 1)
        XCTAssertEqual(store.networkShare.statusMessage, "No new PO gap tasks.")
    }

    private func makeStore() -> EditorStore {
        EditorStore(
            initialBuffers: [EditorBuffer.scratch(index: 1)],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func makeStore(client: POModeFakeHTTPAICompleting) throws -> EditorStore {
        let configuration = try HTTPAIConfiguration(baseURLString: "https://example.com/v1", model: "test-model")
        return EditorStore(
            initialBuffers: [EditorBuffer.scratch(index: 1)],
            persistence: nil,
            httpAIClientFactory: { _ in client },
            httpAIConfigurationProvider: { configuration },
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func waitForPOAIInterpretation(in store: EditorStore) async {
        for _ in 0..<200 where store.poModeAIInterpretation == nil && store.poModeAIInterpretationStatus != "PO mode AI error" {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class POModeFakeHTTPAICompleting: HTTPAICompleting, @unchecked Sendable {
    private let response: String
    private let lock = NSLock()
    private var prompt: String?
    private var systemPrompt: String?

    init(response: String) {
        self.response = response
    }

    var receivedPrompt: String? {
        lock.withLock { prompt }
    }

    var receivedSystemPrompt: String? {
        lock.withLock { systemPrompt }
    }

    func complete(messages: [HTTPAIChatMessage], systemPrompt: String) async throws -> String {
        lock.withLock {
            prompt = messages.first?.content
            self.systemPrompt = systemPrompt
        }
        return response
    }
}
