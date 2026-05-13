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
    var savePolicy: BufferSavePolicy?
    var isLargeFileMode: Bool?
    var fileSizeBytes: Int64?
    var largeFileSourcePath: String?
    var largeFileSourceStartOffsetBytes: Int64?
    var largeFileSourceByteCount: Int?
    var largeFileSourceFileSizeBytes: Int64?
    var isEncrypted: Bool?
}

private struct RestoredLargeFileDescriptor {
    var language: EditorLanguage
    var fileSizeBytes: Int64?
    var isDirty: Bool = false
    var savePolicy: BufferSavePolicy = .readOnly
}

final class SessionPersistence {
    private let fileManager: FileManager
    private let rootURL: URL
    private let buffersURL: URL
    private let manifestURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager

        self.rootURL = rootURL ?? Self.defaultRootURL(fileManager: fileManager)
        buffersURL = self.rootURL.appendingPathComponent("Buffers", isDirectory: true)
        manifestURL = self.rootURL.appendingPathComponent("session.json", isDirectory: false)
    }

    static func defaultRootURL(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> URL {
        AppDataStorage.currentRootURL(fileManager: fileManager, defaults: defaults)
    }

    func load() -> (buffers: [EditorBuffer], selectedID: UUID?) {
        guard let data = try? Data(contentsOf: manifestURL),
              let session = try? JSONDecoder.sessionDecoder.decode(StoredSession.self, from: data) else {
            return ([], nil)
        }

        let buffers = session.buffers.compactMap {
            Self.buffer(from: $0, buffersURL: buffersURL, fileManager: fileManager)
        }

        return (buffers, session.selectedBufferID)
    }

    func loadWindowGroups() -> [EditorWindowGroupState] {
        loadWindowSession().groups
    }

    func loadWindowSession() -> (groups: [EditorWindowGroupState], selectedGroupID: UUID?) {
        guard let data = try? Data(contentsOf: manifestURL),
              let session = try? JSONDecoder.sessionDecoder.decode(StoredSession.self, from: data) else {
            return ([], nil)
        }

        return (
            Self.windowGroups(from: session, buffersURL: buffersURL, fileManager: fileManager),
            session.selectedWindowGroupID
        )
    }

    private static func windowGroups(
        from session: StoredSession,
        buffersURL: URL,
        fileManager: FileManager
    ) -> [EditorWindowGroupState] {

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
            let buffers = group.buffers.compactMap { stored in
                Self.buffer(from: stored, buffersURL: buffersURL, fileManager: fileManager)
            }

            return EditorWindowGroupState(
                id: group.id,
                selectedBufferID: group.selectedBufferID,
                buffers: buffers
            )
        }
    }

    private static func buffer(
        from stored: StoredBuffer,
        buffersURL: URL,
        fileManager: FileManager
    ) -> EditorBuffer? {
        let textURL = buffersURL.appendingPathComponent(stored.textFileName, isDirectory: false)
        let largeFileRestore = largeFileRestoreDescriptor(
            for: stored,
            storedTextURL: textURL,
            fileManager: fileManager
        )
        let text = largeFileRestore == nil
            ? ((try? String(contentsOf: textURL, encoding: .utf8)) ?? "")
            : ""

        return EditorBuffer(
            id: stored.id,
            title: stored.title,
            kind: stored.kind,
            filePath: stored.filePath,
            text: text,
            language: largeFileRestore?.language ?? stored.language,
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt,
            isDirty: largeFileRestore?.isDirty ?? stored.isDirty,
            selectionRanges: stored.selectionRanges.isEmpty ? [.zero] : stored.selectionRanges,
            aiSessions: stored.aiSessions ?? [],
            selectedAIChatSessionID: stored.selectedAIChatSessionID,
            savePolicy: largeFileRestore?.savePolicy ?? stored.savePolicy ?? .normal,
            isLargeFileMode: largeFileRestore != nil || (stored.isLargeFileMode ?? false),
            fileSizeBytes: largeFileRestore?.fileSizeBytes ?? stored.fileSizeBytes,
            largeFileSourcePath: stored.largeFileSourcePath,
            largeFileSourceStartOffsetBytes: stored.largeFileSourceStartOffsetBytes,
            largeFileSourceByteCount: stored.largeFileSourceByteCount,
            largeFileSourceFileSizeBytes: stored.largeFileSourceFileSizeBytes,
            isEncrypted: stored.isEncrypted ?? false
        )
    }

    private static func largeFileRestoreDescriptor(
        for stored: StoredBuffer,
        storedTextURL: URL,
        fileManager: FileManager
    ) -> RestoredLargeFileDescriptor? {
        guard stored.kind == .file,
              stored.isEncrypted != true,
              let filePath = stored.filePath else {
            return nil
        }

        if stored.isDirty, Self.hasLargeFileChunkSourceMetadata(stored) {
            return nil
        }

        let fileURL = URL(fileURLWithPath: filePath)
        let language = EditorLanguage.detect(fileName: fileURL.lastPathComponent, text: "")
        let diskSize = fileSizeBytes(at: fileURL, fileManager: fileManager) ?? stored.fileSizeBytes
        guard EditorStore.shouldUseLargeFileMode(fileSizeBytes: diskSize, language: language) else {
            return nil
        }

        return RestoredLargeFileDescriptor(language: language, fileSizeBytes: diskSize)
    }

    private static func fileSizeBytes(at url: URL, fileManager: FileManager) -> Int64? {
        guard fileManager.fileExists(atPath: url.path),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }

        return Int64(size)
    }

    func save(buffers: [EditorBuffer], selectedID: UUID?) throws {
        try fileManager.createDirectory(at: buffersURL, withIntermediateDirectories: true)

        var storedBuffers: [StoredBuffer] = []
        let activeFileNames = Set(buffers.map { "\($0.id.uuidString).txt" })

        for buffer in buffers {
            let textFileName = "\(buffer.id.uuidString).txt"
            let textURL = buffersURL.appendingPathComponent(textFileName, isDirectory: false)
            let metadata = persistedMetadata(for: buffer)
            try metadata.text.write(to: textURL, atomically: true, encoding: .utf8)

            storedBuffers.append(
                StoredBuffer(
                    id: buffer.id,
                    title: buffer.title,
                    kind: buffer.kind,
                    filePath: buffer.filePath,
                    language: metadata.language,
                    createdAt: buffer.createdAt,
                    updatedAt: buffer.updatedAt,
                    isDirty: metadata.isDirty,
                    textFileName: textFileName,
                    selectionRanges: buffer.selectionRanges,
                    aiSessions: buffer.aiSessions,
                    selectedAIChatSessionID: buffer.selectedAIChatSessionID,
                    savePolicy: metadata.savePolicy,
                    isLargeFileMode: metadata.isLargeFileMode,
                    fileSizeBytes: metadata.fileSizeBytes,
                    largeFileSourcePath: buffer.largeFileSourcePath,
                    largeFileSourceStartOffsetBytes: buffer.largeFileSourceStartOffsetBytes,
                    largeFileSourceByteCount: buffer.largeFileSourceByteCount,
                    largeFileSourceFileSizeBytes: buffer.largeFileSourceFileSizeBytes,
                    isEncrypted: buffer.isEncrypted
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
                let metadata = persistedMetadata(for: buffer)
                try metadata.text.write(to: textURL, atomically: true, encoding: .utf8)
                activeFileNames.insert(textFileName)

                storedBuffers.append(
                    StoredBuffer(
                        id: buffer.id,
                        title: buffer.title,
                        kind: buffer.kind,
                        filePath: buffer.filePath,
                        language: metadata.language,
                        createdAt: buffer.createdAt,
                        updatedAt: buffer.updatedAt,
                        isDirty: metadata.isDirty,
                        textFileName: textFileName,
                        selectionRanges: buffer.selectionRanges,
                        aiSessions: buffer.aiSessions,
                        selectedAIChatSessionID: buffer.selectedAIChatSessionID,
                        savePolicy: metadata.savePolicy,
                        isLargeFileMode: metadata.isLargeFileMode,
                        fileSizeBytes: metadata.fileSizeBytes,
                        largeFileSourcePath: buffer.largeFileSourcePath,
                        largeFileSourceStartOffsetBytes: buffer.largeFileSourceStartOffsetBytes,
                        largeFileSourceByteCount: buffer.largeFileSourceByteCount,
                        largeFileSourceFileSizeBytes: buffer.largeFileSourceFileSizeBytes,
                        isEncrypted: buffer.isEncrypted
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

    private func persistedMetadata(
        for buffer: EditorBuffer
    ) -> (
        text: String,
        language: EditorLanguage,
        isDirty: Bool,
        savePolicy: BufferSavePolicy,
        isLargeFileMode: Bool,
        fileSizeBytes: Int64?
    ) {
        if buffer.isEncrypted {
            return (
                "",
                buffer.language,
                buffer.isDirty,
                buffer.savePolicy,
                buffer.isLargeFileMode,
                buffer.fileSizeBytes
            )
        }

        if shouldPersistEditableLargeFileChunk(buffer) {
            return (
                buffer.text,
                buffer.language,
                buffer.isDirty,
                buffer.savePolicy,
                true,
                buffer.fileSizeBytes
            )
        }

        if shouldPersistAsLargeFilePreview(buffer) {
            let language = diskLanguage(for: buffer) ?? buffer.language
            let fileSizeBytes = diskFileSizeBytes(for: buffer) ?? buffer.fileSizeBytes
            return ("", language, false, .readOnly, true, fileSizeBytes)
        }

        return (
            buffer.text,
            buffer.language,
            buffer.isDirty,
            buffer.savePolicy,
            buffer.isLargeFileMode,
            buffer.fileSizeBytes
        )
    }

    private func shouldPersistEditableLargeFileChunk(_ buffer: EditorBuffer) -> Bool {
        buffer.isLargeFileMode &&
            buffer.isDirty &&
            buffer.largeFileSourcePath != nil &&
            buffer.largeFileSourceStartOffsetBytes != nil &&
            buffer.largeFileSourceByteCount != nil &&
            buffer.largeFileSourceFileSizeBytes != nil
    }

    private func shouldPersistAsLargeFilePreview(_ buffer: EditorBuffer) -> Bool {
        guard buffer.kind == .file else { return false }
        if buffer.isLargeFileMode {
            return true
        }
        guard let language = diskLanguage(for: buffer) else { return false }
        return EditorStore.shouldUseLargeFileMode(fileSizeBytes: diskFileSizeBytes(for: buffer), language: language)
    }

    private func diskLanguage(for buffer: EditorBuffer) -> EditorLanguage? {
        guard let filePath = buffer.filePath else { return nil }
        let url = URL(fileURLWithPath: filePath)
        return EditorLanguage.detect(fileName: url.lastPathComponent, text: "")
    }

    private func diskFileSizeBytes(for buffer: EditorBuffer) -> Int64? {
        guard let filePath = buffer.filePath else { return nil }
        let url = URL(fileURLWithPath: filePath)
        return buffer.fileSizeBytes ?? Self.fileSizeBytes(at: url, fileManager: fileManager)
    }

    private static func hasLargeFileChunkSourceMetadata(_ stored: StoredBuffer) -> Bool {
        stored.largeFileSourcePath != nil &&
            stored.largeFileSourceStartOffsetBytes != nil &&
            stored.largeFileSourceByteCount != nil &&
            stored.largeFileSourceFileSizeBytes != nil
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
