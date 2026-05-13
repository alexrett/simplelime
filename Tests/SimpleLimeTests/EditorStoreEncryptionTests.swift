import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreEncryptionTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        EncryptedDocumentService.passwordKeyDerivationIterationsOverride = 1_000
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-encryption-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        EncryptedDocumentService.passwordKeyDerivationIterationsOverride = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testSaveSelectedEncryptedWritesEncryptedFileAndMarksBufferSecure() throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "# Private\nDo not leak"
        buffer.language = .markdown
        let store = makeStore(buffer: buffer)

        let url = temporaryDirectory.appendingPathComponent("private")
        XCTAssertTrue(store.saveSelectedEncrypted(to: url, password: "pw"))

        let encryptedURL = temporaryDirectory.appendingPathComponent("private.slenc")
        let data = try Data(contentsOf: encryptedURL)
        XCTAssertTrue(EncryptedDocumentService.isEncryptedDocument(data))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Do not leak"))
        XCTAssertEqual(try EncryptedDocumentService.decryptText(from: data, password: "pw"), "# Private\nDo not leak")
        XCTAssertEqual(store.selectedBuffer?.filePath, encryptedURL.path)
        XCTAssertEqual(store.selectedBuffer?.isEncrypted, true)
        XCTAssertEqual(store.selectedBuffer?.language, .markdown)
        XCTAssertEqual(store.selectedBuffer?.isDirty, false)
    }

    func testOpenEncryptedFileUnlocksTextAndNormalSavePreservesEncryption() throws {
        let url = temporaryDirectory.appendingPathComponent("note.slenc")
        try EncryptedDocumentService.encrypt(text: "secret v1", password: "pw", iterations: 1_000).write(to: url)
        let store = makeStore(buffer: EditorBuffer.scratch(index: 1))

        store.openEncryptedFile(at: url, password: "pw")
        XCTAssertEqual(store.selectedBuffer?.text, "secret v1")
        XCTAssertEqual(store.selectedBuffer?.isEncrypted, true)

        store.updateText("secret v2", in: store.selectedBuffer!.id)
        store.saveSelected()

        let saved = try Data(contentsOf: url)
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("secret v2"))
        XCTAssertEqual(try EncryptedDocumentService.decryptText(from: saved, password: "pw"), "secret v2")
    }

    func testSaveAsPlainTextFromEncryptedBufferRemovesEncryption() throws {
        let url = temporaryDirectory.appendingPathComponent("note.slenc")
        try EncryptedDocumentService.encrypt(text: "secret", password: "pw", iterations: 1_000).write(to: url)
        let store = makeStore(buffer: EditorBuffer.scratch(index: 1))
        store.openEncryptedFile(at: url, password: "pw")

        let plainURL = temporaryDirectory.appendingPathComponent("note.txt")
        store.saveSelected(to: plainURL, as: .plain)

        XCTAssertEqual(try String(contentsOf: plainURL, encoding: .utf8), "secret")
        XCTAssertEqual(store.selectedBuffer?.isEncrypted, false)
        XCTAssertEqual(store.selectedBuffer?.filePath, plainURL.path)
    }

    func testVersionedCopyOfEncryptedBufferStaysEncrypted() throws {
        let url = temporaryDirectory.appendingPathComponent("note.slenc")
        try EncryptedDocumentService.encrypt(text: "secret", password: "pw", iterations: 1_000).write(to: url)
        let store = makeStore(buffer: EditorBuffer.scratch(index: 1))
        store.openEncryptedFile(at: url, password: "pw")
        store.updateText("secret copy", in: store.selectedBuffer!.id)

        store.saveVersionedCopyOfSelected()

        let versionURL = temporaryDirectory.appendingPathComponent("note.1.slenc")
        let data = try Data(contentsOf: versionURL)
        XCTAssertTrue(EncryptedDocumentService.isEncryptedDocument(data))
        XCTAssertEqual(try EncryptedDocumentService.decryptText(from: data, password: "pw"), "secret copy")
    }

    private func makeStore(buffer: EditorBuffer) -> EditorStore {
        EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }
}
