import AppKit
import STTextView
import SwiftUI

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectionRanges: [TextRange]

    var language: EditorLanguage
    var fontSize: Double
    var wrapsLines: Bool
    var focusModeEnabled: Bool
    var typewriterModeEnabled: Bool
    var onShortcut: (EditorShortcut) -> Void
    var onVisibleLineRangeChange: (ClosedRange<Int>) -> Void
    var onRegisterEditorCommandHandler: (@escaping (EditorCommand) -> Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = EditorTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true

        guard let textView = scrollView.documentView as? EditorTextView else {
            return scrollView
        }

        textView.textDelegate = context.coordinator
        textView.shortcutHandler = { shortcut in
            context.coordinator.parent.onShortcut(shortcut)
            return true
        }
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.text = text
        textView.currentLanguage = language
        textView.focusModeEnabled = focusModeEnabled
        textView.typewriterModeEnabled = typewriterModeEnabled

        registerCommandHandler(for: textView)
        configure(
            textView: textView,
            in: scrollView,
            wrapsLines: wrapsLines,
            fontSize: CGFloat(fontSize),
            typewriterModeEnabled: typewriterModeEnabled
        )
        applySyntaxHighlighting(to: textView, language: language, fontSize: CGFloat(fontSize))
        applySelection(selectionRanges, to: textView)
        context.coordinator.observeVisibleRange(in: scrollView, textView: textView)
        context.coordinator.publishVisibleLineRange(from: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }

        context.coordinator.parent = self
        context.coordinator.isApplyingExternalUpdate = true
        defer {
            context.coordinator.isApplyingExternalUpdate = false
        }

        if textView.text != text {
            textView.text = text
            textView.needsSyntaxHighlight = true
        }

        textView.shortcutHandler = { shortcut in
            context.coordinator.parent.onShortcut(shortcut)
            return true
        }
        if textView.currentLanguage != language ||
            textView.focusModeEnabled != focusModeEnabled {
            textView.needsSyntaxHighlight = true
        }
        let shouldCenterForTypewriter = !textView.typewriterModeEnabled && typewriterModeEnabled
        textView.currentLanguage = language
        textView.focusModeEnabled = focusModeEnabled
        textView.typewriterModeEnabled = typewriterModeEnabled
        registerCommandHandler(for: textView)
        configure(
            textView: textView,
            in: scrollView,
            wrapsLines: wrapsLines,
            fontSize: CGFloat(fontSize),
            typewriterModeEnabled: typewriterModeEnabled
        )
        applySyntaxHighlighting(to: textView, language: language, fontSize: CGFloat(fontSize))
        applySelection(selectionRanges, to: textView)
        context.coordinator.observeVisibleRange(in: scrollView, textView: textView)
        context.coordinator.publishVisibleLineRange(from: textView)

        if shouldCenterForTypewriter {
            textView.centerSelectionForTypewriterModeIfNeeded(immediate: true)
        }
    }

    private func configure(
        textView: EditorTextView,
        in scrollView: NSScrollView,
        wrapsLines: Bool,
        fontSize: CGFloat,
        typewriterModeEnabled: Bool
    ) {
        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let lineHighlightColor = NSColor.controlAccentColor.withAlphaComponent(0.10)
        let typewriterInset = typewriterModeEnabled
            ? max(160, floor(scrollView.bounds.height * 0.45))
            : 0

        scrollView.hasHorizontalScroller = !wrapsLines
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.contentInsets = NSEdgeInsets(
            top: typewriterInset,
            left: 0,
            bottom: typewriterInset,
            right: 0
        )

        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !wrapsLines
        textView.autoresizingMask = wrapsLines ? [.width] : [.width, .height]
        textView.showsLineNumbers = true
        textView.highlightSelectedLine = true
        textView.selectedLineHighlightColor = lineHighlightColor
        textView.textContainer.lineFragmentPadding = 14
        textView.configuredWrapsLines = wrapsLines

        if textView.configuredFontSize != fontSize {
            textView.configuredFontSize = fontSize
            textView.needsSyntaxHighlight = true
        }

        if let gutterView = textView.gutterView {
            gutterView.font = baseFont
            gutterView.textColor = .tertiaryLabelColor
            gutterView.selectedLineTextColor = .secondaryLabelColor
            gutterView.selectedLineHighlightColor = lineHighlightColor
        }

        textView.needsLayout = true
        textView.needsDisplay = true
    }

    private func applySelection(_ ranges: [TextRange], to textView: EditorTextView) {
        let normalized = textView.normalizedRanges((ranges.isEmpty ? [.zero] : ranges).map(\.nsRange))
        let targetRanges = normalized.isEmpty ? [NSRange(location: 0, length: 0)] : normalized

        guard textView.editorSelectionRanges != targetRanges else { return }
        textView.setEditorSelectionRanges(targetRanges, scrollToLast: true)
    }

    private func registerCommandHandler(for textView: EditorTextView) {
        onRegisterEditorCommandHandler { [weak textView] command in
            textView?.performEditorCommand(command) ?? false
        }
    }

    private func applySyntaxHighlighting(to textView: EditorTextView, language: EditorLanguage, fontSize: CGFloat) {
        guard textView.needsSyntaxHighlight ||
            textView.highlightedLanguage != language ||
            textView.highlightedFontSize != fontSize else {
            return
        }

        let selectionRanges = textView.editorSelectionRanges
        SyntaxHighlighter.apply(to: textView, language: language, fontSize: fontSize)
        textView.needsSyntaxHighlight = false
        textView.highlightedLanguage = language
        textView.highlightedFontSize = fontSize

        if selectionRanges.count > 1, textView.editorSelectionRanges != selectionRanges {
            textView.setEditorSelectionRanges(selectionRanges)
        }

        textView.updateFocusModeDimming()
    }

    final class Coordinator: NSObject, STTextViewDelegate {
        var parent: CodeEditorView
        var isApplyingExternalUpdate = false
        private weak var observedTextView: EditorTextView?
        private weak var observedContentView: NSClipView?
        private var lastVisibleLineRange: ClosedRange<Int>?

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        deinit {
            if let observedContentView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedContentView
                )
            }
        }

        func observeVisibleRange(in scrollView: NSScrollView, textView: EditorTextView) {
            observedTextView = textView
            guard observedContentView !== scrollView.contentView else { return }

            if let observedContentView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedContentView
                )
            }

            observedContentView = scrollView.contentView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(visibleBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func publishVisibleLineRange(from textView: EditorTextView) {
            let visibleLineRange = textView.visibleSourceLineRange()
            guard lastVisibleLineRange != visibleLineRange else { return }

            lastVisibleLineRange = visibleLineRange
            DispatchQueue.main.async { [weak self] in
                self?.parent.onVisibleLineRangeChange(visibleLineRange)
            }
        }

        @objc private func visibleBoundsDidChange(_ notification: Notification) {
            guard let observedTextView else { return }
            publishVisibleLineRange(from: observedTextView)
        }

        func textViewDidChangeText(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? EditorTextView else {
                return
            }

            parent.text = textView.text ?? ""
            parent.selectionRanges = textView.editorSelectionRanges.map(TextRange.init)
            textView.needsSyntaxHighlight = true
            parent.applySyntaxHighlighting(to: textView, language: parent.language, fontSize: CGFloat(parent.fontSize))
            textView.centerSelectionForTypewriterModeIfNeeded()
            publishVisibleLineRange(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? EditorTextView else {
                return
            }

            parent.selectionRanges = textView.editorSelectionRanges.map(TextRange.init)
            textView.updateFocusModeDimming()
            textView.centerSelectionForTypewriterModeIfNeeded()
            publishVisibleLineRange(from: textView)
        }
    }
}

final class EditorTextView: STTextView {
    var shortcutHandler: ((EditorShortcut) -> Bool)?
    var needsSyntaxHighlight = true
    var highlightedLanguage: EditorLanguage?
    var highlightedFontSize: CGFloat?
    var configuredWrapsLines: Bool?
    var configuredFontSize: CGFloat?
    var currentLanguage: EditorLanguage = .plain
    var focusModeEnabled = false
    var typewriterModeEnabled = false

    private var columnDragState: ColumnDragState?

    var editorSelectionRanges: [NSRange] {
        textLayoutManager.textSelections
            .filter { !$0.isTransient }
            .flatMap(\.textRanges)
            .compactMap { NSRange($0, in: textContentManager) }
            .map(normalizedRange)
            .sorted { first, second in
                if first.location == second.location {
                    return first.length < second.length
                }
                return first.location < second.location
            }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    func setEditorSelectionRanges(_ ranges: [NSRange], scrollToLast: Bool = false) {
        let normalized = normalizedRanges(ranges)
        let safeRanges = normalized.isEmpty ? [NSRange(location: 0, length: 0)] : normalized
        let selections = safeRanges.compactMap { range -> NSTextSelection? in
            guard let textRange = NSTextRange(range, in: textContentManager) else {
                return nil
            }

            return NSTextSelection(range: textRange, affinity: .downstream, granularity: .character)
        }

        guard !selections.isEmpty else { return }
        textLayoutManager.textSelections = selections
        needsLayout = true
        needsDisplay = true

        if scrollToLast, let last = safeRanges.last {
            scrollRangeToVisible(last)
        }
    }

    func visibleSourceLineRange() -> ClosedRange<Int> {
        let nsText = editorNSString
        let ranges = lineRanges
        guard nsText.length > 0 else { return 1...1 }

        let visibleRect = self.visibleRect
        guard visibleRect.height > 0 else {
            let line = (lineInfo(for: editorSelectionRanges.last?.location ?? 0)?.index ?? 0) + 1
            return line...line
        }

        let baseLineHeight: CGFloat = ceil(font.ascender - font.descender + font.leading)
        let lineHeight: CGFloat = Swift.max(1, baseLineHeight)
        let textTop: CGFloat = Swift.max(0, visibleRect.minY)
        let startLine = Swift.min(
            Swift.max(1, Int((textTop / lineHeight).rounded(.down)) + 1),
            ranges.count
        )
        let visibleLineCount = Swift.max(1, Int((visibleRect.height / lineHeight).rounded(.up)) + 1)
        let endLine = Swift.min(ranges.count, startLine + visibleLineCount - 1)

        return min(startLine, endLine)...max(startLine, endLine)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control) else {
            return super.performKeyEquivalent(with: event)
        }

        let shortcut: EditorShortcut?
        switch event.keyCode {
        case 18 where flags.contains(.option):
            shortcut = .showSourceMode
        case 19 where flags.contains(.option):
            shortcut = .showMarkdownPreviewMode
        case 20 where flags.contains(.option):
            shortcut = .showMarkdownWysiwygMode
        case 21 where flags.contains(.option):
            shortcut = .toggleMiniMap
        case 35 where flags.contains(.shift):
            shortcut = .showCommandPalette
        case 31 where flags.contains(.shift):
            shortcut = .openFolder
        case 35 where flags.contains(.option):
            shortcut = .toggleMarkdownPreview
        case 31 where flags.contains(.option):
            shortcut = .toggleMarkdownOutline
        case 14 where flags.contains(.option):
            shortcut = .toggleWysiwygMode
        case 3 where flags.contains(.option):
            shortcut = .toggleFocusMode
        case 17 where flags.contains(.option) && !flags.contains(.shift):
            shortcut = .toggleTypewriterMode
        case 34 where flags.contains(.shift):
            shortcut = .toggleAI
        case 3 where flags.contains(.shift):
            shortcut = .showGlobalFind
        case 3:
            shortcut = .showFind
        case 15:
            shortcut = .showReplace
        case 2 where flags.contains(.option):
            shortcut = .toggleDocumentCatalog
        case 2 where flags.contains(.shift):
            shortcut = .transform(.duplicateLine)
        case 2:
            shortcut = .addNextOccurrence
        case 11:
            shortcut = .markdown(.bold)
        case 34:
            shortcut = .markdown(.italic)
        case 37 where flags.contains(.shift):
            shortcut = .editorCommand(.splitSelectionIntoLines)
        case 37 where flags.contains(.option):
            shortcut = .selectAllMatches
        case 37:
            shortcut = .editorCommand(.expandSelectionToLine)
        case 5 where flags.contains(.option):
            shortcut = flags.contains(.shift) ? .addPreviousOccurrence : .addNextOccurrence
        case 5 where flags.contains(.shift):
            shortcut = .findPrevious
        case 5:
            shortcut = .findNext
        case 6 where flags.contains(.option):
            shortcut = .toggleWrapLines
        case 30:
            shortcut = .editorCommand(.indentLines)
        case 33:
            shortcut = .editorCommand(.outdentLines)
        case 44:
            shortcut = .editorCommand(.toggleComment)
        case 32 where flags.contains(.option) && flags.contains(.shift):
            shortcut = .transform(.uniqueLines)
        case 32 where flags.contains(.shift):
            shortcut = .transform(.uppercase)
        case 32 where flags.contains(.option):
            shortcut = .transform(.lowercase)
        case 17 where flags.contains(.option) && flags.contains(.shift):
            shortcut = .transform(.titlecase)
        case 1 where flags.contains(.option):
            shortcut = .transform(.sortLines)
        case 13 where flags.contains(.option):
            shortcut = .transform(.trimTrailingWhitespace)
        case 38:
            shortcut = .transform(.joinLines)
        case 24, 69:
            shortcut = .increaseFontSize
        case 27, 78:
            shortcut = .decreaseFontSize
        default:
            shortcut = nil
        }

        if let shortcut, shortcutHandler?(shortcut) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command), flags.contains(.option), !flags.contains(.control) {
            switch event.keyCode {
            case 126:
                if shortcutHandler?(.editorCommand(.moveLineUp)) == true { return }
            case 125:
                if shortcutHandler?(.editorCommand(.moveLineDown)) == true { return }
            default:
                break
            }
        }

        if flags.contains(.option), !flags.contains(.command), !flags.contains(.control), !flags.contains(.shift) {
            switch event.keyCode {
            case 126:
                if addVerticalCursor(direction: -1) { return }
            case 125:
                if addVerticalCursor(direction: 1) { return }
            default:
                break
            }
        }

        if event.keyCode == 48, flags.contains(.control), !flags.contains(.command), !flags.contains(.option) {
            let shortcut: EditorShortcut = flags.contains(.shift) ? .previousTab : .nextTab
            if shortcutHandler?(shortcut) == true {
                return
            }
        }

        if event.keyCode == 53, shortcutHandler?(.escape) == true {
            return
        }

        super.keyDown(with: event)
    }

    override func insertText(_ insertString: Any) {
        if insertSmartText(insertString, replacementRange: .notFound) {
            return
        }

        if insertTextAcrossSelections(insertString, replacementRange: .notFound) {
            return
        }

        super.insertText(insertString)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if insertSmartText(string, replacementRange: replacementRange) {
            return
        }

        if insertTextAcrossSelections(string, replacementRange: replacementRange) {
            return
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    override func insertNewline(_ sender: Any?) {
        if continueMarkdownLineAfterReturn() {
            return
        }

        super.insertNewline(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        if deleteSurroundingPair() {
            return
        }

        if deleteBackwardAcrossSelections() {
            return
        }

        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        if deleteForwardAcrossSelections() {
            return
        }

        super.deleteForward(sender)
    }

    override func mouseDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isColumnCursorMouseModifier(flags),
              let anchorLocation = characterLocation(for: event) else {
            super.mouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        trackColumnSelection(from: event, anchorLocation: anchorLocation)
    }

    func performEditorCommand(_ command: EditorCommand) -> Bool {
        switch command {
        case .transform(let transform):
            return performTextTransform(transform)
        case .markdown(let command):
            return performMarkdownCommand(command)
        case .splitSelectionIntoLines:
            return splitSelectionIntoLines()
        case .expandSelectionToLine:
            return expandSelectionToLine()
        case .deleteLine:
            return deleteSelectedLinesOrCurrentLine()
        case .moveLineUp:
            return moveSelectedLines(direction: -1)
        case .moveLineDown:
            return moveSelectedLines(direction: 1)
        case .indentLines:
            return indentSelectedLines()
        case .outdentLines:
            return outdentSelectedLines()
        case .toggleComment:
            return toggleLineComments()
        }
    }

    private func performTextTransform(_ transform: TextTransform) -> Bool {
        switch transform {
        case .uppercase:
            return replaceTargetText { $0.uppercased() }
        case .lowercase:
            return replaceTargetText { $0.lowercased() }
        case .titlecase:
            return replaceTargetText { $0.capitalized }
        case .swapCase:
            return replaceTargetText { $0.swappingCase() }
        case .reverseSelection:
            return replaceTargetText { String($0.reversed()) }
        case .sortLines:
            return replaceTargetLines { text in
                preserveTrailingNewline(text) { lines in
                    lines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                }
            }
        case .uniqueLines:
            return replaceTargetLines { text in
                preserveTrailingNewline(text) { lines in
                    var seen = Set<String>()
                    return lines.filter { seen.insert($0).inserted }
                }
            }
        case .trimTrailingWhitespace:
            return replaceTargetLines { text in
                text.components(separatedBy: .newlines)
                    .map { $0.trimmingTrailingWhitespace() }
                    .joined(separator: "\n")
            }
        case .duplicateLine:
            return duplicateSelectedTextOrCurrentLine()
        case .joinLines:
            return replaceTargetLines { text in
                text.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
        }
    }

    private func replaceTargetText(_ transform: (String) -> String) -> Bool {
        let nsText = editorNSString
        let ranges = nonEmptySelectedRanges()
        let targetRanges = ranges.isEmpty ? [NSRange(location: 0, length: nsText.length)] : ranges
        let replacements = targetRanges.map { transform(nsText.substring(with: $0)) }
        return replace(ranges: targetRanges, replacements: replacements)
    }

    private func replaceTargetLines(_ transform: (String) -> String) -> Bool {
        let nsText = editorNSString
        let ranges = nonEmptySelectedRanges()
        let targetRanges = ranges.isEmpty
            ? [NSRange(location: 0, length: nsText.length)]
            : mergedLineRanges(for: ranges)
        let replacements = targetRanges.map { transform(nsText.substring(with: $0)) }
        return replace(ranges: targetRanges, replacements: replacements)
    }

    private func duplicateSelectedTextOrCurrentLine() -> Bool {
        let nsText = editorNSString
        let ranges = nonEmptySelectedRanges()

        if !ranges.isEmpty {
            let replacements = ranges.map { range in
                let selectedText = nsText.substring(with: range)
                return "\(selectedText)\(selectedText)"
            }
            return replace(ranges: ranges, replacements: replacements)
        }

        let cursor = editorSelectionRanges.last ?? NSRange(location: 0, length: 0)
        let cursorLocation = min(cursor.location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let line = nsText.substring(with: lineRange)
        let insertion = line.hasSuffix("\n") ? line : "\n\(line)"
        return replace(
            ranges: [NSRange(location: lineRange.location + lineRange.length, length: 0)],
            replacements: [insertion]
        )
    }

    private func performMarkdownCommand(_ command: MarkdownCommand) -> Bool {
        switch command {
        case .bold:
            return wrapSelections(left: "**", right: "**")
        case .italic:
            return wrapSelections(left: "*", right: "*")
        case .inlineCode:
            return wrapSelections(left: "`", right: "`")
        case .strikethrough:
            return wrapSelections(left: "~~", right: "~~")
        case .highlight:
            return wrapSelections(left: "==", right: "==")
        case .subscriptText:
            return wrapSelections(left: "~", right: "~")
        case .superscriptText:
            return wrapSelections(left: "^", right: "^")
        case .heading1:
            return transformTargetLines { lines in
                lines.map { applyHeading(level: 1, to: $0) }
            }
        case .heading2:
            return transformTargetLines { lines in
                lines.map { applyHeading(level: 2, to: $0) }
            }
        case .heading3:
            return transformTargetLines { lines in
                lines.map { applyHeading(level: 3, to: $0) }
            }
        case .unorderedList:
            return transformTargetLines { lines in
                lines.map { toggleLinePrefix("- ", in: $0, matching: #"^[-*+]\s+"#) }
            }
        case .orderedList:
            return transformTargetLines { lines in
                lines.enumerated().map { index, line in
                    toggleLinePrefix("\(index + 1). ", in: line, matching: #"^\d+[.)]\s+"#)
                }
            }
        case .taskList:
            return transformTargetLines { lines in
                lines.map { toggleLinePrefix("- [ ] ", in: $0, matching: #"^[-*+]\s+\[[ xX]\]\s+"#) }
            }
        case .link:
            return insertMarkdownLink()
        case .image:
            return insertMarkdownSnippet("![image](image.png)", selectOffset: 9, selectLength: 9)
        case .table:
            return insertMarkdownSnippet("| Column 1 | Column 2 |\n| --- | --- |\n|  |  |", selectOffset: 2, selectLength: 8)
        case .quote:
            return transformTargetLines { lines in
                lines.map { toggleLinePrefix("> ", in: $0, matching: #"^>\s?"#) }
            }
        case .codeFence:
            return insertCodeFence()
        case .mathBlock:
            return insertMarkdownSnippet("$$\nx = y\n$$", selectOffset: 3, selectLength: 5)
        case .mermaidDiagram:
            return insertMarkdownSnippet("```mermaid\ngraph TD\n  A-->B\n```", selectOffset: 11, selectLength: 16)
        }
    }

    private func insertMarkdownLink() -> Bool {
        let nsText = editorNSString
        let ranges = editorSelectionRanges.isEmpty
            ? [NSRange(location: 0, length: 0)]
            : editorSelectionRanges.map(normalizedRange)

        let edits = ranges.map { range -> TextEdit in
            let selectedText = nsText.substring(with: range)
            let text = selectedText.isEmpty ? "link" : selectedText
            return TextEdit(range: range, replacement: "[\(text)](https://example.com)")
        }

        var delta = 0
        let selections = zip(ranges, edits).map { range, edit in
            let selectedText = nsText.substring(with: range)
            let linkTextLength = selectedText.isEmpty ? "link".utf16.count : selectedText.utf16.count
            let location = edit.range.location + delta + 1
            delta += edit.replacement.utf16.count - edit.range.length
            return NSRange(location: location, length: linkTextLength)
        }

        return apply(edits: edits, newSelections: selections)
    }

    private func insertMarkdownSnippet(_ snippet: String, selectOffset: Int, selectLength: Int) -> Bool {
        let nsText = editorNSString
        let range = normalizedRange(editorSelectionRanges.last ?? NSRange(location: 0, length: 0))
        let location = min(range.location, nsText.length)
        let prefix = needsLeadingBlankLine(before: location, in: nsText) ? "\n\n" : ""
        let suffix = needsTrailingBlankLine(after: location + range.length, in: nsText) ? "\n\n" : ""
        let insertion = "\(prefix)\(snippet)\(suffix)"
        return apply(
            edits: [TextEdit(range: range, replacement: insertion)],
            newSelections: [NSRange(location: location + prefix.utf16.count + selectOffset, length: selectLength)]
        )
    }

    private func needsLeadingBlankLine(before location: Int, in text: NSString) -> Bool {
        guard location > 0 else { return false }
        let prefix = text.substring(to: min(location, text.length))
        return !prefix.hasSuffix("\n\n")
    }

    private func needsTrailingBlankLine(after location: Int, in text: NSString) -> Bool {
        guard location < text.length else { return false }
        let suffix = text.substring(from: max(0, location))
        return !suffix.hasPrefix("\n\n")
    }

    private func wrapSelections(left: String, right: String) -> Bool {
        let targetRanges = editorSelectionRanges
        guard !targetRanges.isEmpty else { return false }

        let nsText = editorNSString
        let edits = targetRanges.map { range in
            let selectedText = nsText.substring(with: normalizedRange(range))
            return TextEdit(range: range, replacement: "\(left)\(selectedText)\(right)")
        }

        var delta = 0
        let newSelections = edits.map { edit in
            let selection = NSRange(
                location: edit.range.location + delta + left.utf16.count,
                length: edit.range.length
            )
            delta += edit.replacement.utf16.count - edit.range.length
            return selection
        }

        return apply(edits: edits, newSelections: newSelections)
    }

    private func insertCodeFence() -> Bool {
        let nsText = editorNSString
        let selectedRanges = nonEmptySelectedRanges()

        if selectedRanges.isEmpty {
            let cursor = editorSelectionRanges.last ?? NSRange(location: 0, length: 0)
            let insertion = "```\n\n```"
            return apply(
                edits: [TextEdit(range: NSRange(location: min(cursor.location, nsText.length), length: 0), replacement: insertion)],
                newSelections: [NSRange(location: min(cursor.location, nsText.length) + 4, length: 0)]
            )
        }

        let targetRanges = mergedLineRanges(for: selectedRanges)
        let edits = targetRanges.map { range -> TextEdit in
            let text = nsText.substring(with: range)
            return TextEdit(range: range, replacement: "```\n\(text.hasSuffix("\n") ? text : "\(text)\n")```")
        }

        var delta = 0
        let selections = edits.map { edit in
            let selection = NSRange(location: edit.range.location + delta + 4, length: edit.range.length)
            delta += edit.replacement.utf16.count - edit.range.length
            return selection
        }

        return apply(edits: edits, newSelections: selections)
    }

    private func transformTargetLines(_ transform: ([String]) -> [String]) -> Bool {
        let nsText = editorNSString
        let ranges = nonEmptySelectedRanges()
        let targetRanges = ranges.isEmpty
            ? [nsText.lineRange(for: NSRange(location: min((editorSelectionRanges.last ?? NSRange(location: 0, length: 0)).location, nsText.length), length: 0))]
            : mergedLineRanges(for: ranges)
        let replacements = targetRanges.map { range in
            preserveTrailingNewline(nsText.substring(with: range), transform: transform)
        }

        return replace(ranges: targetRanges, replacements: replacements)
    }

    private func applyHeading(level: Int, to line: String) -> String {
        let (indent, body) = splitIndent(line)
        guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
        let cleaned = removePrefix(in: body, matching: #"^#{1,6}\s+"#)
        return "\(indent)\(String(repeating: "#", count: level)) \(cleaned)"
    }

    private func toggleLinePrefix(_ prefix: String, in line: String, matching pattern: String) -> String {
        let (indent, body) = splitIndent(line)
        guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { return line }

        let cleaned = removePrefix(in: body, matching: pattern)
        if cleaned != body {
            return "\(indent)\(cleaned)"
        }

        return "\(indent)\(prefix)\(body)"
    }

    private func splitIndent(_ line: String) -> (String, String) {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        return (String(indent), String(line.dropFirst(indent.count)))
    }

    private func removePrefix(in body: String, matching pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return body }

        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, range: fullRange),
              match.range.location == 0 else {
            return body
        }

        return nsBody.substring(from: match.range.length)
    }

    private func splitSelectionIntoLines() -> Bool {
        let ranges = nonEmptySelectedRanges()
        guard !ranges.isEmpty else { return expandSelectionToLine() }

        let nsText = editorNSString
        let splitRanges = ranges.flatMap { range in
            lineContentRanges(intersecting: range, in: nsText)
        }

        guard !splitRanges.isEmpty else { return false }
        setEditorSelectionRanges(splitRanges, scrollToLast: true)
        return true
    }

    private func expandSelectionToLine() -> Bool {
        let nsText = editorNSString
        let ranges = editorSelectionRanges.isEmpty ? [NSRange(location: 0, length: 0)] : editorSelectionRanges
        let lineRanges = normalizedRanges(ranges.map { range in
            nsText.lineRange(for: NSRange(location: min(range.location, nsText.length), length: max(range.length, 0)))
        })

        setEditorSelectionRanges(lineRanges, scrollToLast: true)
        return true
    }

    private func deleteSelectedLinesOrCurrentLine() -> Bool {
        let nsText = editorNSString
        let ranges = nonEmptySelectedRanges()
        let targetRanges = ranges.isEmpty
            ? [nsText.lineRange(for: NSRange(location: min((editorSelectionRanges.last ?? NSRange(location: 0, length: 0)).location, nsText.length), length: 0))]
            : mergedLineRanges(for: ranges)
        guard !targetRanges.isEmpty else { return false }

        let selectionLocation = targetRanges.first?.location ?? 0
        let edits = targetRanges.map { TextEdit(range: $0, replacement: "") }
        return apply(edits: edits, newSelections: [NSRange(location: selectionLocation, length: 0)])
    }

    private func moveSelectedLines(direction: Int) -> Bool {
        let nsText = editorNSString
        guard nsText.length > 0 else { return false }

        let ranges = nonEmptySelectedRanges()
        let cursor = editorSelectionRanges.last ?? NSRange(location: 0, length: 0)
        let targetRange = ranges.isEmpty
            ? nsText.lineRange(for: NSRange(location: min(cursor.location, nsText.length), length: 0))
            : mergedLineRanges(for: ranges).reduce(nil) { result, range -> NSRange? in
                guard let result else { return range }
                let end = max(result.location + result.length, range.location + range.length)
                return NSRange(location: min(result.location, range.location), length: end - min(result.location, range.location))
            } ?? NSRange(location: 0, length: 0)

        if direction < 0 {
            guard targetRange.location > 0 else { return false }
            let previousLine = nsText.lineRange(for: NSRange(location: max(0, targetRange.location - 1), length: 0))
            let targetText = nsText.substring(with: targetRange)
            let previousText = nsText.substring(with: previousLine)
            let replacementRange = NSRange(location: previousLine.location, length: previousLine.length + targetRange.length)
            return apply(
                edits: [TextEdit(range: replacementRange, replacement: swapAdjacentLineTexts(previousText, targetText))],
                newSelections: [NSRange(location: previousLine.location, length: targetRange.length)]
            )
        }

        let targetEnd = targetRange.location + targetRange.length
        guard targetEnd < nsText.length else { return false }

        let nextLine = nsText.lineRange(for: NSRange(location: targetEnd, length: 0))
        let targetText = nsText.substring(with: targetRange)
        let nextText = nsText.substring(with: nextLine)
        let replacementRange = NSRange(location: targetRange.location, length: targetRange.length + nextLine.length)
        return apply(
            edits: [TextEdit(range: replacementRange, replacement: swapAdjacentLineTexts(targetText, nextText))],
            newSelections: [
                NSRange(
                    location: targetRange.location + firstLineOffsetAfterSwap(first: targetText, second: nextText),
                    length: firstLineLengthAfterSwap(first: targetText, second: nextText)
                )
            ]
        )
    }

    private func swapAdjacentLineTexts(_ first: String, _ second: String) -> String {
        if trailingLineBreak(in: second) != nil {
            return "\(second)\(first)"
        }

        if let firstBreak = trailingLineBreak(in: first) {
            return "\(second)\(firstBreak)\(removingTrailingLineBreak(from: first))"
        }

        return "\(second)\n\(first)"
    }

    private func firstLineOffsetAfterSwap(first: String, second: String) -> Int {
        if trailingLineBreak(in: second) != nil {
            return second.utf16.count
        }

        if let firstBreak = trailingLineBreak(in: first) {
            return second.utf16.count + firstBreak.utf16.count
        }

        return second.utf16.count + 1
    }

    private func firstLineLengthAfterSwap(first: String, second: String) -> Int {
        if trailingLineBreak(in: second) != nil {
            return first.utf16.count
        }

        if trailingLineBreak(in: first) != nil {
            return removingTrailingLineBreak(from: first).utf16.count
        }

        return first.utf16.count
    }

    private func trailingLineBreak(in text: String) -> String? {
        if text.hasSuffix("\r\n") { return "\r\n" }
        if text.hasSuffix("\n") { return "\n" }
        if text.hasSuffix("\r") { return "\r" }
        return nil
    }

    private func removingTrailingLineBreak(from text: String) -> String {
        if text.hasSuffix("\r\n") { return String(text.dropLast(2)) }
        if text.hasSuffix("\n") || text.hasSuffix("\r") { return String(text.dropLast()) }
        return text
    }

    private func indentSelectedLines() -> Bool {
        transformTargetLines { lines in
            lines.map { line in
                line.isEmpty ? line : "\t\(line)"
            }
        }
    }

    private func outdentSelectedLines() -> Bool {
        transformTargetLines { lines in
            lines.map { line in
                if line.hasPrefix("\t") {
                    return String(line.dropFirst())
                }
                if line.hasPrefix("    ") {
                    return String(line.dropFirst(4))
                }
                if line.hasPrefix("  ") {
                    return String(line.dropFirst(2))
                }
                if line.hasPrefix(" ") {
                    return String(line.dropFirst())
                }
                return line
            }
        }
    }

    private func toggleLineComments() -> Bool {
        guard let prefix = lineCommentPrefix else { return false }

        return transformTargetLines { lines in
            let meaningfulLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let shouldUncomment = !meaningfulLines.isEmpty && meaningfulLines.allSatisfy { line in
                let (_, body) = splitIndent(line)
                return body.hasPrefix(prefix)
            }

            return lines.map { line in
                let (indent, body) = splitIndent(line)
                guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { return line }

                if shouldUncomment, body.hasPrefix(prefix) {
                    var uncommented = String(body.dropFirst(prefix.count))
                    if uncommented.hasPrefix(" ") {
                        uncommented.removeFirst()
                    }
                    return "\(indent)\(uncommented)"
                }

                return "\(indent)\(prefix) \(body)"
            }
        }
    }

    private var lineCommentPrefix: String? {
        switch currentLanguage {
        case .swift, .javascript, .typescript, .go, .rust:
            return "//"
        case .python, .ruby, .shell:
            return "#"
        case .plain, .markdown, .json, .html, .css:
            return nil
        }
    }

    private func lineContentRanges(intersecting range: NSRange, in nsText: NSString) -> [NSRange] {
        var output: [NSRange] = []
        var location = range.location
        let end = range.location + range.length

        while location < end {
            let lineRange = nsText.lineRange(for: NSRange(location: min(location, nsText.length), length: 0))
            let contentRange = contentRange(for: lineRange)
            let start = max(contentRange.location, range.location)
            let finish = min(contentRange.location + contentRange.length, end)
            output.append(NSRange(location: start, length: max(0, finish - start)))

            let nextLocation = lineRange.location + max(lineRange.length, 1)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return output
    }

    private func replace(ranges: [NSRange], replacements: [String]) -> Bool {
        guard ranges.count == replacements.count, !ranges.isEmpty else { return false }
        let edits = zip(ranges, replacements).map { TextEdit(range: $0.0, replacement: $0.1) }
        return apply(edits: edits, selectionMode: .selectReplacement)
    }

    private func insertTextAcrossSelections(_ insertString: Any, replacementRange: NSRange) -> Bool {
        guard let replacement = plainText(from: insertString) else { return false }
        let targetRanges = rangesForEditing(replacementRange: replacementRange)
        guard targetRanges.count > 1 else { return false }

        let edits = targetRanges.map { TextEdit(range: $0, replacement: replacement) }
        return apply(edits: edits, selectionMode: .cursorAfterReplacement)
    }

    private func deleteBackwardAcrossSelections() -> Bool {
        let ranges = editorSelectionRanges
        guard ranges.count > 1 else { return false }

        let nsText = editorNSString
        let edits = ranges.compactMap { range -> TextEdit? in
            let safeRange = normalizedRange(range)
            if safeRange.length > 0 {
                return TextEdit(range: safeRange, replacement: "")
            }

            guard safeRange.location > 0 else { return nil }
            let deleteRange = nsText.rangeOfComposedCharacterSequence(at: safeRange.location - 1)
            return TextEdit(range: deleteRange, replacement: "")
        }

        return apply(edits: edits, selectionMode: .cursorAfterReplacement)
    }

    private func deleteForwardAcrossSelections() -> Bool {
        let ranges = editorSelectionRanges
        guard ranges.count > 1 else { return false }

        let nsText = editorNSString
        let edits = ranges.compactMap { range -> TextEdit? in
            let safeRange = normalizedRange(range)
            if safeRange.length > 0 {
                return TextEdit(range: safeRange, replacement: "")
            }

            guard safeRange.location < nsText.length else { return nil }
            let deleteRange = nsText.rangeOfComposedCharacterSequence(at: safeRange.location)
            return TextEdit(range: deleteRange, replacement: "")
        }

        return apply(edits: edits, selectionMode: .cursorAfterReplacement)
    }

    private func rangesForEditing(replacementRange: NSRange) -> [NSRange] {
        if replacementRange.location != NSNotFound {
            return normalizedRanges([replacementRange])
        }

        return editorSelectionRanges
    }

    private func plainText(from insertString: Any) -> String? {
        switch insertString {
        case let string as String:
            return string
        case let attributedString as NSAttributedString:
            return attributedString.string
        default:
            return nil
        }
    }

    private func insertSmartText(_ insertString: Any, replacementRange: NSRange) -> Bool {
        guard let replacement = plainText(from: insertString),
              replacement.utf16.count == 1 else {
            return false
        }

        if skipOverClosingPair(replacement, replacementRange: replacementRange) {
            return true
        }

        guard let pair = smartPair(for: replacement) else {
            return false
        }

        return insertSmartPair(pair, replacementRange: replacementRange)
    }

    private func smartPair(for replacement: String) -> (left: String, right: String)? {
        switch replacement {
        case "(": return ("(", ")")
        case "[": return ("[", "]")
        case "{": return ("{", "}")
        case "\"": return ("\"", "\"")
        case "'": return ("'", "'")
        case "`" where currentLanguage == .markdown: return ("`", "`")
        case "*" where currentLanguage == .markdown && nonEmptySelectedRanges().count > 0,
             "_" where currentLanguage == .markdown && nonEmptySelectedRanges().count > 0:
            return (replacement, replacement)
        default:
            return nil
        }
    }

    private func insertSmartPair(_ pair: (left: String, right: String), replacementRange: NSRange) -> Bool {
        let targetRanges = rangesForEditing(replacementRange: replacementRange)
        guard !targetRanges.isEmpty else { return false }

        let nsText = editorNSString
        let edits = targetRanges.map { range in
            let selectedText = nsText.substring(with: normalizedRange(range))
            return TextEdit(range: range, replacement: "\(pair.left)\(selectedText)\(pair.right)")
        }

        var delta = 0
        let newSelections = edits.map { edit in
            let location = edit.range.location + delta + pair.left.utf16.count
            let selection = NSRange(location: location, length: edit.range.length)
            delta += edit.replacement.utf16.count - edit.range.length
            return selection
        }

        return apply(edits: edits, newSelections: newSelections)
    }

    private func skipOverClosingPair(_ replacement: String, replacementRange: NSRange) -> Bool {
        guard replacementRange.location == NSNotFound,
              ")]}\"'`".contains(replacement),
              editorSelectionRanges.count == 1,
              let cursor = editorSelectionRanges.first,
              cursor.length == 0 else {
            return false
        }

        let nsText = editorNSString
        guard cursor.location < nsText.length,
              nsText.substring(with: NSRange(location: cursor.location, length: 1)) == replacement else {
            return false
        }

        setEditorSelectionRanges([NSRange(location: cursor.location + 1, length: 0)], scrollToLast: true)
        return true
    }

    private func deleteSurroundingPair() -> Bool {
        guard editorSelectionRanges.count == 1,
              let cursor = editorSelectionRanges.first,
              cursor.length == 0,
              cursor.location > 0 else {
            return false
        }

        let nsText = editorNSString
        guard cursor.location < nsText.length else { return false }

        let left = nsText.substring(with: NSRange(location: cursor.location - 1, length: 1))
        let right = nsText.substring(with: NSRange(location: cursor.location, length: 1))
        guard smartPair(for: left)?.right == right ||
            ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"][left] == right else {
            return false
        }

        return apply(
            edits: [TextEdit(range: NSRange(location: cursor.location - 1, length: 2), replacement: "")],
            newSelections: [NSRange(location: cursor.location - 1, length: 0)]
        )
    }

    private func continueMarkdownLineAfterReturn() -> Bool {
        guard currentLanguage == .markdown,
              editorSelectionRanges.count == 1,
              let cursor = editorSelectionRanges.first,
              cursor.length == 0 else {
            return false
        }

        let nsText = editorNSString
        let safeLocation = min(max(0, cursor.location), nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        let contentRange = contentRange(for: lineRange)
        let line = nsText.substring(with: contentRange)

        guard let continuation = markdownContinuation(for: line) else {
            return false
        }

        let trailingText = (line as NSString).substring(from: min(continuation.markerLength, (line as NSString).length))
        if trailingText.trimmingCharacters(in: .whitespaces).isEmpty {
            let edit = TextEdit(
                range: NSRange(location: lineRange.location, length: continuation.markerLength),
                replacement: ""
            )
            return apply(edits: [edit], newSelections: [NSRange(location: lineRange.location, length: 0)])
        }

        let insertion = "\n\(continuation.nextPrefix)"
        let edit = TextEdit(range: NSRange(location: safeLocation, length: 0), replacement: insertion)
        return apply(
            edits: [edit],
            newSelections: [NSRange(location: safeLocation + insertion.utf16.count, length: 0)]
        )
    }

    private func markdownContinuation(for line: String) -> (markerLength: Int, nextPrefix: String)? {
        let patterns: [(String, (NSTextCheckingResult, NSString) -> String)] = [
            ("^(\\s*)[-*+]\\s+\\[[ xX]\\]\\s+", { match, nsLine in
                "\(nsLine.substring(with: match.range(at: 1)))- [ ] "
            }),
            ("^(\\s*)(\\d+)([.)])\\s+", { match, nsLine in
                let indent = nsLine.substring(with: match.range(at: 1))
                let number = Int(nsLine.substring(with: match.range(at: 2))) ?? 1
                let delimiter = nsLine.substring(with: match.range(at: 3))
                return "\(indent)\(number + 1)\(delimiter) "
            }),
            ("^(\\s*)[-*+]\\s+", { match, nsLine in
                "\(nsLine.substring(with: match.range(at: 1)))- "
            }),
            ("^(\\s*)>\\s?", { match, nsLine in
                "\(nsLine.substring(with: match.range(at: 1)))> "
            })
        ]

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        for (pattern, nextPrefix) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: fullRange),
                  match.range.location == 0 else {
                continue
            }

            return (match.range.length, nextPrefix(match, nsLine))
        }

        return nil
    }

    private func apply(edits: [TextEdit], selectionMode: MultiEditSelectionMode) -> Bool {
        let preparedEdits = nonOverlappingEdits(edits)
        guard !preparedEdits.isEmpty else { return false }

        let newSelections = selectionsAfterApplying(edits: preparedEdits, selectionMode: selectionMode)
        return apply(edits: preparedEdits, newSelections: newSelections)
    }

    private func apply(edits: [TextEdit], newSelections: [NSRange]) -> Bool {
        let preparedEdits = nonOverlappingEdits(edits)
        guard !preparedEdits.isEmpty else { return false }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        for edit in preparedEdits.reversed() {
            replaceCharacters(in: edit.range, with: edit.replacement)
        }

        setEditorSelectionRanges(normalizedRanges(newSelections), scrollToLast: true)
        return true
    }

    private func selectionsAfterApplying(
        edits: [TextEdit],
        selectionMode: MultiEditSelectionMode
    ) -> [NSRange] {
        var delta = 0
        return edits.map { edit in
            let replacementLength = edit.replacement.utf16.count
            let location = edit.range.location + delta
            let selectionRange: NSRange
            switch selectionMode {
            case .cursorAfterReplacement:
                selectionRange = NSRange(location: location + replacementLength, length: 0)
            case .selectReplacement:
                selectionRange = NSRange(location: location, length: replacementLength)
            }

            delta += replacementLength - edit.range.length
            return selectionRange
        }
    }

    private func trackColumnSelection(from event: NSEvent, anchorLocation: Int) {
        guard let window else { return }

        var dragState = ColumnDragState(anchorLocation: anchorLocation)
        columnDragState = dragState

        while let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch nextEvent.type {
            case .leftMouseDragged:
                guard let currentLocation = characterLocation(for: nextEvent) else { continue }
                dragState.didDrag = true
                columnDragState = dragState
                let flags = nextEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let ranges = columnRanges(
                    from: anchorLocation,
                    to: currentLocation,
                    createsSelections: flags.contains(.shift)
                )
                if !ranges.isEmpty {
                    setEditorSelectionRanges(ranges, scrollToLast: true)
                }

            case .leftMouseUp:
                columnDragState = nil
                if dragState.didDrag {
                    let currentLocation = characterLocation(for: nextEvent) ?? anchorLocation
                    let flags = nextEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let ranges = columnRanges(
                        from: anchorLocation,
                        to: currentLocation,
                        createsSelections: flags.contains(.shift)
                    )
                    if !ranges.isEmpty {
                        setEditorSelectionRanges(ranges, scrollToLast: true)
                    }
                } else {
                    var ranges = editorSelectionRanges
                    ranges.append(NSRange(location: anchorLocation, length: 0))
                    setEditorSelectionRanges(ranges, scrollToLast: true)
                }
                return

            default:
                window.sendEvent(nextEvent)
            }
        }

        columnDragState = nil
    }

    private func addVerticalCursor(direction: Int) -> Bool {
        let activeRange = editorSelectionRanges.last ?? NSRange(location: 0, length: 0)
        let activeLocation = activeRange.location + activeRange.length
        guard let lineInfo = lineInfo(for: activeLocation) else { return false }

        let targetLineIndex = lineInfo.index + direction
        guard targetLineIndex >= 0,
              targetLineIndex < lineRanges.count else {
            return false
        }

        let targetLocation = location(inLineAt: targetLineIndex, column: lineInfo.column)
        var ranges = editorSelectionRanges
        ranges.append(NSRange(location: targetLocation, length: 0))
        setEditorSelectionRanges(ranges, scrollToLast: true)
        return true
    }

    private func columnRanges(from anchorLocation: Int, to currentLocation: Int, createsSelections: Bool) -> [NSRange] {
        guard let anchorInfo = lineInfo(for: anchorLocation),
              let currentInfo = lineInfo(for: currentLocation) else {
            return [NSRange(location: anchorLocation, length: 0)]
        }

        let startLine = min(anchorInfo.index, currentInfo.index)
        let endLine = max(anchorInfo.index, currentInfo.index)

        return (startLine...endLine).map { lineIndex in
            if createsSelections {
                let first = location(inLineAt: lineIndex, column: anchorInfo.column)
                let second = location(inLineAt: lineIndex, column: currentInfo.column)
                return NSRange(location: min(first, second), length: abs(second - first))
            }

            return NSRange(location: location(inLineAt: lineIndex, column: anchorInfo.column), length: 0)
        }
    }

    private func characterLocation(for event: NSEvent) -> Int? {
        guard let window else { return nil }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        let location = characterIndex(for: screenPoint)
        guard location != NSNotFound else { return nil }
        return min(max(0, location), editorNSString.length)
    }

    private func isColumnCursorMouseModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option) && (flags.contains(.command) || flags.contains(.function))
    }

    private var editorNSString: NSString {
        (text ?? "") as NSString
    }

    private var lineRanges: [NSRange] {
        let nsText = editorNSString
        guard nsText.length > 0 else {
            return [NSRange(location: 0, length: 0)]
        }

        var ranges: [NSRange] = []
        var location = 0
        while location < nsText.length {
            let range = nsText.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(range)
            let nextLocation = range.location + max(range.length, 1)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        if nsText.endsWithLineBreak {
            ranges.append(NSRange(location: nsText.length, length: 0))
        }

        return ranges
    }

    private func lineInfo(for location: Int) -> LineInfo? {
        let ranges = lineRanges
        let textLength = editorNSString.length
        let safeLocation = min(max(0, location), textLength)

        for (index, lineRange) in ranges.enumerated() {
            let lineEnd = lineRange.location + lineRange.length
            if safeLocation <= lineEnd || index == ranges.count - 1 {
                let contentLength = contentLength(for: lineRange)
                let column = min(max(0, safeLocation - lineRange.location), contentLength)
                return LineInfo(index: index, column: column)
            }
        }

        return nil
    }

    private func location(inLineAt lineIndex: Int, column: Int) -> Int {
        let ranges = lineRanges
        guard ranges.indices.contains(lineIndex) else {
            return editorNSString.length
        }

        let lineRange = ranges[lineIndex]
        let contentLength = contentLength(for: lineRange)
        return lineRange.location + min(max(0, column), contentLength)
    }

    private func contentLength(for lineRange: NSRange) -> Int {
        let nsText = editorNSString
        var length = min(lineRange.length, max(0, nsText.length - lineRange.location))

        while length > 0 {
            let character = nsText.character(at: lineRange.location + length - 1)
            guard character == 10 || character == 13 else { break }
            length -= 1
        }

        return length
    }

    private func contentRange(for lineRange: NSRange) -> NSRange {
        NSRange(location: lineRange.location, length: contentLength(for: lineRange))
    }

    func normalizedRanges(_ ranges: [NSRange]) -> [NSRange] {
        var seen = Set<String>()
        return ranges
            .map(normalizedRange)
            .filter { range in
                let key = "\(range.location):\(range.length)"
                return seen.insert(key).inserted
            }
            .sorted { first, second in
                if first.location == second.location {
                    return first.length < second.length
                }
                return first.location < second.location
            }
    }

    private func normalizedRange(_ range: NSRange) -> NSRange {
        let textLength = editorNSString.length
        let location = min(max(0, range.location), textLength)
        let length = min(max(0, range.length), textLength - location)
        return NSRange(location: location, length: length)
    }

    private func nonOverlappingEdits(_ edits: [TextEdit]) -> [TextEdit] {
        var previousEnd = -1
        var seen = Set<String>()
        return edits
            .map { edit in
                TextEdit(
                    range: normalizedRange(edit.range),
                    replacement: edit.replacement
                )
            }
            .sorted { $0.range.location < $1.range.location }
            .filter { edit in
                let key = "\(edit.range.location):\(edit.range.length)"
                guard seen.insert(key).inserted else { return false }
                guard edit.range.location >= previousEnd else { return false }
                previousEnd = edit.range.location + edit.range.length
                return true
            }
    }

    private func nonEmptySelectedRanges() -> [NSRange] {
        editorSelectionRanges
            .filter { $0.length > 0 }
            .sorted { $0.location < $1.location }
    }

    private func mergedLineRanges(for ranges: [NSRange]) -> [NSRange] {
        let nsText = editorNSString
        let lineRanges = ranges.map { nsText.lineRange(for: $0) }
            .sorted { $0.location < $1.location }

        var merged: [NSRange] = []
        for range in lineRanges {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            let lastEnd = last.location + last.length
            let rangeEnd = range.location + range.length
            if range.location <= lastEnd {
                merged[merged.count - 1] = NSRange(location: last.location, length: max(lastEnd, rangeEnd) - last.location)
            } else {
                merged.append(range)
            }
        }

        return merged
    }

    private func preserveTrailingNewline(_ text: String, transform: ([String]) -> [String]) -> String {
        let hasTrailingNewline = text.hasSuffix("\n") || text.hasSuffix("\r")
        var lines = text.components(separatedBy: .newlines)
        if hasTrailingNewline, lines.last == "" {
            lines.removeLast()
        }

        let output = transform(lines).joined(separator: "\n")
        return hasTrailingNewline ? "\(output)\n" : output
    }

    func updateFocusModeDimming() {
        let nsText = editorNSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else { return }

        removeRenderingAttribute(.foregroundColor, range: fullRange)
        guard focusModeEnabled else {
            needsDisplay = true
            return
        }

        addRenderingAttributes(
            [.foregroundColor: NSColor.labelColor.withAlphaComponent(0.24)],
            range: fullRange
        )

        let activeRange = focusedBlockRange()
        addRenderingAttributes([.foregroundColor: NSColor.labelColor], range: activeRange)
        needsDisplay = true
    }

    func centerSelectionForTypewriterModeIfNeeded(immediate: Bool = false) {
        guard typewriterModeEnabled else { return }

        let center = { [weak self] in
            guard let self, self.typewriterModeEnabled else { return }
            self.centerActiveLineForTypewriterMode()
        }

        if immediate {
            center()
        } else {
            DispatchQueue.main.async(execute: center)
        }
    }

    private func centerActiveLineForTypewriterMode() {
        guard let scrollView = enclosingScrollView,
              let window,
              let selection = editorSelectionRanges.last else {
            centerSelectionInVisibleArea(nil)
            return
        }

        let nsText = editorNSString
        let caretLocation = min(selection.location + selection.length, nsText.length)
        let caretRange = NSRange(location: caretLocation, length: 0)
        let screenRect = firstRect(forCharacterRange: caretRange, actualRange: nil)

        guard !screenRect.isEmpty, !screenRect.isNull, !screenRect.isInfinite else {
            scrollRangeToVisible(caretRange)
            centerSelectionInVisibleArea(nil)
            return
        }

        let windowOrigin = window.convertPoint(fromScreen: screenRect.origin)
        let localOrigin = convert(windowOrigin, from: nil)
        let localRect = NSRect(origin: localOrigin, size: screenRect.size)
        let clipView = scrollView.contentView
        let visibleRect = clipView.documentVisibleRect
        guard visibleRect.height > 0 else { return }

        let targetY = localRect.midY - visibleRect.height * 0.5
        let maxY = max(0, bounds.height - visibleRect.height)
        let clampedY = min(max(0, targetY), maxY)
        clipView.setBoundsOrigin(NSPoint(x: visibleRect.origin.x, y: clampedY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func focusedBlockRange() -> NSRange {
        let nsText = editorNSString
        guard nsText.length > 0 else { return NSRange(location: 0, length: 0) }

        let cursor = editorSelectionRanges.last ?? NSRange(location: 0, length: 0)
        let safeLocation = min(max(0, cursor.location), nsText.length)
        guard let currentLine = lineInfo(for: safeLocation) else {
            return NSRange(location: safeLocation, length: 0)
        }

        let ranges = lineRanges
        var startIndex = currentLine.index
        var endIndex = currentLine.index

        if isBlankLine(ranges[currentLine.index]) {
            return ranges[currentLine.index]
        }

        while startIndex > 0, !isBlankLine(ranges[startIndex - 1]) {
            startIndex -= 1
        }

        while endIndex + 1 < ranges.count, !isBlankLine(ranges[endIndex + 1]) {
            endIndex += 1
        }

        let start = ranges[startIndex].location
        let endRange = ranges[endIndex]
        return NSRange(location: start, length: endRange.location + endRange.length - start)
    }

    private func isBlankLine(_ range: NSRange) -> Bool {
        let text = editorNSString.substring(with: contentRange(for: range))
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ColumnDragState {
    var anchorLocation: Int
    var didDrag = false
}

private struct LineInfo {
    var index: Int
    var column: Int
}

private struct TextEdit {
    var range: NSRange
    var replacement: String
}

private enum MultiEditSelectionMode {
    case cursorAfterReplacement
    case selectReplacement
}

private extension NSString {
    var endsWithLineBreak: Bool {
        guard length > 0 else { return false }
        let lastCharacter = character(at: length - 1)
        return lastCharacter == 10 || lastCharacter == 13
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last == " " || last == "\t" {
            result.removeLast()
        }
        return result
    }

    func swappingCase() -> String {
        map { character in
            let value = String(character)
            let uppercased = value.uppercased()
            let lowercased = value.lowercased()

            if value == uppercased, value != lowercased {
                return lowercased
            }

            if value == lowercased, value != uppercased {
                return uppercased
            }

            return value
        }
        .joined()
    }
}
