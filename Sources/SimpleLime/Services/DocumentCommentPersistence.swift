import Foundation

struct StoredDocumentComments: Codable {
    var version: Int
    var comments: [DocumentComment]
}

final class DocumentCommentPersistence {
    private let fileManager: FileManager
    private let fileURL: URL

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager

        if let fileURL {
            self.fileURL = fileURL
            return
        }

        self.fileURL = Self.defaultCommentsURL(fileManager: fileManager, defaults: defaults)
    }

    func load() -> [DocumentComment] {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder.commentDecoder.decode(StoredDocumentComments.self, from: data) else {
            return []
        }

        return stored.comments
    }

    func save(_ comments: [DocumentComment]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.commentEncoder.encode(
            StoredDocumentComments(version: 1, comments: comments)
        )
        try data.write(to: fileURL, options: .atomic)
    }

    static func defaultCommentsURL(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> URL {
        AppDataStorage.currentRootURL(fileManager: fileManager, defaults: defaults)
            .appendingPathComponent("comments.json", isDirectory: false)
    }
}

private extension JSONEncoder {
    static var commentEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var commentDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
