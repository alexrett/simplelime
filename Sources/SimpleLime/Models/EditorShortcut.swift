import Foundation

enum EditorShortcut {
    case showFind
    case showReplace
    case showGlobalFind
    case selectAllMatches
    case transform(TextTransform)
    case increaseFontSize
    case decreaseFontSize
    case nextTab
    case previousTab
    case toggleAI
    case escape
}
