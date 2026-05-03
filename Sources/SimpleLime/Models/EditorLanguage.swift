import Foundation

enum EditorLanguage: String, CaseIterable, Codable, Identifiable {
    case plain
    case markdown
    case swift
    case javascript
    case typescript
    case json
    case html
    case css
    case python
    case ruby
    case go
    case rust
    case shell

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plain: "Plain Text"
        case .markdown: "Markdown"
        case .swift: "Swift"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .json: "JSON"
        case .html: "HTML"
        case .css: "CSS"
        case .python: "Python"
        case .ruby: "Ruby"
        case .go: "Go"
        case .rust: "Rust"
        case .shell: "Shell"
        }
    }

    var isMarkdown: Bool {
        self == .markdown
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
        case "html", "htm", "xml": return .html
        case "css", "scss", "sass": return .css
        case "py": return .python
        case "rb": return .ruby
        case "go": return .go
        case "rs": return .rust
        case "sh", "bash", "zsh", "fish": return .shell
        default:
            if ["makefile", "dockerfile", "gemfile", "rakefile"].contains(lower) {
                return .shell
            }
            return .plain
        }
    }
}
