import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreFileVersionTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testNextVersionedCopyURLPreservesExtensionAndSkipsExistingCopies() throws {
        let source = temporaryDirectory.appendingPathComponent("note.md")
        let firstCopy = temporaryDirectory.appendingPathComponent("note.1.md")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        try "copy".write(to: firstCopy, atomically: true, encoding: .utf8)

        XCTAssertEqual(EditorStore.nextVersionedCopyURL(for: source), temporaryDirectory.appendingPathComponent("note.2.md"))
    }

    func testSaveVersionedCopyWritesCurrentBufferTextWithoutRepointingBuffer() throws {
        let source = temporaryDirectory.appendingPathComponent("draft.txt")
        try "old".write(to: source, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.filePath = source.path
        buffer.title = source.lastPathComponent
        buffer.text = "current edits"
        buffer.language = .plain
        buffer.isDirty = true

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.saveVersionedCopyOfSelected()

        let version = temporaryDirectory.appendingPathComponent("draft.1.txt")
        XCTAssertEqual(try String(contentsOf: version), "current edits")
        XCTAssertEqual(store.selectedBuffer?.filePath, source.path)
        XCTAssertEqual(store.selectedBuffer?.isDirty, true)
    }

    func testSaveWithNumberedBackupCopiesDiskFileBeforeSavingCurrentEdits() throws {
        let source = temporaryDirectory.appendingPathComponent("draft.txt")
        try "old disk state".write(to: source, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.filePath = source.path
        buffer.title = source.lastPathComponent
        buffer.text = "current edits"
        buffer.language = .plain
        buffer.isDirty = true

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.saveSelectedWithNumberedBackup()

        let version = temporaryDirectory.appendingPathComponent("draft.1.txt")
        XCTAssertEqual(try String(contentsOf: version), "old disk state")
        XCTAssertEqual(try String(contentsOf: source), "current edits")
        XCTAssertEqual(store.selectedBuffer?.filePath, source.path)
        XCTAssertEqual(store.selectedBuffer?.isDirty, false)
        XCTAssertEqual(store.networkShare.statusMessage, "Saved draft.txt with backup draft.1.txt.")
    }

    func testSaveWithNumberedBackupSkipsExistingVersions() throws {
        let source = temporaryDirectory.appendingPathComponent("draft.txt")
        let firstVersion = temporaryDirectory.appendingPathComponent("draft.1.txt")
        try "old disk state".write(to: source, atomically: true, encoding: .utf8)
        try "older version".write(to: firstVersion, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.filePath = source.path
        buffer.title = source.lastPathComponent
        buffer.text = "current edits"
        buffer.language = .plain
        buffer.isDirty = true

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.saveSelectedWithNumberedBackup()

        let secondVersion = temporaryDirectory.appendingPathComponent("draft.2.txt")
        XCTAssertEqual(try String(contentsOf: firstVersion), "older version")
        XCTAssertEqual(try String(contentsOf: secondVersion), "old disk state")
        XCTAssertEqual(try String(contentsOf: source), "current edits")
    }
}
