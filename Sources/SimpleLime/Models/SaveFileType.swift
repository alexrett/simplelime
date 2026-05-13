import Foundation
import UniformTypeIdentifiers

enum SaveFileType: String, CaseIterable, Identifiable {
    case plain
    case markdown
    case json
    case yaml
    case html
    case css
    case swift
    case javascript
    case typescript
    case csv
    case tsv
    case python
    case ruby
    case go
    case rust
    case shell
    case drawing

    var id: String { rawValue }

    var language: EditorLanguage {
        switch self {
        case .plain: .plain
        case .markdown: .markdown
        case .json: .json
        case .yaml: .yaml
        case .html: .html
        case .css: .css
        case .swift: .swift
        case .javascript: .javascript
        case .typescript: .typescript
        case .csv: .csv
        case .tsv: .tsv
        case .python: .python
        case .ruby: .ruby
        case .go: .go
        case .rust: .rust
        case .shell: .shell
        case .drawing: .drawing
        }
    }

    var fileExtension: String {
        switch self {
        case .plain: "txt"
        case .markdown: "md"
        case .json: "json"
        case .yaml: "yaml"
        case .html: "html"
        case .css: "css"
        case .swift: "swift"
        case .javascript: "js"
        case .typescript: "ts"
        case .csv: "csv"
        case .tsv: "tsv"
        case .python: "py"
        case .ruby: "rb"
        case .go: "go"
        case .rust: "rs"
        case .shell: "sh"
        case .drawing: WhiteboardDocument.fileExtension
        }
    }

    var displayName: String {
        "\(language.displayName) (.\(fileExtension))"
    }

    var contentType: UTType {
        if self == .drawing {
            return UTType(filenameExtension: fileExtension) ?? .json
        }
        return UTType(filenameExtension: fileExtension) ?? .plainText
    }

    static func preferred(for language: EditorLanguage) -> SaveFileType {
        SaveFileType.allCases.first { $0.language == language } ?? .plain
    }
}
