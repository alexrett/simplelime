import Foundation

struct UsageTimelineEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case edit
        case open
        case save
        case export
        case macro
        case app
    }

    var id: UUID
    var timestamp: Date
    var kind: Kind
    var title: String
    var documentKey: String
    var durationSeconds: Int

    init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: Kind,
        title: String,
        documentKey: String,
        durationSeconds: Int = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.documentKey = documentKey
        self.durationSeconds = durationSeconds
    }
}

struct DailyUsageStats: Codable, Equatable, Identifiable {
    var day: String
    var editCount: Int
    var charactersAdded: Int
    var charactersRemoved: Int
    var openCount: Int
    var saveCount: Int
    var exportCount: Int
    var macroCount: Int
    var activeEditingSeconds: Int
    var uniqueDocumentKeys: Set<String>
    var timelineEntries: [UsageTimelineEntry]

    var id: String { day }

    init(
        day: String,
        editCount: Int,
        charactersAdded: Int,
        charactersRemoved: Int,
        openCount: Int,
        saveCount: Int,
        exportCount: Int,
        macroCount: Int = 0,
        activeEditingSeconds: Int,
        uniqueDocumentKeys: Set<String>,
        timelineEntries: [UsageTimelineEntry] = []
    ) {
        self.day = day
        self.editCount = editCount
        self.charactersAdded = charactersAdded
        self.charactersRemoved = charactersRemoved
        self.openCount = openCount
        self.saveCount = saveCount
        self.exportCount = exportCount
        self.macroCount = macroCount
        self.activeEditingSeconds = activeEditingSeconds
        self.uniqueDocumentKeys = uniqueDocumentKeys
        self.timelineEntries = timelineEntries
    }

    static func empty(day: String) -> DailyUsageStats {
        DailyUsageStats(
            day: day,
            editCount: 0,
            charactersAdded: 0,
            charactersRemoved: 0,
            openCount: 0,
            saveCount: 0,
            exportCount: 0,
            macroCount: 0,
            activeEditingSeconds: 0,
            uniqueDocumentKeys: [],
            timelineEntries: []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case day
        case editCount
        case charactersAdded
        case charactersRemoved
        case openCount
        case saveCount
        case exportCount
        case macroCount
        case activeEditingSeconds
        case uniqueDocumentKeys
        case timelineEntries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        editCount = try container.decodeIfPresent(Int.self, forKey: .editCount) ?? 0
        charactersAdded = try container.decodeIfPresent(Int.self, forKey: .charactersAdded) ?? 0
        charactersRemoved = try container.decodeIfPresent(Int.self, forKey: .charactersRemoved) ?? 0
        openCount = try container.decodeIfPresent(Int.self, forKey: .openCount) ?? 0
        saveCount = try container.decodeIfPresent(Int.self, forKey: .saveCount) ?? 0
        exportCount = try container.decodeIfPresent(Int.self, forKey: .exportCount) ?? 0
        macroCount = try container.decodeIfPresent(Int.self, forKey: .macroCount) ?? 0
        activeEditingSeconds = try container.decodeIfPresent(Int.self, forKey: .activeEditingSeconds) ?? 0
        uniqueDocumentKeys = try container.decodeIfPresent(Set<String>.self, forKey: .uniqueDocumentKeys) ?? []
        timelineEntries = try container.decodeIfPresent([UsageTimelineEntry].self, forKey: .timelineEntries) ?? []
    }
}

struct UsageStatsSummary: Equatable {
    var title: String
    var editCount: Int
    var charactersAdded: Int
    var charactersRemoved: Int
    var openCount: Int
    var saveCount: Int
    var exportCount: Int
    var macroCount: Int
    var activeEditingSeconds: Int
    var uniqueDocumentCount: Int
    var uniqueFileCount: Int
    var uniqueScratchCount: Int
    var timelineEntries: [UsageTimelineEntry]

    static func make(title: String, days: [DailyUsageStats]) -> UsageStatsSummary {
        let uniqueDocumentKeys = Set(days.flatMap(\.uniqueDocumentKeys))
        return UsageStatsSummary(
            title: title,
            editCount: days.reduce(0) { $0 + $1.editCount },
            charactersAdded: days.reduce(0) { $0 + $1.charactersAdded },
            charactersRemoved: days.reduce(0) { $0 + $1.charactersRemoved },
            openCount: days.reduce(0) { $0 + $1.openCount },
            saveCount: days.reduce(0) { $0 + $1.saveCount },
            exportCount: days.reduce(0) { $0 + $1.exportCount },
            macroCount: days.reduce(0) { $0 + $1.macroCount },
            activeEditingSeconds: days.reduce(0) { $0 + $1.activeEditingSeconds },
            uniqueDocumentCount: uniqueDocumentKeys.count,
            uniqueFileCount: uniqueDocumentKeys.filter { $0.hasPrefix("file:") }.count,
            uniqueScratchCount: uniqueDocumentKeys.filter { $0.hasPrefix("scratch:") }.count,
            timelineEntries: days
                .flatMap(\.timelineEntries)
                .sorted { $0.timestamp > $1.timestamp }
        )
    }
}

enum UsageStatsClock {
    static func dayIdentifier(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func recentDayIdentifiers(count: Int, from date: Date = Date(), calendar: Calendar = .current) -> Set<String> {
        guard count > 0 else { return [] }
        return Set((0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: date)
                .map { dayIdentifier(for: $0, calendar: calendar) }
        })
    }
}
