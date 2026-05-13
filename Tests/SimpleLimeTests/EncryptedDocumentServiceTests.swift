import XCTest
@testable import SimpleLime

final class EncryptedDocumentServiceTests: XCTestCase {
    func testEncryptDecryptRoundTripDoesNotStorePlaintext() throws {
        let encrypted = try EncryptedDocumentService.encrypt(
            text: "Sensitive scratch text",
            password: "correct horse battery staple",
            iterations: 1_000
        )

        XCTAssertTrue(EncryptedDocumentService.isEncryptedDocument(encrypted))
        XCTAssertFalse(String(decoding: encrypted, as: UTF8.self).contains("Sensitive scratch text"))
        XCTAssertEqual(
            try EncryptedDocumentService.decryptText(from: encrypted, password: "correct horse battery staple"),
            "Sensitive scratch text"
        )
    }

    func testWrongPasswordFails() throws {
        let encrypted = try EncryptedDocumentService.encrypt(text: "secret", password: "right", iterations: 1_000)

        XCTAssertThrowsError(try EncryptedDocumentService.decryptText(from: encrypted, password: "wrong")) { error in
            XCTAssertEqual(error as? EncryptedDocumentServiceError, .wrongPasswordOrCorruptData)
        }
    }

    func testRejectsPlainTextAsInvalidEnvelope() {
        XCTAssertThrowsError(try EncryptedDocumentService.decryptText(from: Data("plain".utf8), password: "pw")) { error in
            XCTAssertEqual(error as? EncryptedDocumentServiceError, .invalidEnvelope)
        }
    }

    func testFileProbeIsExtensionGatedBeforeOpeningHandle() throws {
        let encrypted = try EncryptedDocumentService.encrypt(text: "secret", password: "pw", iterations: 1_000)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-encrypted-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let encryptedURL = directory.appendingPathComponent("note.slenc")
        let renamedURL = directory.appendingPathComponent("note.json")
        try encrypted.write(to: encryptedURL)
        try encrypted.write(to: renamedURL)

        XCTAssertTrue(EncryptedDocumentService.shouldProbeEncryptedEnvelope(at: encryptedURL))
        XCTAssertFalse(EncryptedDocumentService.shouldProbeEncryptedEnvelope(at: renamedURL))
        XCTAssertTrue(EncryptedDocumentService.isEncryptedDocument(at: encryptedURL))
        XCTAssertFalse(EncryptedDocumentService.isEncryptedDocument(at: renamedURL))
    }
}
