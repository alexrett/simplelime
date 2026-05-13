import Foundation

enum EditorCommand: Codable, Equatable {
    case transform(TextTransform)
    case markdown(MarkdownCommand)
    case splitSelectionIntoLines
    case expandSelectionToLine
    case deleteLine
    case moveLineUp
    case moveLineDown
    case indentLines
    case outdentLines
    case toggleComment

    var title: String {
        switch self {
        case .transform(let transform):
            return transform.title
        case .markdown(let command):
            return command.title
        case .splitSelectionIntoLines:
            return "Split Selection Into Lines"
        case .expandSelectionToLine:
            return "Expand Selection To Line"
        case .deleteLine:
            return "Delete Line"
        case .moveLineUp:
            return "Move Line Up"
        case .moveLineDown:
            return "Move Line Down"
        case .indentLines:
            return "Indent Lines"
        case .outdentLines:
            return "Outdent Lines"
        case .toggleComment:
            return "Toggle Comment"
        }
    }
}
