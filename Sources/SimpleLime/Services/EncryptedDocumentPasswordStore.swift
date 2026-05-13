import Foundation
import LocalAuthentication
import Security

enum EncryptedDocumentPasswordStoreError: LocalizedError {
    case unavailable
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Touch ID password storage is not available on this Mac."
        case .keychain(let status):
            "Keychain returned status \(status)."
        }
    }
}

enum EncryptedDocumentPasswordStore {
    private static let service = "com.whitehappypony.SimpleLime.encrypted-document-password"

    static var canUseTouchID: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static func save(password: String, for url: URL) throws {
        guard canUseTouchID else {
            throw EncryptedDocumentPasswordStoreError.unavailable
        }

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) else {
            throw EncryptedDocumentPasswordStoreError.unavailable
        }

        let account = accountKey(for: url)
        deletePassword(for: url)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: Data(password.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptedDocumentPasswordStoreError.keychain(status)
        }
    }

    static func loadPassword(for url: URL, reason: String) throws -> String? {
        let context = LAContext()
        context.localizedReason = reason

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(for: url),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw EncryptedDocumentPasswordStoreError.keychain(status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for url: URL) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(for: url)
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func accountKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
