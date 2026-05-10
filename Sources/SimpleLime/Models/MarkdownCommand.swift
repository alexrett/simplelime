import Foundation

enum MarkdownCommand: String, CaseIterable, Identifiable {
    case bold
    case italic
    case inlineCode
    case strikethrough
    case highlight
    case subscriptText = "subscript"
    case superscriptText = "superscript"
    case heading1
    case heading2
    case heading3
    case unorderedList
    case orderedList
    case taskList
    case link
    case image
    case table
    case quote
    case codeFence
    case mathBlock
    case mermaidDiagram

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .inlineCode: "Inline Code"
        case .strikethrough: "Strikethrough"
        case .highlight: "Highlight"
        case .subscriptText: "Subscript"
        case .superscriptText: "Superscript"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .unorderedList: "Bullet List"
        case .orderedList: "Numbered List"
        case .taskList: "Task List"
        case .link: "Link"
        case .image: "Image"
        case .table: "Table"
        case .quote: "Quote"
        case .codeFence: "Code Fence"
        case .mathBlock: "Math Block"
        case .mermaidDiagram: "Mermaid Diagram"
        }
    }
}
