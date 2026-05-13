import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreSavePolicyTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-save-policy-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testReadOnlyModeBlocksSavingCurrentFile() throws {
        let url = temporaryDirectory.appendingPathComponent("important.txt")
        try "original".write(to: url, atomically: true, encoding: .utf8)
        let store = makeStore(fileURL: url, text: "changed", savePolicy: .readOnly)

        store.saveSelected()

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "original")
        XCTAssertEqual(store.lastError, "important.txt is in read-only mode. Disable read-only mode before saving.")
    }

    func testTemporaryModeBlocksVersionedCopy() throws {
        let url = temporaryDirectory.appendingPathComponent("draft.md")
        try "draft".write(to: url, atomically: true, encoding: .utf8)
        let store = makeStore(fileURL: url, text: "changed", savePolicy: .temporary)

        store.saveVersionedCopyOfSelected()

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("draft.1.md").path))
        XCTAssertEqual(store.lastError, "draft.md is in temporary mode. Disable temporary mode before saving.")
    }

    func testSavePolicyTogglesReturnToNormal() throws {
        let url = temporaryDirectory.appendingPathComponent("note.txt")
        try "note".write(to: url, atomically: true, encoding: .utf8)
        let store = makeStore(fileURL: url, text: "note", savePolicy: .normal)

        store.toggleReadOnlyMode()
        XCTAssertEqual(store.selectedSavePolicy, .readOnly)

        store.toggleTemporaryMode()
        XCTAssertEqual(store.selectedSavePolicy, .temporary)

        store.toggleTemporaryMode()
        XCTAssertEqual(store.selectedSavePolicy, .normal)
    }

    private func makeStore(fileURL: URL, text: String, savePolicy: BufferSavePolicy) -> EditorStore {
        let now = Date()
        let buffer = EditorBuffer(
            id: UUID(),
            title: fileURL.lastPathComponent,
            kind: .file,
            filePath: fileURL.path,
            text: text,
            language: EditorLanguage.detect(fileName: fileURL.lastPathComponent, text: text),
            createdAt: now,
            updatedAt: now,
            isDirty: true,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil,
            savePolicy: savePolicy
        )

        return EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }
}
