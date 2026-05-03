import Foundation

struct AIBufferFileBridge {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        rootURL = baseURL
            .appendingPathComponent("SimpleLime", isDirectory: true)
            .appendingPathComponent("AgentBuffers", isDirectory: true)
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

    func mimeType(for buffer: EditorBuffer) -> String {
        switch buffer.language {
        case .markdown: "text/markdown"
        case .swift: "text/x-swift"
        case .javascript: "text/javascript"
        case .typescript: "text/typescript"
        case .json: "application/json"
        case .html: "text/html"
        case .css: "text/css"
        case .python: "text/x-python"
        case .ruby: "text/x-ruby"
        case .go: "text/x-go"
        case .rust: "text/x-rust"
        case .shell: "text/x-shellscript"
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
        case .html: return "html"
        case .css: return "css"
        case .python: return "py"
        case .ruby: return "rb"
        case .go: return "go"
        case .rust: return "rs"
        case .shell: return "sh"
        case .plain: return "txt"
        }
    }
}
