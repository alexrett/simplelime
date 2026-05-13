import Foundation

enum BufferKind: String, Codable {
    case scratch
    case file
}

enum BufferSavePolicy: String, CaseIterable, Codable, Identifiable {
    case normal
    case readOnly
    case temporary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .readOnly: "Read-Only"
        case .temporary: "Temporary"
        }
    }

    var systemImage: String {
        switch self {
        case .normal: "checkmark.circle"
        case .readOnly: "lock"
        case .temporary: "clock"
        }
    }

    var blocksSaving: Bool {
        self != .normal
    }

    func blockedSaveMessage(for title: String) -> String {
        switch self {
        case .normal:
            return ""
        case .readOnly:
            return "\(title) is in read-only mode. Disable read-only mode before saving."
        case .temporary:
            return "\(title) is in temporary mode. Disable temporary mode before saving."
        }
    }
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
    var savePolicy: BufferSavePolicy = .normal
    var isLargeFileMode: Bool = false
    var fileSizeBytes: Int64?
    var largeFilePreviewStartOffsetBytes: Int64?
    var largeFilePreviewByteCount: Int?
    var largeFileSourcePath: String? = nil
    var largeFileSourceStartOffsetBytes: Int64? = nil
    var largeFileSourceByteCount: Int? = nil
    var largeFileSourceFileSizeBytes: Int64? = nil
    var isEncrypted: Bool = false

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
            selectedAIChatSessionID: nil,
            savePolicy: .normal,
            isLargeFileMode: false,
            fileSizeBytes: nil,
            largeFilePreviewStartOffsetBytes: nil,
            largeFilePreviewByteCount: nil,
            isEncrypted: false
        )
    }
}
