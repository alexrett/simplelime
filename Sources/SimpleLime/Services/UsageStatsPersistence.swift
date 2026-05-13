import Foundation

struct StoredUsageStats: Codable {
    var days: [DailyUsageStats]
}

final class UsageStatsPersistence {
    private let fileManager: FileManager
    private let statsURL: URL

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager

        statsURL = Self.defaultStatsURL(fileManager: fileManager, defaults: defaults)
    }

    init(fileManager: FileManager = .default, statsURL: URL) {
        self.fileManager = fileManager
        self.statsURL = statsURL
    }

    func load() -> [DailyUsageStats] {
        guard let data = try? Data(contentsOf: statsURL),
              let stored = try? JSONDecoder.usageStatsDecoder.decode(StoredUsageStats.self, from: data) else {
            return []
        }

        return stored.days
    }

    func save(_ days: [DailyUsageStats]) throws {
        try fileManager.createDirectory(at: statsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sorted = days.sorted { $0.day < $1.day }
        let data = try JSONEncoder.usageStatsEncoder.encode(StoredUsageStats(days: sorted))
        try data.write(to: statsURL, options: .atomic)
    }

    static func defaultStatsURL(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> URL {
        AppDataStorage.currentRootURL(fileManager: fileManager, defaults: defaults)
            .appendingPathComponent("usage-stats.json", isDirectory: false)
    }
}

private extension JSONEncoder {
    static var usageStatsEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var usageStatsDecoder: JSONDecoder {
        JSONDecoder()
    }
}
