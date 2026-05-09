import AppKit
import STTextView
import SwiftUI

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectionRanges: [TextRange]

    var language: EditorLanguage
    var fontSize: Double
    var wrapsLines: Bool
    var onShortcut: (EditorShortcut) -> Void
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

        registerCommandHandler(for: textView)
        configure(textView: textView, in: scrollView, wrapsLines: wrapsLines, fontSize: CGFloat(fontSize))
        applySyntaxHighlighting(to: textView, language: language, fontSize: CGFloat(fontSize))
        applySelection(selectionRanges, to: textView)

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
        registerCommandHandler(for: textView)
        configure(textView: textView, in: scrollView, wrapsLines: wrapsLines, fontSize: CGFloat(fontSize))
        applySyntaxHighlighting(to: textView, language: language, fontSize: CGFloat(fontSize))
        applySelection(selectionRanges, to: textView)
    }

    private func configure(
        textView: EditorTextView,
        in scrollView: NSScrollView,
        wrapsLines: Bool,
        fontSize: CGFloat
    ) {
        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let lineHighlightColor = NSColor.controlAccentColor.withAlphaComponent(0.10)

        scrollView.hasHorizontalScroller = !wrapsLines
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

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
    }

    final class Coordinator: NSObject, STTextViewDelegate {
        var parent: CodeEditorView
        var isApplyingExternalUpdate = false

        init(_ parent: CodeEditorView) {
            self.parent = parent
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
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? EditorTextView else {
                return
            }

            parent.selectionRanges = textView.editorSelectionRanges.map(TextRange.init)
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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control) else {
            return super.performKeyEquivalent(with: event)
        }

        let shortcut: EditorShortcut?
        switch event.keyCode {
        case 34 where flags.contains(.shift):
            shortcut = .toggleAI
        case 3 where flags.contains(.shift):
            shortcut = .showGlobalFind
        case 3:
            shortcut = .showFind
        case 15:
            shortcut = .showReplace
        case 2:
            shortcut = .transform(.duplicateLine)
        case 37 where flags.contains(.shift):
            shortcut = .selectAllMatches
        case 5 where flags.contains(.option):
            shortcut = .addNextOccurrence
        case 6 where flags.contains(.option):
            shortcut = .toggleWrapLines
        case 32 where flags.contains(.option) && flags.contains(.shift):
            shortcut = .transform(.uniqueLines)
        case 32 where flags.contains(.shift):
            shortcut = .transform(.uppercase)
        case 32 where flags.contains(.option):
            shortcut = .transform(.lowercase)
        case 17 where flags.contains(.option):
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
        if insertTextAcrossSelections(insertString, replacementRange: .notFound) {
            return
        }

        super.insertText(insertString)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if insertTextAcrossSelections(string, replacementRange: replacementRange) {
            return
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
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

    private func apply(edits: [TextEdit], selectionMode: MultiEditSelectionMode) -> Bool {
        let preparedEdits = nonOverlappingEdits(edits)
        guard !preparedEdits.isEmpty else { return false }

        let newSelections = selectionsAfterApplying(edits: preparedEdits, selectionMode: selectionMode)

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        for edit in preparedEdits.reversed() {
            replaceCharacters(in: edit.range, with: edit.replacement)
        }

        setEditorSelectionRanges(newSelections, scrollToLast: true)
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
}
