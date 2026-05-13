import XCTest
@testable import SimpleLime

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleLimeWorkspaceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testNamedWorkspacesKeepIndependentSessions() throws {
        let store = makeStore()
        let defaultWorkspaceID = store.activeWorkspaceID

        let defaultBufferID = try XCTUnwrap(store.activeStore?.selectedBuffer?.id)
        store.activeStore?.updateText("default note", in: defaultBufferID)

        let work = try XCTUnwrap(store.createWorkspace(named: "Work"))

        XCTAssertEqual(store.activeWorkspaceID, work.id)
        XCTAssertEqual(store.activeWorkspaceName, "Work")
        XCTAssertEqual(store.activeStore?.selectedBuffer?.text, "")

        let workBufferID = try XCTUnwrap(store.activeStore?.selectedBuffer?.id)
        store.activeStore?.updateText("work note", in: workBufferID)

        store.switchWorkspace(defaultWorkspaceID)
        XCTAssertEqual(store.activeWorkspaceName, "Default")
        XCTAssertEqual(store.activeStore?.selectedBuffer?.text, "default note")

        store.switchWorkspace(work.id)
        XCTAssertEqual(store.activeWorkspaceName, "Work")
        XCTAssertEqual(store.activeStore?.selectedBuffer?.text, "work note")
    }

    func testWorkspaceIndexRestoresSelectedWorkspace() throws {
        var store = makeStore()
        let work = try XCTUnwrap(store.createWorkspace(named: "Work"))
        let bufferID = try XCTUnwrap(store.activeStore?.selectedBuffer?.id)
        store.activeStore?.updateText("remember me", in: bufferID)
        store.persistNow()

        store = makeStore()

        XCTAssertEqual(store.activeWorkspaceID, work.id)
        XCTAssertEqual(store.activeWorkspaceName, "Work")
        XCTAssertEqual(store.activeStore?.selectedBuffer?.text, "remember me")
    }

    func testSafeModeSkipsPersistedWindowSessionAndCanOverwriteIt() throws {
        let workspacePersistence = WorkspacePersistence(rootURL: temporaryDirectory)
        let sessionPersistence = workspacePersistence.sessionPersistence(for: .default)
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "toxic restored text"
        let groupID = UUID()

        try sessionPersistence.save(
            windowGroups: [
                EditorWindowGroupState(id: groupID, selectedBufferID: buffer.id, buffers: [buffer])
            ],
            selectedGroupID: groupID
        )

        let store = WorkspaceStore(
            workspacePersistence: workspacePersistence,
            opensRestoredManualWindows: false,
            restoresPersistedSession: false,
            observesExternalOpenURLs: false,
            startsLocalAutomationBridge: false
        )

        let safeBuffer = try XCTUnwrap(store.activeStore?.selectedBuffer)
        XCTAssertNotEqual(safeBuffer.id, buffer.id)
        XCTAssertEqual(safeBuffer.kind, .scratch)
        XCTAssertEqual(safeBuffer.text, "")

        store.persistNow()

        let overwrittenSession = sessionPersistence.loadWindowSession()
        let persistedBuffer = try XCTUnwrap(overwrittenSession.groups.first?.buffers.first)
        XCTAssertEqual(persistedBuffer.id, safeBuffer.id)
        XCTAssertEqual(persistedBuffer.text, "")
        XCTAssertFalse(
            overwrittenSession.groups.flatMap(\.buffers).contains { $0.id == buffer.id },
            "Safe mode should let the fresh session replace an unusable restored session."
        )
    }

    func testSafeModeSkipsPersistedWindowSessionWhenSwitchingWorkspaces() throws {
        var store = makeStore()
        let defaultWorkspaceID = store.activeWorkspaceID
        let defaultBufferID = try XCTUnwrap(store.activeStore?.selectedBuffer?.id)
        store.activeStore?.updateText("default restored text", in: defaultBufferID)

        let work = try XCTUnwrap(store.createWorkspace(named: "Work"))
        let workBufferID = try XCTUnwrap(store.activeStore?.selectedBuffer?.id)
        store.activeStore?.updateText("work restored text", in: workBufferID)
        store.persistNow()

        store = WorkspaceStore(
            workspacePersistence: WorkspacePersistence(rootURL: temporaryDirectory),
            opensRestoredManualWindows: false,
            restoresPersistedSession: false,
            observesExternalOpenURLs: false,
            startsLocalAutomationBridge: false
        )

        XCTAssertEqual(store.activeWorkspaceID, work.id)
        XCTAssertEqual(store.activeStore?.selectedBuffer?.text, "")

        store.switchWorkspace(defaultWorkspaceID)

        XCTAssertEqual(store.activeWorkspaceID, defaultWorkspaceID)
        XCTAssertEqual(store.activeStore?.selectedBuffer?.text, "")
    }

    func testSafeModeLaunchOptionsRecognizeRecoveryFlagsOnly() {
        XCTAssertTrue(SimpleLimeLaunchOptions.shouldSkipRestoredSession(arguments: ["SimpleLime", "--safe-mode"]))
        XCTAssertTrue(SimpleLimeLaunchOptions.shouldSkipRestoredSession(arguments: ["SimpleLime", "--simplelime-safe-mode"]))
        XCTAssertFalse(SimpleLimeLaunchOptions.shouldSkipRestoredSession(arguments: ["SimpleLime"]))
        XCTAssertFalse(SimpleLimeLaunchOptions.shouldSkipRestoredSession(arguments: ["SimpleLime", "/tmp/--safe-mode.txt"]))
    }

    func testReloadAppDataRootUsesCopiedWorkspaceDataImmediately() throws {
        let localRoot = temporaryDirectory.appendingPathComponent("LocalRoot", isDirectory: true)
        let syncedRoot = temporaryDirectory.appendingPathComponent("SyncedRoot", isDirectory: true)
        var store = WorkspaceStore(
            workspacePersistence: WorkspacePersistence(rootURL: localRoot),
            opensRestoredManualWindows: false,
            observesExternalOpenURLs: false,
            startsLocalAutomationBridge: false
        )

        let work = try XCTUnwrap(store.createWorkspace(named: "Work"))
        let bufferID = try XCTUnwrap(store.activeStore?.selectedBuffer?.id)
        store.activeStore?.updateText("work note", in: bufferID)
        store.persistNow()

        try AppDataStorage.copyExistingData(from: localRoot, to: syncedRoot)
        store.reloadAppDataRoot(workspacePersistence: WorkspacePersistence(rootURL: syncedRoot))

        XCTAssertEqual(store.activeWorkspaceID, work.id)
        XCTAssertEqual(store.activeWorkspaceName, "Work")
        XCTAssertEqual(store.activeStore?.selectedBuffer?.text, "work note")

        let reloadedBufferID = try XCTUnwrap(store.activeStore?.selectedBuffer?.id)
        store.activeStore?.updateText("synced edit", in: reloadedBufferID)
        store.persistNow()

        store = WorkspaceStore(
            workspacePersistence: WorkspacePersistence(rootURL: syncedRoot),
            opensRestoredManualWindows: false,
            observesExternalOpenURLs: false,
            startsLocalAutomationBridge: false
        )

        XCTAssertEqual(store.activeWorkspaceID, work.id)
        XCTAssertEqual(store.activeStore?.selectedBuffer?.text, "synced edit")
    }

    func testExternalAppDataRootChangeReloadsCleanSession() throws {
        let workspacePersistence = WorkspacePersistence(rootURL: temporaryDirectory)
        let store = WorkspaceStore(
            workspacePersistence: workspacePersistence,
            opensRestoredManualWindows: false,
            observesExternalOpenURLs: false,
            startsLocalAutomationBridge: false,
            monitorsExternalAppDataChanges: false
        )
        let groupID = store.primaryGroupID
        var externalBuffer = EditorBuffer.scratch(index: 1)
        externalBuffer.text = "external iCloud note"
        externalBuffer.isDirty = true

        try workspacePersistence.sessionPersistence(for: .default).save(
            windowGroups: [
                EditorWindowGroupState(id: groupID, selectedBufferID: externalBuffer.id, buffers: [externalBuffer])
            ],
            selectedGroupID: groupID
        )

        XCTAssertTrue(store.reloadAppDataRootIfChanged())
        XCTAssertEqual(store.activeStore?.selectedBuffer?.id, externalBuffer.id)
        XCTAssertEqual(store.activeStore?.selectedBuffer?.text, "external iCloud note")
        XCTAssertEqual(store.appDataSyncStatus, "App data reloaded from disk after detecting external changes.")
    }

    func testExternalAppDataRootChangeIgnoresLocalTabSelectionOnlyChanges() throws {
        let workspacePersistence = WorkspacePersistence(rootURL: temporaryDirectory)
        let store = WorkspaceStore(
            workspacePersistence: workspacePersistence,
            opensRestoredManualWindows: false,
            observesExternalOpenURLs: false,
            startsLocalAutomationBridge: false,
            monitorsExternalAppDataChanges: false
        )
        let firstBufferID = try XCTUnwrap(store.activeStore?.selectedBuffer?.id)
        store.activeStore?.newScratch()
        store.persistNow()
        store.activeStore?.select(firstBufferID)

        let groupID = store.primaryGroupID
        var externalBuffer = EditorBuffer.scratch(index: 1)
        externalBuffer.text = "external iCloud note"
        externalBuffer.isDirty = true

        try workspacePersistence.sessionPersistence(for: .default).save(
            windowGroups: [
                EditorWindowGroupState(id: groupID, selectedBufferID: externalBuffer.id, buffers: [externalBuffer])
            ],
            selectedGroupID: groupID
        )

        XCTAssertTrue(store.reloadAppDataRootIfChanged())
        XCTAssertEqual(store.activeStore?.selectedBuffer?.id, externalBuffer.id)
        XCTAssertEqual(store.activeStore?.selectedBuffer?.text, "external iCloud note")
    }

    func testExternalAppDataRootChangeDoesNotReplacePendingLocalEdits() throws {
        let workspacePersistence = WorkspacePersistence(rootURL: temporaryDirectory)
        let store = WorkspaceStore(
            workspacePersistence: workspacePersistence,
            opensRestoredManualWindows: false,
            observesExternalOpenURLs: false,
            startsLocalAutomationBridge: false,
            monitorsExternalAppDataChanges: false
        )
        let localBufferID = try XCTUnwrap(store.activeStore?.selectedBuffer?.id)
        store.activeStore?.updateText("local pending note", in: localBufferID)

        let groupID = store.primaryGroupID
        var externalBuffer = EditorBuffer.scratch(index: 1)
        externalBuffer.text = "external iCloud note"
        externalBuffer.isDirty = true

        try workspacePersistence.sessionPersistence(for: .default).save(
            windowGroups: [
                EditorWindowGroupState(id: groupID, selectedBufferID: externalBuffer.id, buffers: [externalBuffer])
            ],
            selectedGroupID: groupID
        )

        XCTAssertFalse(store.reloadAppDataRootIfChanged())
        XCTAssertEqual(store.activeStore?.selectedBuffer?.id, localBufferID)
        XCTAssertEqual(store.activeStore?.selectedBuffer?.text, "local pending note")
        XCTAssertEqual(store.appDataSyncStatus, "App data changed on disk; pending local edits were kept in the current window.")
    }

    func testWorkspaceRestoreSkipsPersistedFullTextForLargeJSONFile() async throws {
        let workspacePersistence = WorkspacePersistence(rootURL: temporaryDirectory)
        let sessionPersistence = workspacePersistence.sessionPersistence(for: .default)
        let jsonURL = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: jsonURL, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = jsonURL.path
        buffer.text = json
        buffer.language = .json
        buffer.isDirty = false
        buffer.savePolicy = .normal
        let groupID = UUID()

        try sessionPersistence.save(
            windowGroups: [
                EditorWindowGroupState(id: groupID, selectedBufferID: buffer.id, buffers: [buffer])
            ],
            selectedGroupID: groupID
        )

        let loadedBuffer = try XCTUnwrap(sessionPersistence.loadWindowSession().groups.first?.buffers.first)
        XCTAssertEqual(loadedBuffer.text, "")
        XCTAssertTrue(loadedBuffer.isLargeFileMode)
        XCTAssertEqual(loadedBuffer.savePolicy, .readOnly)
        XCTAssertFalse(loadedBuffer.isDirty)

        let store = WorkspaceStore(
            workspacePersistence: workspacePersistence,
            opensRestoredManualWindows: false,
            observesExternalOpenURLs: false,
            startsLocalAutomationBridge: false
        )
        let restored = try XCTUnwrap(store.activeStore?.selectedBuffer)

        XCTAssertEqual(restored.language, .json)
        XCTAssertTrue(restored.isLargeFileMode)
        XCTAssertEqual(restored.savePolicy, .readOnly)
        XCTAssertFalse(restored.isDirty)
        XCTAssertEqual(restored.text, "")

        let loaded = try await waitForLoadedSelectedBuffer(in: store, filePath: jsonURL.path)
        XCTAssertLessThan(loaded.text.count, json.count)
        XCTAssertLessThanOrEqual(loaded.text.utf8.count, EditorStore.complexTextLargeFilePreviewByteLimit + 360)
        XCTAssertTrue(loaded.text.contains("SimpleLime large-file preview"))
    }

    func testWorkspaceOpenLargeOpenAPIJSONStartsAsBoundedPreviewAndClosesBeforeLoadCompletes() async throws {
        let store = makeStore()
        let jsonURL = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedOpenAPISizedJSON(lineCount: 22_000)
        try json.write(to: jsonURL, atomically: true, encoding: .utf8)

        XCTAssertGreaterThan(Int64(json.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)

        store.openFilesInActiveWindow([jsonURL])
        let openingBuffer = try XCTUnwrap(store.activeStore?.selectedBuffer)

        XCTAssertEqual(openingBuffer.filePath, jsonURL.path)
        XCTAssertEqual(openingBuffer.language, .json)
        XCTAssertTrue(openingBuffer.isLargeFileMode)
        XCTAssertEqual(openingBuffer.savePolicy, .readOnly)
        XCTAssertFalse(openingBuffer.isDirty)
        XCTAssertEqual(openingBuffer.text, "")

        store.activeStore?.closeBuffer(id: openingBuffer.id)

        XCTAssertNil(store.activeStore?.pendingCloseBuffer)
        XCTAssertFalse(store.activeStore?.buffers.contains { $0.id == openingBuffer.id } ?? true)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(store.activeStore?.buffers.contains { $0.filePath == jsonURL.path } ?? true)
        XCTAssertNil(store.activeStore?.lastError)
    }

    func testNamedWorkspacesKeepIndependentManualTasks() throws {
        var store = makeStore()
        let defaultWorkspaceID = store.activeWorkspaceID

        store.activeStore?.addManualTask(title: "Default task")
        let work = try XCTUnwrap(store.createWorkspace(named: "Work"))
        store.activeStore?.addManualTask(title: "Work task")

        XCTAssertEqual(store.activeStore?.manualTasks.map(\.title), ["Work task"])

        store.switchWorkspace(defaultWorkspaceID)
        XCTAssertEqual(store.activeStore?.manualTasks.map(\.title), ["Default task"])

        store.switchWorkspace(work.id)
        XCTAssertEqual(store.activeStore?.manualTasks.map(\.title), ["Work task"])

        store.persistNow()
        store = makeStore()

        XCTAssertEqual(store.activeWorkspaceID, work.id)
        XCTAssertEqual(store.activeStore?.manualTasks.map(\.title), ["Work task"])

        store.switchWorkspace(defaultWorkspaceID)
        XCTAssertEqual(store.activeStore?.manualTasks.map(\.title), ["Default task"])
    }

    func testGlobalManualTasksFollowWorkspaceSwitchesAndSyncAcrossWindows() throws {
        var store = makeStore()
        let defaultWorkspaceID = store.activeWorkspaceID
        let primaryGroupID = store.primaryGroupID

        store.activeStore?.addManualTask(title: "Global task", scope: .global)
        store.activeStore?.addManualTask(title: "Default task")
        store.newWindow()
        XCTAssertEqual(store.store(for: primaryGroupID)?.globalManualTasks.map(\.title), ["Global task"])
        XCTAssertEqual(store.activeStore?.globalManualTasks.map(\.title), ["Global task"])
        store.activeStore?.addManualTask(title: "Window global task", scope: .global)
        XCTAssertEqual(
            store.store(for: primaryGroupID)?.globalManualTasks.map(\.title),
            ["Window global task", "Global task"]
        )

        let work = try XCTUnwrap(store.createWorkspace(named: "Work"))
        XCTAssertEqual(store.activeStore?.globalManualTasks.map(\.title), ["Window global task", "Global task"])
        XCTAssertEqual(store.activeStore?.manualTasks.map(\.title), [])
        store.activeStore?.addManualTask(title: "Work task")

        store.switchWorkspace(defaultWorkspaceID)
        XCTAssertEqual(store.activeStore?.globalManualTasks.map(\.title), ["Window global task", "Global task"])
        XCTAssertEqual(store.activeStore?.manualTasks.map(\.title), ["Default task"])

        store.switchWorkspace(work.id)
        XCTAssertEqual(store.activeStore?.globalManualTasks.map(\.title), ["Window global task", "Global task"])
        XCTAssertEqual(store.activeStore?.manualTasks.map(\.title), ["Work task"])

        store.persistNow()
        store = makeStore()

        XCTAssertEqual(store.activeWorkspaceID, work.id)
        XCTAssertEqual(store.activeStore?.globalManualTasks.map(\.title), ["Window global task", "Global task"])
        XCTAssertEqual(store.activeStore?.manualTasks.map(\.title), ["Work task"])
    }

    func testNamedWorkspacesKeepIndependentDocumentCatalogRoots() throws {
        var store = makeStore()
        let defaultWorkspaceID = store.activeWorkspaceID
        let defaultDocs = try makeFolder(named: "DefaultDocs")
        let workDocs = try makeFolder(named: "WorkDocs")

        store.activeStore?.openFolder(at: defaultDocs)
        XCTAssertEqual(store.activeStore?.documentCatalogRootPath, defaultDocs.path)

        let work = try XCTUnwrap(store.createWorkspace(named: "Work"))
        XCTAssertNil(store.activeStore?.documentCatalogRootPath)

        store.activeStore?.openFolder(at: workDocs)
        XCTAssertEqual(store.activeStore?.documentCatalogRootPath, workDocs.path)

        store.switchWorkspace(defaultWorkspaceID)
        XCTAssertEqual(store.activeStore?.documentCatalogRootPath, defaultDocs.path)

        store.switchWorkspace(work.id)
        XCTAssertEqual(store.activeStore?.documentCatalogRootPath, workDocs.path)

        store.persistNow()
        store = makeStore()

        XCTAssertEqual(store.activeWorkspaceID, work.id)
        XCTAssertEqual(store.activeStore?.documentCatalogRootPath, workDocs.path)

        store.switchWorkspace(defaultWorkspaceID)
        XCTAssertEqual(store.activeStore?.documentCatalogRootPath, defaultDocs.path)
    }

    func testDocumentCatalogRootChangePropagatesAcrossWorkspaceWindows() throws {
        let store = makeStore()
        let root = try makeFolder(named: "SharedDocs")
        let primaryGroupID = store.primaryGroupID

        store.newWindow()
        let secondaryStore = try XCTUnwrap(store.activeStore)
        secondaryStore.openFolder(at: root)

        XCTAssertEqual(secondaryStore.documentCatalogRootPath, root.path)
        XCTAssertEqual(store.store(for: primaryGroupID)?.documentCatalogRootPath, root.path)
    }

    func testWorkspaceNamesAreValidated() throws {
        let store = makeStore()

        XCTAssertNil(store.createWorkspace(named: "   "))
        XCTAssertNotNil(store.lastActiveError)

        _ = try XCTUnwrap(store.createWorkspace(named: "Work"))
        XCTAssertFalse(store.renameActiveWorkspace(to: "Default"))
        XCTAssertTrue(store.renameActiveWorkspace(to: "Office"))
        XCTAssertEqual(store.activeWorkspaceName, "Office")
    }

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(
            workspacePersistence: WorkspacePersistence(rootURL: temporaryDirectory),
            opensRestoredManualWindows: false,
            observesExternalOpenURLs: false
        )
    }

    private func makeFolder(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "# \(name)".write(to: url.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        return url
    }

    private func waitForLoadedSelectedBuffer(in store: WorkspaceStore, filePath: String) async throws -> EditorBuffer {
        for _ in 0..<200 {
            if let buffer = store.activeStore?.selectedBuffer,
               buffer.filePath == filePath,
               !buffer.text.isEmpty {
                return buffer
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for restored large file preview")
        return try XCTUnwrap(store.activeStore?.selectedBuffer)
    }

    private func generatedComplexJSON() -> String {
        var paths: [String] = []
        var pathPayloadBytes = 0
        while pathPayloadBytes <= EditorStore.complexTextLargeFileModeThresholdBytes {
            let entry = #"{"path":"/api/v1/products/\#(paths.count)","method":"get","description":"Generated OpenAPI path used to exercise bounded JSON loading."}"#
            pathPayloadBytes += entry.utf8.count + (paths.isEmpty ? 0 : 1)
            paths.append(entry)
        }
        return #"{"openapi":"3.1.0","paths":["# + paths.joined(separator: ",") + #"]}"#
    }

    private func generatedOpenAPISizedJSON(lineCount: Int) -> String {
        var lines = [
            #"{"openapi":"3.1.0","#,
            #""info":{"title":"Large API","version":"1.0.0"},"#,
            #""paths":{"#
        ]
        for index in 0..<lineCount {
            let suffix = index == lineCount - 1 ? "" : ","
            lines.append(
                #""/api/v1/items/\#(index)":{"get":{"operationId":"getItem\#(index)","responses":{"200":{"description":"OK"}}}}\#(suffix)"#
            )
        }
        lines.append("}}")
        return lines.joined(separator: "\n")
    }
}

private extension WorkspaceStore {
    var lastActiveError: String? {
        activeStore?.lastError
    }
}
