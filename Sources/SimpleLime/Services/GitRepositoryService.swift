import Foundation

enum GitRepositoryService {
    struct Repository: Equatable {
        let rootURL: URL
    }

    enum GitError: LocalizedError {
        case emptyMessage
        case notRepository
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyMessage:
                return "Commit message cannot be empty."
            case .notRepository:
                return "The selected file is not inside a git repository."
            case .commandFailed(let output):
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Git command failed." : trimmed
            }
        }
    }

    static func repository(containingFileAt fileURL: URL) -> Repository? {
        let workingDirectory = fileURL.deletingLastPathComponent()

        do {
            let output = try runGit(["-C", workingDirectory.path, "rev-parse", "--show-toplevel"])
            let rootPath = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rootPath.isEmpty else { return nil }
            return Repository(rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
        } catch {
            return nil
        }
    }

    static func commit(fileURL: URL, message: String) throws {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw GitError.emptyMessage
        }

        guard let repository = repository(containingFileAt: fileURL) else {
            throw GitError.notRepository
        }

        let relativePath = relativePath(for: fileURL, in: repository.rootURL)
        try runGit(["-C", repository.rootURL.path, "add", "--", relativePath])
        try runGit(["-C", repository.rootURL.path, "commit", "-m", trimmedMessage, "--", relativePath])
    }

    @discardableResult
    static func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combinedOutput = [output, error]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(combinedOutput)
        }

        return output
    }

    private static func relativePath(for fileURL: URL, in rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"

        guard filePath.hasPrefix(prefix) else {
            return filePath
        }

        return String(filePath.dropFirst(prefix.count))
    }
}
