import Foundation

struct ActionMacro: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var steps: [ActionMacroStep]
    var createdAt: Date
    var updatedAt: Date

    static func custom(title: String, steps: [ActionMacroStep], now: Date = Date()) -> ActionMacro {
        ActionMacro(
            id: "action:\(UUID().uuidString)",
            title: title,
            steps: steps,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct ActionMacroRecording: Equatable {
    var title: String
    var steps: [ActionMacroStep]
    var startedAt: Date

    var isEmpty: Bool {
        steps.isEmpty
    }
}

enum ActionMacroStep: Codable, Equatable {
    case select([TextRange])
    case replaceSelection(String)
    case deleteBackward(Int)
    case deleteForward(Int)
    case transform(TextTransform)
    case markdown(MarkdownCommand)
    case editor(EditorCommand)

    var title: String {
        switch self {
        case .select(let ranges):
            if ranges.count <= 1 {
                let range = ranges.first ?? .zero
                return range.length > 0
                    ? "Select \(range.length) chars"
                    : "Move cursor to \(range.location)"
            }
            return "Select \(ranges.count) ranges"
        case .replaceSelection(let text):
            guard !text.isEmpty else {
                return "Delete selection"
            }
            let preview = text
                .replacingOccurrences(of: "\n", with: "\\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return preview.isEmpty ? "Replace selection" : "Insert \(preview)"
        case .deleteBackward(let count):
            return "Delete \(count) before cursor"
        case .deleteForward(let count):
            return "Delete \(count) after cursor"
        case .transform(let transform):
            return transform.title
        case .markdown(let command):
            return command.title
        case .editor(let command):
            return command.title
        }
    }
}
