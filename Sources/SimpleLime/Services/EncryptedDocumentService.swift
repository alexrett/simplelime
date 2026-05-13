import CryptoKit
import Foundation
import Security

enum EncryptedDocumentServiceError: LocalizedError, Equatable {
    case emptyPassword
    case invalidEnvelope
    case invalidUTF8
    case wrongPasswordOrCorruptData
    case randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .emptyPassword:
            "Password cannot be empty."
        case .invalidEnvelope:
            "This is not a SimpleLime encrypted document."
        case .invalidUTF8:
            "The decrypted document is not valid UTF-8 text."
        case .wrongPasswordOrCorruptData:
            "The password is wrong or the encrypted document is corrupt."
        case .randomGenerationFailed:
            "Could not generate secure random bytes."
        }
    }
}

enum EncryptedDocumentService {
    static let fileExtension = "slenc"
    static let magic = "SIMPLELIME-ENCRYPTED-DOCUMENT\n"

    private static let currentVersion = 1
    private static let saltByteCount = 16
    private static let keyByteCount = 32
    private static let defaultIterations = 210_000
    static var passwordKeyDerivationIterationsOverride: Int?

    static func isEncryptedDocument(_ data: Data) -> Bool {
        data.starts(with: Data(magic.utf8))
    }

    static func shouldProbeEncryptedEnvelope(at url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare(fileExtension) == .orderedSame
    }

    static func isEncryptedDocument(at url: URL) -> Bool {
        guard shouldProbeEncryptedEnvelope(at: url) else { return false }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: Data(magic.utf8).count)) ?? Data()
        return prefix == Data(magic.utf8)
    }

    static func encrypt(text: String, password: String, iterations: Int? = nil) throws -> Data {
        try encrypt(data: Data(text.utf8), password: password, iterations: iterations)
    }

    static func encrypt(data plaintext: Data, password: String, iterations: Int? = nil) throws -> Data {
        let iterationCount = iterations ?? passwordKeyDerivationIterationsOverride ?? defaultIterations
        let passwordData = try passwordData(password)
        let salt = try randomData(byteCount: saltByteCount)
        let key = try deriveKey(passwordData: passwordData, salt: salt, iterations: iterationCount)
        let sealed = try AES.GCM.seal(plaintext, using: key)

        guard let combined = sealed.combined else {
            throw EncryptedDocumentServiceError.wrongPasswordOrCorruptData
        }

        let envelope = EncryptedDocumentEnvelope(
            version: currentVersion,
            algorithm: "AES-256-GCM",
            kdf: "PBKDF2-HMAC-SHA256",
            iterations: iterationCount,
            salt: salt.base64EncodedString(),
            payload: combined.base64EncodedString()
        )
        let body = try JSONEncoder().encode(envelope)
        return Data(magic.utf8) + body
    }

    static func decryptText(from data: Data, password: String) throws -> String {
        let plaintext = try decryptData(from: data, password: password)
        guard let text = String(data: plaintext, encoding: .utf8) else {
            throw EncryptedDocumentServiceError.invalidUTF8
        }
        return text
    }

    static func decryptData(from data: Data, password: String) throws -> Data {
        guard isEncryptedDocument(data),
              let bodyRange = data.range(of: Data(magic.utf8)) else {
            throw EncryptedDocumentServiceError.invalidEnvelope
        }

        let bodyStart = bodyRange.upperBound
        let envelopeData = data.subdata(in: bodyStart..<data.endIndex)
        guard let envelope = try? JSONDecoder().decode(EncryptedDocumentEnvelope.self, from: envelopeData),
              envelope.version == currentVersion,
              envelope.algorithm == "AES-256-GCM",
              envelope.kdf == "PBKDF2-HMAC-SHA256",
              envelope.iterations > 0,
              let salt = Data(base64Encoded: envelope.salt),
              let payload = Data(base64Encoded: envelope.payload) else {
            throw EncryptedDocumentServiceError.invalidEnvelope
        }

        let passwordData = try passwordData(password)
        let key = try deriveKey(passwordData: passwordData, salt: salt, iterations: envelope.iterations)

        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: payload), using: key)
        } catch {
            throw EncryptedDocumentServiceError.wrongPasswordOrCorruptData
        }
    }

    private static func passwordData(_ password: String) throws -> Data {
        guard !password.isEmpty else {
            throw EncryptedDocumentServiceError.emptyPassword
        }
        return Data(password.utf8)
    }

    private static func deriveKey(passwordData: Data, salt: Data, iterations: Int) throws -> SymmetricKey {
        let keyData = try pbkdf2SHA256(
            passwordData: passwordData,
            salt: salt,
            iterations: iterations,
            keyByteCount: keyByteCount
        )
        return SymmetricKey(data: keyData)
    }

    private static func pbkdf2SHA256(
        passwordData: Data,
        salt: Data,
        iterations: Int,
        keyByteCount: Int
    ) throws -> Data {
        guard iterations > 0, keyByteCount > 0 else {
            throw EncryptedDocumentServiceError.invalidEnvelope
        }

        let passwordKey = SymmetricKey(data: passwordData)
        let hashByteCount = SHA256.byteCount
        let blockCount = Int(ceil(Double(keyByteCount) / Double(hashByteCount)))
        var derived = Data()

        for blockIndex in 1...blockCount {
            var blockSalt = salt
            var bigEndianIndex = UInt32(blockIndex).bigEndian
            withUnsafeBytes(of: &bigEndianIndex) { blockSalt.append(contentsOf: $0) }

            var digest = Data(HMAC<SHA256>.authenticationCode(for: blockSalt, using: passwordKey))
            var block = digest

            if iterations > 1 {
                for _ in 2...iterations {
                    digest = Data(HMAC<SHA256>.authenticationCode(for: digest, using: passwordKey))
                    for index in block.indices {
                        block[index] ^= digest[index]
                    }
                }
            }

            derived.append(block)
        }

        return derived.prefix(keyByteCount)
    }

    private static func randomData(byteCount: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw EncryptedDocumentServiceError.randomGenerationFailed
        }
        return Data(bytes)
    }
}

private struct EncryptedDocumentEnvelope: Codable {
    let version: Int
    let algorithm: String
    let kdf: String
    let iterations: Int
    let salt: String
    let payload: String
}
