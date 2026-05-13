import Foundation

enum EditorShortcut {
    case showCommandPalette
    case openFolder
    case showFind
    case showReplace
    case showGlobalFind
    case findNext
    case findPrevious
    case selectAllMatches
    case addNextOccurrence
    case addPreviousOccurrence
    case toggleWrapLines
    case showSourceMode
    case showMarkdownPreviewMode
    case showMarkdownWysiwygMode
    case toggleMarkdownPreview
    case toggleMarkdownOutline
    case toggleDocumentCatalog
    case toggleWysiwygMode
    case toggleFocusMode
    case toggleTypewriterMode
    case toggleMiniMap
    case toggleCommentsPanel
    case addComment
    case transform(TextTransform)
    case editorCommand(EditorCommand)
    case markdown(MarkdownCommand)
    case increaseFontSize
    case decreaseFontSize
    case nextTab
    case previousTab
    case toggleAI
    case toggleTerminal
    case escape
}
