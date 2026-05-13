import Foundation

enum TerminalConfiguration {
    static let shellPathDefaultsKey = "terminal.shellPath"
    static let terminalTypeDefaultsKey = "terminal.type"
    static let localeDefaultsKey = "terminal.locale"
    static let fallbackShellPath = "/bin/zsh"
    static let defaultTerminalType = "xterm-256color"
    static let defaultLocale = "en_US.UTF-8"
    static let supportedTerminalTypes = [
        "xterm-256color",
        "xterm-24bit",
        "screen-256color",
        "tmux-256color",
        "vt100"
    ]

    static func currentShellPath(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let configured = defaults.string(forKey: shellPathDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }

        let environmentShell = environment["SHELL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentShell, !environmentShell.isEmpty {
            return environmentShell
        }

        return fallbackShellPath
    }

    static func currentTerminalType(defaults: UserDefaults = .standard) -> String {
        sanitizedTerminalType(defaults.string(forKey: terminalTypeDefaultsKey))
    }

    static func currentLocale(defaults: UserDefaults = .standard) -> String {
        sanitizedLocale(defaults.string(forKey: localeDefaultsKey))
    }

    static func sanitizedTerminalType(_ rawValue: String?) -> String {
        let trimmed = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return defaultTerminalType
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        guard !filtered.isEmpty else {
            return defaultTerminalType
        }

        return String(filtered.prefix(64))
    }

    static func sanitizedLocale(_ rawValue: String?) -> String {
        let trimmed = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return defaultLocale
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@")
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        guard !filtered.isEmpty else {
            return defaultLocale
        }

        let limited = String(filtered.prefix(64))
        guard isUTF8Locale(limited) else {
            return defaultLocale
        }

        return limited
    }

    static func isUTF8Locale(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return normalized.contains("utf-8") || normalized.contains("utf8")
    }
}
