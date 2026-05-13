import Foundation

enum SettingsSearchSection: String, CaseIterable, Identifiable {
    case editor
    case performance
    case whiteboard
    case storage
    case aiAgents
    case terminal
    case automation

    var id: String { rawValue }
}

struct SettingsSearchCatalog {
    struct Section: Equatable {
        var id: SettingsSearchSection
        var title: String
        var terms: [String]
    }

    static let sections: [Section] = [
        Section(
            id: .editor,
            title: "Editor",
            terms: ["font", "size", "word wrap", "wrap", "column", "guide", "paper", "pep8", "source", "engine", "codemirror", "webview", "prototype"]
        ),
        Section(
            id: .performance,
            title: "Performance",
            terms: ["table", "csv", "tsv", "rows", "columns", "large", "big", "file", "json", "threshold", "chunk"]
        ),
        Section(
            id: .whiteboard,
            title: "Whiteboard",
            terms: ["drawing", "board", "grid", "sticky", "shape", "connector", "arrow", "route", "miro"]
        ),
        Section(
            id: .storage,
            title: "Storage",
            terms: ["data", "root", "icloud", "sync", "cloud", "folder"]
        ),
        Section(
            id: .aiAgents,
            title: "AI Agents",
            terms: [
                "copilot", "codex", "http", "llm", "openai", "anthropic", "gemini",
                "api", "key", "model", "temperature", "task", "companion", "accessibility",
                "screen", "ocr", "selection", "activity", "watch", "timelog", "stats"
            ]
        ),
        Section(
            id: .terminal,
            title: "Terminal",
            terms: ["shell", "zsh", "term", "locale", "utf", "terminal", "pty", "ansi"]
        ),
        Section(
            id: .automation,
            title: "Automation",
            terms: ["local", "bridge", "rpc", "socket", "http", "scribe", "voice", "macro", "meeting", "auto"]
        )
    ]

    static func visibleSections(matching query: String) -> [SettingsSearchSection] {
        let terms = normalizedSearchTerms(query)
        guard !terms.isEmpty else {
            return sections.map(\.id)
        }

        return sections
            .filter { section in
                terms.allSatisfy { term in
                    searchableText(for: section).contains(term)
                }
            }
            .map(\.id)
    }

    static func normalizedSearchTerms(_ query: String) -> [String] {
        query
            .lowercased()
            .replacingOccurrences(of: "[^a-zа-яё0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
    }

    private static func searchableText(for section: Section) -> String {
        ([section.title] + section.terms)
            .joined(separator: " ")
            .lowercased()
    }
}
