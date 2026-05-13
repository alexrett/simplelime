import Foundation

enum TextTransform: String, CaseIterable, Codable, Identifiable {
    case uppercase
    case lowercase
    case titlecase
    case swapCase
    case reverseSelection
    case sortLines
    case uniqueLines
    case trimTrailingWhitespace
    case duplicateLine
    case joinLines
    case formatJSON
    case minifyJSON
    case formatMarkdownTables

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uppercase: "Uppercase"
        case .lowercase: "Lowercase"
        case .titlecase: "Title Case"
        case .swapCase: "Swap Case"
        case .reverseSelection: "Reverse Selection"
        case .sortLines: "Sort Lines"
        case .uniqueLines: "Unique Lines"
        case .trimTrailingWhitespace: "Trim Trailing Whitespace"
        case .duplicateLine: "Duplicate Line"
        case .joinLines: "Join Lines"
        case .formatJSON: "Format JSON"
        case .minifyJSON: "Minify JSON"
        case .formatMarkdownTables: "Format Markdown Tables"
        }
    }
}
