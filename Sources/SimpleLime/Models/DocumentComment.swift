import Foundation

struct DocumentComment: Identifiable, Codable, Equatable {
    var id: UUID
    var documentKey: String
    var range: TextRange
    var quote: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var resolvedAt: Date?
    var reminderAt: Date?

    var isResolved: Bool {
        resolvedAt != nil
    }

    var displayQuote: String {
        let compact = quote
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? "Selection" : compact
    }

    init(
        id: UUID = UUID(),
        documentKey: String,
        range: TextRange,
        quote: String,
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        resolvedAt: Date? = nil,
        reminderAt: Date? = nil
    ) {
        self.id = id
        self.documentKey = documentKey
        self.range = range
        self.quote = quote
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.reminderAt = reminderAt
    }
}

enum CommentReminderPreset: CaseIterable, Identifiable {
    case fifteenMinutes
    case oneHour
    case tomorrow
    case nextWeek

    var id: String { title }

    var title: String {
        switch self {
        case .fifteenMinutes:
            return "In 15 minutes"
        case .oneHour:
            return "In 1 hour"
        case .tomorrow:
            return "Tomorrow"
        case .nextWeek:
            return "Next week"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .fifteenMinutes:
            return 15 * 60
        case .oneHour:
            return 60 * 60
        case .tomorrow:
            return 24 * 60 * 60
        case .nextWeek:
            return 7 * 24 * 60 * 60
        }
    }
}
