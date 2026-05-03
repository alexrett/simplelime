import Foundation

enum BufferKind: String, Codable {
    case scratch
    case file
}

struct EditorBuffer: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var kind: BufferKind
    var filePath: String?
    var text: String
    var language: EditorLanguage
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool
    var selectionRanges: [TextRange]
    var aiSessions: [AIChatSession] = []
    var selectedAIChatSessionID: UUID?

    var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }

    var subtitle: String {
        switch kind {
        case .scratch:
            return "Scratch"
        case .file:
            return filePath ?? "File"
        }
    }

    static func scratch(index: Int) -> EditorBuffer {
        let now = Date()
        return EditorBuffer(
            id: UUID(),
            title: "Scratch \(index)",
            kind: .scratch,
            filePath: nil,
            text: "",
            language: .markdown,
            createdAt: now,
            updatedAt: now,
            isDirty: false,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil
        )
    }
}
