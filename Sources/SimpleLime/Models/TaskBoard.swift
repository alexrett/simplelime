import Foundation

enum TaskBoardStatus: String, CaseIterable, Codable, Identifiable {
    case todo
    case inProgress
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
    }

    var markdownTaskMarker: String {
        switch self {
        case .todo: " "
        case .inProgress: ">"
        case .done: "x"
        }
    }

    static func markdownStatus(for marker: String) -> TaskBoardStatus {
        switch marker.lowercased() {
        case "x":
            return .done
        case ">", "/", "-":
            return .inProgress
        default:
            return .todo
        }
    }
}

enum ManualTaskScope: String, CaseIterable, Codable, Identifiable {
    case workspace
    case global

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .global: "Global"
        }
    }

    var systemImage: String {
        switch self {
        case .workspace: "rectangle.3.group"
        case .global: "macwindow"
        }
    }
}

struct ManualTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var status: TaskBoardStatus
    var scope: ManualTaskScope
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case scope
        case createdAt
        case updatedAt
    }

    init(
        id: UUID,
        title: String,
        status: TaskBoardStatus,
        createdAt: Date,
        updatedAt: Date,
        scope: ManualTaskScope = .workspace
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.scope = scope
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(TaskBoardStatus.self, forKey: .status)
        scope = try container.decodeIfPresent(ManualTaskScope.self, forKey: .scope) ?? .workspace
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    static func new(
        title: String,
        status: TaskBoardStatus = .todo,
        scope: ManualTaskScope = .workspace,
        now: Date = Date()
    ) -> ManualTask {
        ManualTask(
            id: UUID(),
            title: title,
            status: status,
            createdAt: now,
            updatedAt: now,
            scope: scope
        )
    }
}

struct MarkdownTaskMatch: Equatable {
    var title: String
    var status: TaskBoardStatus
    var lineNumber: Int
    var lineRange: TextRange
    var markerRange: TextRange
    var updateMode: DetectedTaskUpdateMode = .markdownMarker
}

enum DetectedTaskUpdateMode: String, Equatable {
    case markdownMarker
    case lineToMarkdownChecklist
}

struct DetectedTask: Identifiable, Equatable {
    var bufferID: UUID?
    var bufferTitle: String
    var filePath: String?
    var title: String
    var status: TaskBoardStatus
    var lineNumber: Int
    var lineRange: TextRange
    var markerRange: TextRange
    var updateMode: DetectedTaskUpdateMode = .markdownMarker

    var id: String {
        let source = bufferID?.uuidString ?? filePath ?? bufferTitle
        return "\(source):\(lineRange.location):\(lineNumber)"
    }

    var sourceLabel: String {
        "\(bufferTitle):\(lineNumber)"
    }
}

enum TaskBoardCard: Identifiable, Equatable {
    case manual(ManualTask)
    case detected(DetectedTask)

    var id: String {
        switch self {
        case .manual(let task):
            return "manual:\(task.id.uuidString)"
        case .detected(let task):
            return "detected:\(task.id)"
        }
    }

    var title: String {
        switch self {
        case .manual(let task):
            return task.title
        case .detected(let task):
            return task.title
        }
    }

    var status: TaskBoardStatus {
        switch self {
        case .manual(let task):
            return task.status
        case .detected(let task):
            return task.status
        }
    }
}
