import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreLocalAutomationTests: XCTestCase {
    func testScribeRequestsAppendToNamedTranscriptScratch() {
        let store = makeStore()

        let first = store.appendScribeTranscript(
            LocalAutomationScribeRequest(
                title: "Planning",
                text: "First point",
                speaker: "Alex",
                timestamp: "09:00",
                language: .markdown,
                mode: nil
            )
        )
        let second = store.appendScribeTranscript(
            LocalAutomationScribeRequest(
                title: "Planning",
                text: "Second point",
                speaker: "Maya",
                timestamp: "09:01",
                language: .markdown,
                mode: nil
            )
        )

        XCTAssertTrue(first.ok)
        XCTAssertTrue(second.ok)
        XCTAssertEqual(store.selectedBuffer?.title, "Planning")
        XCTAssertEqual(
            store.selectedBuffer?.text,
            """
            [09:00] **Alex**: First point
            [09:01] **Maya**: Second point
            """ + "\n"
        )
        XCTAssertEqual(store.buffers.filter { $0.title == "Planning" }.count, 1)
    }

    func testLocalAutomationInsertTextCommandUsesCurrentSelection() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "Hello world"
        buffer.selectionRanges = [TextRange(location: 6, length: 5)]
        let store = makeStore(buffer: buffer)

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .insertText, text: "SimpleLime")
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(store.selectedBuffer?.text, "Hello SimpleLime")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [TextRange(location: 6, length: 10)])
    }

    func testLocalAutomationInsertTextRequiresPayload() {
        let store = makeStore()

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .insertText, text: nil)
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.message, "insertText requires non-empty text.")
    }

    func testLocalAutomationInsertTextRejectsReadOnlyLargePreview() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "openapi.json"
        buffer.kind = .file
        buffer.filePath = "/tmp/openapi.json"
        buffer.text = #"{"openapi":"3.0.3"}"#
        buffer.isLargeFileMode = true
        buffer.savePolicy = .readOnly
        let store = makeStore(buffer: buffer)

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .insertText, text: "x")
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.bufferTitle, "openapi.json")
        XCTAssertEqual(store.selectedBuffer?.text, #"{"openapi":"3.0.3"}"#)
    }

    func testLocalAutomationReplaceLargeFileLineRequiresLineNumber() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "large.txt"
        buffer.kind = .file
        buffer.filePath = "/tmp/large.txt"
        buffer.isLargeFileMode = true
        let store = makeStore(buffer: buffer)

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .replaceLargeFileLine, text: "edited")
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.message, "replaceLargeFileLine requires a positive lineNumber.")
    }

    func testLocalAutomationReplaceLargeFileLineRejectsMultiLineText() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "large.txt"
        buffer.kind = .file
        buffer.filePath = "/tmp/large.txt"
        buffer.isLargeFileMode = true
        let store = makeStore(buffer: buffer)

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .replaceLargeFileLine, text: "one\ntwo", lineNumber: 2)
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.message, "Virtual line replacement accepts one replacement line.")
    }

    func testLocalAutomationInsertLargeFileLineRequiresLineNumber() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "large.txt"
        buffer.kind = .file
        buffer.filePath = "/tmp/large.txt"
        buffer.isLargeFileMode = true
        let store = makeStore(buffer: buffer)

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .insertLargeFileLine, text: "inserted")
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.message, "insertLargeFileLine requires a positive lineNumber.")
    }

    func testLocalAutomationDeleteLargeFileLineRequiresLineNumber() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "large.txt"
        buffer.kind = .file
        buffer.filePath = "/tmp/large.txt"
        buffer.isLargeFileMode = true
        let store = makeStore(buffer: buffer)

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .deleteLargeFileLine, text: nil)
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.message, "deleteLargeFileLine requires a positive lineNumber.")
    }

    func testLocalAutomationInsertLargeFileLineRejectsMultiLineText() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "large.txt"
        buffer.kind = .file
        buffer.filePath = "/tmp/large.txt"
        buffer.isLargeFileMode = true
        let store = makeStore(buffer: buffer)

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .insertLargeFileLine, text: "one\ntwo", lineNumber: 2)
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.message, "Virtual line insertion accepts one inserted line.")
    }

    func testLocalAutomationReplaceLargeFileLineUpdatesSourceAndPreview() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("large.txt")
        let lines = (1...7_000).map { "line-\($0)" }
        let largeText = lines.joined(separator: "\n")
        try largeText.write(to: fileURL, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "large.txt"
        buffer.kind = .file
        buffer.filePath = fileURL.path
        buffer.language = .plain
        buffer.text = "line-1\nline-2"
        buffer.isLargeFileMode = true
        buffer.savePolicy = .readOnly
        buffer.fileSizeBytes = Int64(largeText.utf8.count)
        buffer.largeFilePreviewStartOffsetBytes = 0
        buffer.largeFilePreviewByteCount = buffer.text.utf8.count
        let store = makeStore(buffer: buffer)

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(
                command: .replaceLargeFileLine,
                text: "line-6000-edited",
                lineNumber: 6_000
            )
        )

        XCTAssertTrue(response.ok)
        let updatedText = try await waitForFile(fileURL, containing: "line-6000-edited")
        XCTAssertTrue(updatedText.contains("line-5999\nline-6000-edited\nline-6001"))
        let selected = try await waitForSelectedBuffer(in: store, containing: "line-6000-edited")
        XCTAssertTrue(selected.isLargeFileMode)
        XCTAssertEqual(store.largeFileSearchStatus, "Replaced line 6000 in large.txt.")
    }

    func testLocalAutomationInsertAndDeleteLargeFileLinesUpdateSourceAndPreview() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("large.txt")
        let lines = (1...7_000).map { "line-\($0)" }
        let largeText = lines.joined(separator: "\n")
        try largeText.write(to: fileURL, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "large.txt"
        buffer.kind = .file
        buffer.filePath = fileURL.path
        buffer.language = .plain
        buffer.text = "line-1\nline-2"
        buffer.isLargeFileMode = true
        buffer.savePolicy = .readOnly
        buffer.fileSizeBytes = Int64(largeText.utf8.count)
        buffer.largeFilePreviewStartOffsetBytes = 0
        buffer.largeFilePreviewByteCount = buffer.text.utf8.count
        let store = makeStore(buffer: buffer)

        let insertResponse = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(
                command: .insertLargeFileLine,
                text: "line-4000-inserted",
                lineNumber: 4_000
            )
        )

        XCTAssertTrue(insertResponse.ok)
        var updatedText = try await waitForFile(fileURL, containing: "line-4000-inserted")
        XCTAssertTrue(updatedText.contains("line-3999\nline-4000-inserted\nline-4000"))
        var selected = try await waitForSelectedBuffer(in: store, containing: "line-4000-inserted")
        XCTAssertTrue(selected.isLargeFileMode)
        XCTAssertEqual(store.largeFileSearchStatus, "Inserted line 4000 in large.txt.")

        let deleteResponse = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .deleteLargeFileLine, text: nil, lineNumber: 4_000)
        )

        XCTAssertTrue(deleteResponse.ok)
        updatedText = try await waitForFile(fileURL, excluding: "line-4000-inserted")
        XCTAssertTrue(updatedText.contains("line-3999\nline-4000\nline-4001"))
        selected = try await waitForSelectedBuffer(in: store, containing: "line-4000")
        XCTAssertTrue(selected.isLargeFileMode)
        XCTAssertEqual(store.largeFileSearchStatus, "Deleted line 4000 in large.txt.")
    }

    func testLocalAutomationLargeFileLineRangeCommandsUpdateSourceAndPreview() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("large.txt")
        let lines = (1...7_000).map { "line-\($0)" }
        let largeText = lines.joined(separator: "\n")
        try largeText.write(to: fileURL, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "large.txt"
        buffer.kind = .file
        buffer.filePath = fileURL.path
        buffer.language = .plain
        buffer.text = "line-1\nline-2"
        buffer.isLargeFileMode = true
        buffer.savePolicy = .readOnly
        buffer.fileSizeBytes = Int64(largeText.utf8.count)
        buffer.largeFilePreviewStartOffsetBytes = 0
        buffer.largeFilePreviewByteCount = buffer.text.utf8.count
        let store = makeStore(buffer: buffer)

        let replaceResponse = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(
                command: .replaceLargeFileLines,
                text: "range-a\nrange-b\n",
                lineNumber: 4_000,
                endLineNumber: 4_002
            )
        )

        XCTAssertTrue(replaceResponse.ok)
        var updatedText = try await waitForFile(fileURL, containing: "range-a")
        XCTAssertTrue(updatedText.contains("line-3999\nrange-a\nrange-b\nline-4003"))
        var selected = try await waitForSelectedBuffer(in: store, containing: "range-a")
        XCTAssertTrue(selected.isLargeFileMode)
        XCTAssertEqual(store.largeFileSearchStatus, "Replaced lines 4000-4002 in large.txt.")

        let insertResponse = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(
                command: .insertLargeFileLines,
                text: "insert-a\ninsert-b\n",
                lineNumber: 4_000
            )
        )

        XCTAssertTrue(insertResponse.ok)
        updatedText = try await waitForFile(fileURL, containing: "insert-a")
        XCTAssertTrue(updatedText.contains("line-3999\ninsert-a\ninsert-b\nrange-a"))
        selected = try await waitForSelectedBuffer(in: store, containing: "insert-a")
        XCTAssertTrue(selected.isLargeFileMode)
        XCTAssertEqual(store.largeFileSearchStatus, "Inserted 2 lines before line 4000 in large.txt.")

        let deleteResponse = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(
                command: .deleteLargeFileLines,
                text: nil,
                lineNumber: 4_000,
                endLineNumber: 4_001
            )
        )

        XCTAssertTrue(deleteResponse.ok)
        updatedText = try await waitForFile(fileURL, excluding: "insert-a")
        XCTAssertTrue(updatedText.contains("line-3999\nrange-a\nrange-b\nline-4003"))
        selected = try await waitForSelectedBuffer(in: store, containing: "range-a")
        XCTAssertTrue(selected.isLargeFileMode)
        XCTAssertEqual(store.largeFileSearchStatus, "Deleted lines 4000-4001 in large.txt.")
    }

    func testLocalAutomationLargeFileLineRangeRejectsInvertedRange() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "large.txt"
        buffer.kind = .file
        buffer.filePath = "/tmp/large.txt"
        buffer.isLargeFileMode = true
        let store = makeStore(buffer: buffer)

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(
                command: .deleteLargeFileLines,
                text: nil,
                lineNumber: 10,
                endLineNumber: 4
            )
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.message, "deleteLargeFileLines requires endLineNumber greater than or equal to lineNumber.")
    }

    func testLocalAutomationCanToggleScribePanel() {
        let store = makeStore()

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .toggleScribe, text: nil)
        )

        XCTAssertTrue(response.ok)
        XCTAssertTrue(store.isScribePanelVisible)
    }

    func testLocalAutomationCanToggleActivityWatch() {
        let store = makeStore()

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .toggleActivityWatch, text: nil)
        )

        XCTAssertTrue(response.ok)
        XCTAssertTrue(store.isUsageActivityWatchEnabled)
    }

    func testLocalAutomationForceCloseBypassesStuckCloseConfirmation() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "Unsaved state"
        buffer.isDirty = true
        let store = makeStore(buffer: buffer)

        let closeResponse = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .close, text: nil)
        )

        XCTAssertTrue(closeResponse.ok)
        XCTAssertEqual(store.pendingCloseBuffer?.id, buffer.id)

        let forceCloseResponse = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .forceClose, text: nil)
        )

        XCTAssertTrue(forceCloseResponse.ok)
        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertFalse(store.buffers.contains { $0.id == buffer.id })
        XCTAssertEqual(store.selectedBuffer?.kind, .scratch)
    }

    func testLocalAutomationForceClosePathClosesMatchingNonSelectedStuckTab() {
        let now = Date()
        let scratch = EditorBuffer.scratch(index: 1)
        let jsonURL = URL(fileURLWithPath: "/tmp/openapi.json")
        let jsonBuffer = EditorBuffer(
            id: UUID(),
            title: "openapi.json",
            kind: .file,
            filePath: jsonURL.path,
            text: #"{"openapi":"3.0.3"}"#,
            language: .json,
            createdAt: now,
            updatedAt: now,
            isDirty: true,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil
        )

        let store = EditorStore(
            initialBuffers: [scratch, jsonBuffer],
            selectedID: scratch.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: jsonBuffer.id)
        XCTAssertEqual(store.pendingCloseBuffer?.id, jsonBuffer.id)
        XCTAssertEqual(store.selectedBuffer?.id, scratch.id)

        let response = store.performLocalAutomationCommand(
            LocalAutomationCommandRequest(command: .forceClosePath, text: jsonURL.path)
        )

        XCTAssertTrue(response.ok)
        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertFalse(store.buffers.contains { $0.id == jsonBuffer.id })
        XCTAssertEqual(store.selectedBuffer?.id, scratch.id)
    }

    private func makeStore(buffer: EditorBuffer = EditorBuffer.scratch(index: 1)) -> EditorStore {
        EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForFile(_ url: URL, containing marker: String) async throws -> String {
        for _ in 0..<200 {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains(marker) {
                return text
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        return try String(contentsOf: url, encoding: .utf8)
    }

    private func waitForFile(_ url: URL, excluding marker: String) async throws -> String {
        for _ in 0..<200 {
            let text = try String(contentsOf: url, encoding: .utf8)
            if !text.contains(marker) {
                return text
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        return try String(contentsOf: url, encoding: .utf8)
    }

    private func waitForSelectedBuffer(in store: EditorStore, containing marker: String) async throws -> EditorBuffer {
        for _ in 0..<200 {
            if let buffer = store.selectedBuffer,
               buffer.text.contains(marker) {
                return buffer
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        return try XCTUnwrap(store.selectedBuffer)
    }
}
