import Foundation

struct StoredTaskBoard: Codable {
    var manualTasks: [ManualTask]
}

final class TaskBoardPersistence {
    private let fileManager: FileManager
    private let boardURL: URL

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager

        boardURL = Self.defaultBoardURL(fileManager: fileManager, defaults: defaults)
    }

    init(fileManager: FileManager = .default, boardURL: URL) {
        self.fileManager = fileManager
        self.boardURL = boardURL
    }

    func load() -> [ManualTask] {
        guard let data = try? Data(contentsOf: boardURL),
              let board = try? JSONDecoder.taskBoardDecoder.decode(StoredTaskBoard.self, from: data) else {
            return []
        }

        return board.manualTasks
    }

    func save(_ manualTasks: [ManualTask]) throws {
        try fileManager.createDirectory(at: boardURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.taskBoardEncoder.encode(StoredTaskBoard(manualTasks: manualTasks))
        try data.write(to: boardURL, options: .atomic)
    }

    static func defaultBoardURL(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> URL {
        AppDataStorage.currentRootURL(fileManager: fileManager, defaults: defaults)
            .appendingPathComponent("tasks.json", isDirectory: false)
    }

    static func defaultGlobalBoardURL(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> URL {
        AppDataStorage.currentRootURL(fileManager: fileManager, defaults: defaults)
            .appendingPathComponent("global-tasks.json", isDirectory: false)
    }
}

private extension JSONEncoder {
    static var taskBoardEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var taskBoardDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
