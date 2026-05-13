import AppKit

struct EncryptedDocumentPasswordPromptResult {
    let password: String
    let rememberWithTouchID: Bool
}

enum EncryptedDocumentPasswordPrompt {
    static func askForNewPassword(documentName: String) -> EncryptedDocumentPasswordPromptResult? {
        ask(
            title: "Encrypt \(documentName)",
            message: "Choose a password for this encrypted SimpleLime document.",
            confirmPassword: true,
            allowTouchIDStorage: EncryptedDocumentPasswordStore.canUseTouchID
        )
    }

    static func askForExistingPassword(documentName: String) -> EncryptedDocumentPasswordPromptResult? {
        ask(
            title: "Unlock \(documentName)",
            message: "Enter the password for this encrypted SimpleLime document.",
            confirmPassword: false,
            allowTouchIDStorage: EncryptedDocumentPasswordStore.canUseTouchID
        )
    }

    private static func ask(
        title: String,
        message: String,
        confirmPassword: Bool,
        allowTouchIDStorage: Bool
    ) -> EncryptedDocumentPasswordPromptResult? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmPassword ? "Encrypt" : "Unlock")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        passwordField.placeholderString = "Password"
        stack.addArrangedSubview(passwordField)

        let confirmationField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        if confirmPassword {
            confirmationField.placeholderString = "Confirm password"
            stack.addArrangedSubview(confirmationField)
        }

        let touchIDCheckbox = NSButton(checkboxWithTitle: "Remember password for Touch ID unlock", target: nil, action: nil)
        if allowTouchIDStorage {
            stack.addArrangedSubview(touchIDCheckbox)
        }

        alert.accessoryView = stack

        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let password = passwordField.stringValue
            guard !password.isEmpty else {
                alert.informativeText = "Password cannot be empty."
                continue
            }
            if confirmPassword, password != confirmationField.stringValue {
                alert.informativeText = "Passwords do not match."
                continue
            }
            return EncryptedDocumentPasswordPromptResult(
                password: password,
                rememberWithTouchID: allowTouchIDStorage && touchIDCheckbox.state == .on
            )
        }
    }
}
