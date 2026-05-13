import Foundation

struct AIBufferFileBridge {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager

        rootURL = Self.defaultRootURL(fileManager: fileManager, defaults: defaults)
    }

    func editableURL(for buffer: EditorBuffer) -> URL {
        return rootURL
            .appendingPathComponent(buffer.id.uuidString, isDirectory: true)
            .appendingPathComponent(fileName(for: buffer), isDirectory: false)
            .standardizedFileURL
    }

    func mirror(_ buffer: EditorBuffer) throws {
        let url = editableURL(for: buffer)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try buffer.text.write(to: url, atomically: true, encoding: .utf8)
    }

    func readMirroredText(for buffer: EditorBuffer) -> String? {
        let url = editableURL(for: buffer)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func defaultRootURL(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> URL {
        AppDataStorage.currentRootURL(fileManager: fileManager, defaults: defaults)
            .appendingPathComponent("AgentBuffers", isDirectory: true)
    }

    func mimeType(for buffer: EditorBuffer) -> String {
        switch buffer.language {
        case .markdown: "text/markdown"
        case .swift: "text/x-swift"
        case .javascript: "text/javascript"
        case .typescript: "text/typescript"
        case .json: "application/json"
        case .yaml: "application/x-yaml"
        case .html: "text/html"
        case .css: "text/css"
        case .csv: "text/csv"
        case .tsv: "text/tab-separated-values"
        case .python: "text/x-python"
        case .ruby: "text/x-ruby"
        case .go: "text/x-go"
        case .rust: "text/x-rust"
        case .shell: "text/x-shellscript"
        case .drawing: "application/json"
        case .image: "application/octet-stream"
        case .pdf: "application/pdf"
        case .hex: "application/octet-stream"
        case .plain: "text/plain"
        }
    }

    private func fileName(for buffer: EditorBuffer) -> String {
        "current-buffer.\(fileExtension(for: buffer))"
    }

    private func fileExtension(for buffer: EditorBuffer) -> String {
        if let filePath = buffer.filePath {
            let ext = (filePath as NSString).pathExtension
            if !ext.isEmpty {
                return ext
            }
        }

        switch buffer.language {
        case .markdown: return "md"
        case .swift: return "swift"
        case .javascript: return "js"
        case .typescript: return "ts"
        case .json: return "json"
        case .yaml: return "yaml"
        case .html: return "html"
        case .css: return "css"
        case .csv: return "csv"
        case .tsv: return "tsv"
        case .python: return "py"
        case .ruby: return "rb"
        case .go: return "go"
        case .rust: return "rs"
        case .shell: return "sh"
        case .drawing: return WhiteboardDocument.fileExtension
        case .image: return "bin"
        case .pdf: return "pdf"
        case .hex: return "bin"
        case .plain: return "txt"
        }
    }
}
