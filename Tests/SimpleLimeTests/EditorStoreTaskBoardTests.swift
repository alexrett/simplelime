import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreTaskBoardTests: XCTestCase {
    func testManualTasksCanMoveAcrossColumns() {
        let store = makeStore(text: "")

        store.addManualTask(title: "Follow up")
        guard let task = store.manualTasks.first else {
            return XCTFail("Expected a manual task")
        }

        store.updateManualTask(task.id, status: .done)

        XCTAssertEqual(store.manualTasks.first?.status, .done)
        XCTAssertEqual(store.taskCards(for: .done), [.manual(store.manualTasks[0])])
    }

    func testGlobalAndWorkspaceManualTasksPersistSeparatelyAndShareBoard() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let workspacePersistence = TaskBoardPersistence(boardURL: rootURL.appendingPathComponent("tasks.json"))
        let globalPersistence = TaskBoardPersistence(boardURL: rootURL.appendingPathComponent("global-tasks.json"))
        let store = makeStore(
            text: "",
            taskPersistence: workspacePersistence,
            globalTaskPersistence: globalPersistence
        )

        store.addManualTask(title: "Workspace task")
        store.addManualTask(title: "Global task", scope: .global)

        XCTAssertEqual(store.manualTasks.map(\.title), ["Workspace task"])
        XCTAssertEqual(store.globalManualTasks.map(\.title), ["Global task"])
        XCTAssertEqual(store.taskCards(for: .todo).map(\.title), ["Global task", "Workspace task"])

        let globalTask = try XCTUnwrap(store.globalManualTasks.first)
        store.updateManualTask(globalTask.id, status: .done)

        XCTAssertEqual(store.globalManualTasks.first?.status, .done)
        XCTAssertEqual(globalPersistence.load().map(\.status), [.done])
        XCTAssertEqual(workspacePersistence.load().map(\.status), [.todo])
    }

    func testDetectedMarkdownTasksAppearOnBoardAndCanBeUpdated() {
        let store = makeStore(
            text:
            """
            # Tasks
            - [ ] Draft
            - [x] Done
            """
        )

        let todoCards = store.taskCards(for: .todo)
        guard case .detected(let task) = todoCards.first else {
            return XCTFail("Expected a detected task")
        }

        store.updateDetectedTask(task, status: .done)

        XCTAssertTrue(store.selectedBuffer?.text.contains("- [x] Draft") == true)
        XCTAssertEqual(store.taskCards(for: .done).count, 2)
    }

    func testNaturalTasksAppearOnBoardAndConvertToChecklistWhenUpdated() {
        let store = makeStore(text: "// TODO: Handle terminal resize\nlet x = 1", language: .swift)

        let todoCards = store.taskCards(for: .todo)
        guard case .detected(let task) = todoCards.first else {
            return XCTFail("Expected a natural detected task")
        }

        XCTAssertEqual(task.title, "Handle terminal resize")
        XCTAssertEqual(task.updateMode, .lineToMarkdownChecklist)

        store.updateDetectedTask(task, status: .done)

        XCTAssertEqual(store.selectedBuffer?.text, "- [x] Handle terminal resize\nlet x = 1")
    }

    func testInferredPlainLanguageTasksAppearOnBoardAndConvertToChecklistWhenUpdated() {
        let store = makeStore(text: "We need to update README before launch.\n")

        let todoCards = store.taskCards(for: .todo)
        guard case .detected(let task) = todoCards.first else {
            return XCTFail("Expected an inferred detected task")
        }

        XCTAssertEqual(task.title, "Update README before launch")
        XCTAssertEqual(task.updateMode, .lineToMarkdownChecklist)

        store.updateDetectedTask(task, status: .done)

        XCTAssertEqual(store.selectedBuffer?.text, "- [x] Update README before launch\n")
    }

    func testOpenDetectedTaskSelectsBufferAndLine() {
        var first = EditorBuffer.scratch(index: 1)
        first.title = "First"
        first.text = "- [ ] A"
        var second = EditorBuffer.scratch(index: 2)
        second.title = "Second"
        second.text = "intro\n- [ ] B"
        let store = EditorStore(
            initialBuffers: [first, second],
            selectedID: first.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        guard let task = store.detectedTasks.first(where: { $0.bufferID == second.id }) else {
            return XCTFail("Expected detected task in second buffer")
        }

        store.openDetectedTask(task)

        XCTAssertEqual(store.selectedBufferID, second.id)
        XCTAssertEqual(store.selectedBuffer?.selectionRanges.first?.location, 6)
    }

    func testDocumentCatalogMarkdownTasksAppearOnBoardAndOpenFromDisk() async throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let taskURL = rootURL.appendingPathComponent("tasks.md")
        try "# Plan\n- [ ] Catalog task\n".write(to: taskURL, atomically: true, encoding: .utf8)

        let store = makeStore(text: "")
        store.openFolder(at: rootURL)
        let task = try await waitForCatalogTask(in: store, title: "Catalog task")

        XCTAssertNil(task.bufferID)
        XCTAssertEqual(task.filePath.map { URL(fileURLWithPath: $0).lastPathComponent }, taskURL.lastPathComponent)
        XCTAssertEqual(task.sourceLabel, "tasks.md:2")
        XCTAssertTrue(store.taskCards(for: .todo).contains(.detected(task)))

        store.openDetectedTask(task)
        let opened = try await waitForLoadedSelectedBuffer(in: store, filePath: task.filePath ?? taskURL.path)

        XCTAssertEqual(opened.filePath, task.filePath)
        XCTAssertEqual(opened.selectionRanges.first?.location, 7)
    }

    func testDocumentCatalogNaturalTaskCanBeUpdatedOnDisk() async throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let taskURL = rootURL.appendingPathComponent("notes.txt")
        try "TODO: Catalog natural task\n".write(to: taskURL, atomically: true, encoding: .utf8)

        let store = makeStore(text: "")
        store.openFolder(at: rootURL)
        let task = try await waitForCatalogTask(in: store, title: "Catalog natural task")

        XCTAssertEqual(task.updateMode, .lineToMarkdownChecklist)

        store.updateDetectedTask(task, status: .inProgress)

        XCTAssertEqual(try String(contentsOf: taskURL, encoding: .utf8), "- [>] Catalog natural task\n")
        _ = try await waitForCatalogTask(in: store, title: "Catalog natural task", status: .inProgress)
    }

    func testDocumentCatalogDetectedTaskCanBeUpdatedOnDisk() async throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let taskURL = rootURL.appendingPathComponent("tasks.md")
        try "# Plan\n- [ ] Catalog task\n".write(to: taskURL, atomically: true, encoding: .utf8)

        let store = makeStore(text: "")
        store.openFolder(at: rootURL)
        let task = try await waitForCatalogTask(in: store, title: "Catalog task")

        store.updateDetectedTask(task, status: .done)

        XCTAssertTrue(try String(contentsOf: taskURL, encoding: .utf8).contains("- [x] Catalog task"))
        _ = try await waitForCatalogTask(in: store, title: "Catalog task", status: .done)
    }

    func testAITaskInferenceAddsManualTasksFromOpenBuffers() async throws {
        let client = TaskBoardFakeHTTPAICompleting(
            response: """
            {"tasks":[
              {"title":"Define checkout rollback owner","status":"todo"},
              {"title":"Pair with support on launch FAQ","status":"inProgress"},
              {"title":"Catalog task","status":"todo"}
            ]}
            """
        )
        let store = makeStore(
            text:
            """
            # Checkout launch
            The launch notes imply a rollback owner and a support FAQ, but the task list is not explicit.
            - [ ] Catalog task
            """,
            client: client
        )

        store.runAITaskInference()
        try await waitForTaskAIInference(in: store)

        XCTAssertEqual(store.taskAIInferenceStatus, "Added 2 AI tasks.")
        XCTAssertEqual(Set(store.manualTasks.map(\.title)), [
            "Define checkout rollback owner",
            "Pair with support on launch FAQ"
        ])
        XCTAssertEqual(
            store.manualTasks.first(where: { $0.title == "Pair with support on launch FAQ" })?.status,
            .inProgress
        )
        XCTAssertTrue(client.receivedSystemPrompt?.contains("extract concrete follow-up tasks") == true)
        XCTAssertTrue(client.receivedPrompt?.contains("Checkout launch") == true)
    }

    func testTaskAIAutoInferenceRunsAfterTextEditWhenEnabled() async throws {
        let client = TaskBoardFakeHTTPAICompleting(
            response: #"{"tasks":[{"title":"Define rollback owner","status":"todo"}]}"#
        )
        let store = makeStore(
            text: "",
            client: client,
            taskAIAutoInferenceEnabled: true,
            taskAIAutoInferenceDelayNanoseconds: 1_000_000
        )

        store.updateSelectedText("Before launch we need to define rollback owner.")
        try await waitForTaskAIInference(in: store)

        XCTAssertEqual(store.taskAIInferenceStatus, "Auto-added 1 AI task.")
        XCTAssertEqual(store.manualTasks.map(\.title), ["Define rollback owner"])
        XCTAssertFalse(store.isTasksPanelVisible)
        XCTAssertEqual(client.receivedPrompts.count, 1)
        XCTAssertTrue(client.receivedPrompt?.contains("define rollback owner") == true)
    }

    func testTaskAIAutoInferenceIsOptIn() async throws {
        let client = TaskBoardFakeHTTPAICompleting(
            response: #"{"tasks":[{"title":"Define rollback owner","status":"todo"}]}"#
        )
        let store = makeStore(
            text: "",
            client: client,
            taskAIAutoInferenceEnabled: false,
            taskAIAutoInferenceDelayNanoseconds: 1_000_000
        )

        store.updateSelectedText("Before launch we need to define rollback owner.")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(store.taskAIInferenceStatus)
        XCTAssertTrue(store.manualTasks.isEmpty)
        XCTAssertTrue(client.receivedPrompts.isEmpty)
    }

    func testTaskAIAutoInferenceRunsAfterOpeningTextFileWhenEnabled() async throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let notesURL = rootURL.appendingPathComponent("launch.md")
        try "Launch FAQ ownership is still unresolved before rollout.\n".write(to: notesURL, atomically: true, encoding: .utf8)
        let client = TaskBoardFakeHTTPAICompleting(
            response: #"{"tasks":[{"title":"Assign launch FAQ owner","status":"inProgress"}]}"#
        )
        let store = makeStore(
            text: "",
            client: client,
            taskAIAutoInferenceEnabled: true,
            taskAIAutoInferenceDelayNanoseconds: 1_000_000
        )

        store.openFile(at: notesURL)
        _ = try await waitForLoadedSelectedBuffer(in: store, filePath: notesURL.path)
        try await waitForTaskAIInference(in: store)

        XCTAssertEqual(store.taskAIInferenceStatus, "Auto-added 1 AI task.")
        XCTAssertEqual(store.manualTasks.first?.title, "Assign launch FAQ owner")
        XCTAssertEqual(store.manualTasks.first?.status, .inProgress)
        XCTAssertFalse(store.isTasksPanelVisible)
        XCTAssertEqual(client.receivedPrompts.count, 1)
        XCTAssertTrue(client.receivedPrompt?.contains("Launch FAQ ownership") == true)
    }

    func testAITaskInferenceParserAcceptsFencedJSONAndDeduplicates() {
        let results = AITaskInference.parse(
            """
            ```json
            {"tasks":[
              {"task":"Review privacy copy","state":"doing"},
              {"title":"Review privacy copy","status":"todo"},
              "Prepare release note"
            ]}
            ```
            """
        )

        XCTAssertEqual(results, [
            AITaskInferenceResult(title: "Review privacy copy", status: .inProgress),
            AITaskInferenceResult(title: "Prepare release note", status: .todo)
        ])
    }

    private func makeStore(
        text: String,
        language: EditorLanguage = .markdown,
        taskPersistence: TaskBoardPersistence? = nil,
        globalTaskPersistence: TaskBoardPersistence? = nil,
        client: TaskBoardFakeHTTPAICompleting? = nil,
        taskAIAutoInferenceEnabled: Bool? = nil,
        taskAIAutoInferenceDelayNanoseconds: UInt64 = 1_000_000
    ) -> EditorStore {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = text
        buffer.language = language
        let configuration = try! HTTPAIConfiguration(baseURLString: "https://example.com/v1", model: "test-model")
        return EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            taskPersistence: taskPersistence,
            globalTaskPersistence: globalTaskPersistence,
            httpAIClientFactory: { _ in
                client ?? TaskBoardFakeHTTPAICompleting(response: #"{"tasks":[]}"#)
            },
            httpAIConfigurationProvider: { configuration },
            taskAIAutoInferenceEnabled: taskAIAutoInferenceEnabled,
            taskAIAutoInferenceDelayNanoseconds: taskAIAutoInferenceDelayNanoseconds,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func makeTemporaryRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-task-board-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func waitForCatalogTask(
        in store: EditorStore,
        title: String,
        status: TaskBoardStatus? = nil
    ) async throws -> DetectedTask {
        for _ in 0..<200 {
            if let task = store.detectedTasks.first(where: { task in
                task.title == title && (status == nil || task.status == status)
            }) {
                return task
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for catalog task \(title)")
        return try XCTUnwrap(store.detectedTasks.first)
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

        XCTFail("Timed out waiting for opened file")
        return try XCTUnwrap(store.selectedBuffer)
    }

    private func waitForTaskAIInference(in store: EditorStore) async throws {
        for _ in 0..<200 {
            if !store.isTaskAIInferenceRunning,
               let status = store.taskAIInferenceStatus,
               status != "AI task inference queued..." {
                return
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for AI task inference")
    }
}

private final class TaskBoardFakeHTTPAICompleting: HTTPAICompleting, @unchecked Sendable {
    let response: String
    private(set) var receivedPrompts: [String] = []
    private(set) var receivedPrompt: String?
    private(set) var receivedSystemPrompt: String?

    init(response: String) {
        self.response = response
    }

    func complete(messages: [HTTPAIChatMessage], systemPrompt: String) async throws -> String {
        receivedPrompt = messages.last?.content
        if let receivedPrompt {
            receivedPrompts.append(receivedPrompt)
        }
        receivedSystemPrompt = systemPrompt
        return response
    }
}
