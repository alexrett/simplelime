import SwiftUI

struct SourceEditorCallbacks {
    var onShortcut: (EditorShortcut) -> Void
    var onVisibleLineRangeChange: (ClosedRange<Int>) -> Void
    var onToggleFoldAtLine: (Int) -> Void
    var onRegisterEditorCommandHandler: (@escaping (EditorCommand) -> Bool) -> Void

    init(
        onShortcut: @escaping (EditorShortcut) -> Void,
        onVisibleLineRangeChange: @escaping (ClosedRange<Int>) -> Void,
        onToggleFoldAtLine: @escaping (Int) -> Void = { _ in },
        onRegisterEditorCommandHandler: @escaping (@escaping (EditorCommand) -> Bool) -> Void
    ) {
        self.onShortcut = onShortcut
        self.onVisibleLineRangeChange = onVisibleLineRangeChange
        self.onToggleFoldAtLine = onToggleFoldAtLine
        self.onRegisterEditorCommandHandler = onRegisterEditorCommandHandler
    }
}

struct SourceEditorView: View {
    @Binding var text: String
    @Binding var selectionRanges: [TextRange]

    let configuration: SourceEditorConfiguration
    let decorations: SourceEditorDecorations
    let callbacks: SourceEditorCallbacks

    var body: some View {
        switch configuration.engine {
        case .nativeSTTextView:
            CodeEditorView(
                text: $text,
                selectionRanges: $selectionRanges,
                language: configuration.language,
                fontSize: configuration.fontSize,
                wrapsLines: configuration.wrapsLines,
                columnGuide: configuration.columnGuide,
                foldedRanges: configuration.foldedRanges,
                syntaxHighlightingEnabled: configuration.syntaxHighlightingEnabled,
                isEditable: configuration.isEditable,
                focusModeEnabled: configuration.focusModeEnabled,
                typewriterModeEnabled: configuration.typewriterModeEnabled,
                comments: decorations.comments,
                activeCommentID: decorations.activeCommentID,
                collaborators: decorations.collaborators,
                onShortcut: callbacks.onShortcut,
                onVisibleLineRangeChange: callbacks.onVisibleLineRangeChange,
                onToggleFoldAtLine: callbacks.onToggleFoldAtLine,
                onRegisterEditorCommandHandler: callbacks.onRegisterEditorCommandHandler
            )
        case .codeMirrorWebViewPrototype:
            CodeMirrorSourceEditorView(
                text: $text,
                selectionRanges: $selectionRanges,
                configuration: configuration,
                decorations: decorations,
                callbacks: callbacks
            )
        }
    }
}
