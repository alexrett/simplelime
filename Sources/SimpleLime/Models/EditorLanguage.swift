import Foundation

enum EditorLanguage: String, CaseIterable, Codable, Identifiable {
    case plain
    case markdown
    case swift
    case javascript
    case typescript
    case json
    case yaml
    case html
    case css
    case csv
    case tsv
    case python
    case ruby
    case go
    case rust
    case shell
    case image
    case pdf
    case hex
    case drawing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plain: "Plain Text"
        case .markdown: "Markdown"
        case .swift: "Swift"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .json: "JSON"
        case .yaml: "YAML"
        case .html: "HTML"
        case .css: "CSS"
        case .csv: "CSV"
        case .tsv: "TSV"
        case .python: "Python"
        case .ruby: "Ruby"
        case .go: "Go"
        case .rust: "Rust"
        case .shell: "Shell"
        case .image: "Image"
        case .pdf: "PDF"
        case .hex: "Hex"
        case .drawing: "Drawing"
        }
    }

    var isMarkdown: Bool {
        self == .markdown
    }

    var isDelimitedTable: Bool {
        self == .csv || self == .tsv
    }

    var supportsRenderedPreview: Bool {
        isMarkdown || isDelimitedTable
    }

    var isBinaryPreview: Bool {
        self == .image || self == .pdf || self == .hex
    }

    var supportsTaskScanning: Bool {
        switch self {
        case .image, .pdf, .hex, .drawing, .csv, .tsv, .json:
            return false
        default:
            return true
        }
    }

    var isWhiteboard: Bool {
        self == .drawing
    }

    var usesComplexTextLargeFileThreshold: Bool {
        switch self {
        case .swift, .javascript, .typescript, .json, .yaml, .html, .css, .python, .ruby, .go, .rust, .shell:
            return true
        default:
            return false
        }
    }

    var needsDebouncedSyntaxHighlighting: Bool {
        switch self {
        case .plain, .csv, .tsv, .image, .pdf, .hex, .drawing:
            return false
        case .markdown, .json, .yaml, .swift, .javascript, .typescript, .python, .ruby, .go, .rust, .shell, .html, .css:
            return true
        }
    }

    var supportsStructuredFoldGutter: Bool {
        switch self {
        case .markdown, .json, .yaml:
            return true
        case .plain, .swift, .javascript, .typescript, .python, .ruby, .go, .rust, .shell, .html, .css, .csv, .tsv, .image, .pdf, .hex, .drawing:
            return false
        }
    }

    var tableDelimiter: Character? {
        switch self {
        case .csv:
            return ","
        case .tsv:
            return "\t"
        default:
            return nil
        }
    }

    static func detect(fileName: String?, text: String = "") -> EditorLanguage {
        guard let fileName else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") ? .markdown : .plain
        }

        let lower = fileName.lowercased()
        let ext = (lower as NSString).pathExtension

        switch ext {
        case "md", "markdown", "mdown": return .markdown
        case "swift": return .swift
        case "js", "mjs", "cjs": return .javascript
        case "ts", "tsx": return .typescript
        case "json", "jsonl": return .json
        case "yaml", "yml": return .yaml
        case "html", "htm", "xml": return .html
        case "css", "scss", "sass": return .css
        case "csv": return .csv
        case "tsv", "tab": return .tsv
        case "py": return .python
        case "rb": return .ruby
        case "go": return .go
        case "rs": return .rust
        case "sh", "bash", "zsh", "fish": return .shell
        case "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "webp": return .image
        case "pdf": return .pdf
        case WhiteboardDocument.fileExtension, "whiteboard": return .drawing
        default:
            if ["makefile", "dockerfile", "gemfile", "rakefile"].contains(lower) {
                return .shell
            }
            return .plain
        }
    }
}
