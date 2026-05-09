import Foundation

enum TextTransform: String, CaseIterable, Identifiable {
    case uppercase
    case lowercase
    case titlecase
    case sortLines
    case uniqueLines
    case trimTrailingWhitespace
    case duplicateLine
    case joinLines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uppercase: "Uppercase"
        case .lowercase: "Lowercase"
        case .titlecase: "Title Case"
        case .sortLines: "Sort Lines"
        case .uniqueLines: "Unique Lines"
        case .trimTrailingWhitespace: "Trim Trailing Whitespace"
        case .duplicateLine: "Duplicate Line"
        case .joinLines: "Join Lines"
        }
    }
}
