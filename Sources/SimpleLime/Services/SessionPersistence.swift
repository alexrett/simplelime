import Foundation

struct StoredSession: Codable {
    var selectedBufferID: UUID?
    var buffers: [StoredBuffer]
    var selectedWindowGroupID: UUID?
    var windowGroups: [StoredWindowGroup]?
}

struct StoredWindowGroup: Codable {
    var id: UUID
    var selectedBufferID: UUID?
    var buffers: [StoredBuffer]
}

struct StoredBuffer: Codable {
    var id: UUID
    var title: String
    var kind: BufferKind
    var filePath: String?
    var language: EditorLanguage
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool
    var textFileName: String
    var selectionRanges: [TextRange]
    var aiSessions: [AIChatSession]?
    var selectedAIChatSessionID: UUID?
}

final class SessionPersistence {
    private let fileManager: FileManager
    private let rootURL: URL
    private let buffersURL: URL
    private let manifestURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        rootURL = baseURL.appendingPathComponent("SimpleLime", isDirectory: true)
        buffersURL = rootURL.appendingPathComponent("Buffers", isDirectory: true)
        manifestURL = rootURL.appendingPathComponent("session.json", isDirectory: false)
    }

    func load() -> (buffers: [EditorBuffer], selectedID: UUID?) {
        guard let data = try? Data(contentsOf: manifestURL),
              let session = try? JSONDecoder.sessionDecoder.decode(StoredSession.self, from: data) else {
            return ([], nil)
        }

        let buffers = session.buffers.compactMap { stored -> EditorBuffer? in
            let textURL = buffersURL.appendingPathComponent(stored.textFileName, isDirectory: false)
            let text = (try? String(contentsOf: textURL, encoding: .utf8)) ?? ""

            return EditorBuffer(
                id: stored.id,
                title: stored.title,
                kind: stored.kind,
                filePath: stored.filePath,
                text: text,
                language: stored.language,
                createdAt: stored.createdAt,
                updatedAt: stored.updatedAt,
                isDirty: stored.isDirty,
                selectionRanges: stored.selectionRanges.isEmpty ? [.zero] : stored.selectionRanges,
                aiSessions: stored.aiSessions ?? [],
                selectedAIChatSessionID: stored.selectedAIChatSessionID
            )
        }

        return (buffers, session.selectedBufferID)
    }

    func loadWindowGroups() -> [EditorWindowGroupState] {
        guard let data = try? Data(contentsOf: manifestURL),
              let session = try? JSONDecoder.sessionDecoder.decode(StoredSession.self, from: data) else {
            return []
        }

        let storedGroups: [StoredWindowGroup]
        if let windowGroups = session.windowGroups, !windowGroups.isEmpty {
            storedGroups = windowGroups
        } else {
            storedGroups = [
                StoredWindowGroup(
                    id: UUID(),
                    selectedBufferID: session.selectedBufferID,
                    buffers: session.buffers
                )
            ]
        }

        return storedGroups.map { group in
            let buffers = group.buffers.compactMap { stored -> EditorBuffer? in
                let textURL = buffersURL.appendingPathComponent(stored.textFileName, isDirectory: false)
                let text = (try? String(contentsOf: textURL, encoding: .utf8)) ?? ""

                return EditorBuffer(
                    id: stored.id,
                    title: stored.title,
                    kind: stored.kind,
                    filePath: stored.filePath,
                    text: text,
                    language: stored.language,
                    createdAt: stored.createdAt,
                    updatedAt: stored.updatedAt,
                    isDirty: stored.isDirty,
                    selectionRanges: stored.selectionRanges.isEmpty ? [.zero] : stored.selectionRanges,
                    aiSessions: stored.aiSessions ?? [],
                    selectedAIChatSessionID: stored.selectedAIChatSessionID
                )
            }

            return EditorWindowGroupState(
                id: group.id,
                selectedBufferID: group.selectedBufferID,
                buffers: buffers
            )
        }
    }

    func save(buffers: [EditorBuffer], selectedID: UUID?) throws {
        try fileManager.createDirectory(at: buffersURL, withIntermediateDirectories: true)

        var storedBuffers: [StoredBuffer] = []
        let activeFileNames = Set(buffers.map { "\($0.id.uuidString).txt" })

        for buffer in buffers {
            let textFileName = "\(buffer.id.uuidString).txt"
            let textURL = buffersURL.appendingPathComponent(textFileName, isDirectory: false)
            try buffer.text.write(to: textURL, atomically: true, encoding: .utf8)

            storedBuffers.append(
                StoredBuffer(
                    id: buffer.id,
                    title: buffer.title,
                    kind: buffer.kind,
                    filePath: buffer.filePath,
                    language: buffer.language,
                    createdAt: buffer.createdAt,
                    updatedAt: buffer.updatedAt,
                    isDirty: buffer.isDirty,
                    textFileName: textFileName,
                    selectionRanges: buffer.selectionRanges,
                    aiSessions: buffer.aiSessions,
                    selectedAIChatSessionID: buffer.selectedAIChatSessionID
                )
            )
        }

        let staleFiles = (try? fileManager.contentsOfDirectory(atPath: buffersURL.path)) ?? []
        for fileName in staleFiles where !activeFileNames.contains(fileName) {
            try? fileManager.removeItem(at: buffersURL.appendingPathComponent(fileName, isDirectory: false))
        }

        let payload = StoredSession(
            selectedBufferID: selectedID,
            buffers: storedBuffers,
            selectedWindowGroupID: nil,
            windowGroups: nil
        )
        let data = try JSONEncoder.sessionEncoder.encode(payload)
        try data.write(to: manifestURL, options: .atomic)
    }

    func save(windowGroups: [EditorWindowGroupState], selectedGroupID: UUID?) throws {
        try fileManager.createDirectory(at: buffersURL, withIntermediateDirectories: true)

        var storedGroups: [StoredWindowGroup] = []
        var activeFileNames = Set<String>()

        for group in windowGroups {
            var storedBuffers: [StoredBuffer] = []

            for buffer in group.buffers {
                let textFileName = "\(buffer.id.uuidString).txt"
                let textURL = buffersURL.appendingPathComponent(textFileName, isDirectory: false)
                try buffer.text.write(to: textURL, atomically: true, encoding: .utf8)
                activeFileNames.insert(textFileName)

                storedBuffers.append(
                    StoredBuffer(
                        id: buffer.id,
                        title: buffer.title,
                        kind: buffer.kind,
                        filePath: buffer.filePath,
                        language: buffer.language,
                        createdAt: buffer.createdAt,
                        updatedAt: buffer.updatedAt,
                        isDirty: buffer.isDirty,
                        textFileName: textFileName,
                        selectionRanges: buffer.selectionRanges,
                        aiSessions: buffer.aiSessions,
                        selectedAIChatSessionID: buffer.selectedAIChatSessionID
                    )
                )
            }

            storedGroups.append(
                StoredWindowGroup(
                    id: group.id,
                    selectedBufferID: group.selectedBufferID,
                    buffers: storedBuffers
                )
            )
        }

        let staleFiles = (try? fileManager.contentsOfDirectory(atPath: buffersURL.path)) ?? []
        for fileName in staleFiles where !activeFileNames.contains(fileName) {
            try? fileManager.removeItem(at: buffersURL.appendingPathComponent(fileName, isDirectory: false))
        }

        let firstGroup = windowGroups.first
        let payload = StoredSession(
            selectedBufferID: firstGroup?.selectedBufferID,
            buffers: [],
            selectedWindowGroupID: selectedGroupID,
            windowGroups: storedGroups
        )
        let data = try JSONEncoder.sessionEncoder.encode(payload)
        try data.write(to: manifestURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var sessionEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var sessionDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
