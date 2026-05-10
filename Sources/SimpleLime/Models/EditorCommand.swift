import Foundation

enum EditorCommand {
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
}
