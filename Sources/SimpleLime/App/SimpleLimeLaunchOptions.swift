import Foundation

enum SimpleLimeLaunchOptions {
    static let safeModeArguments: Set<String> = [
        "--safe-mode",
        "--simplelime-safe-mode"
    ]

    static func shouldSkipRestoredSession(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.dropFirst().contains { safeModeArguments.contains($0) }
    }
}
