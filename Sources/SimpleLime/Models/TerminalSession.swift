import Foundation

struct TerminalSession: Identifiable, Equatable {
    var id: UUID
    var title: String
    var workingDirectoryPath: String
    var output: String
    var rawOutputData: Data
    var isRunning: Bool
    var lastExitStatus: Int32?
    var createdAt: Date
    var clearGeneration: Int

    static func new(index: Int, workingDirectory: URL) -> TerminalSession {
        TerminalSession(
            id: UUID(),
            title: "Terminal \(index)",
            workingDirectoryPath: workingDirectory.standardizedFileURL.path,
            output: "",
            rawOutputData: Data(),
            isRunning: true,
            lastExitStatus: nil,
            createdAt: Date(),
            clearGeneration: 0
        )
    }
}
