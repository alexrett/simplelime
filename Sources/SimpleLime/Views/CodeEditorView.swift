import AppKit
import SwiftUI

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectionRanges: [TextRange]

    var language: EditorLanguage
    var fontSize: Double
    var onShortcut: (EditorShortcut) -> Void
    var onRegisterEditorCommandHandler: (@escaping (EditorCommand) -> Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = true
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.masksToBounds = true

        let textView = EditorTextView()
        textView.delegate = context.coordinator
        registerCommandHandler(for: textView)
        textView.shortcutHandler = { shortcut in
            context.coordinator.parent.onShortcut(shortcut)
            return true
        }
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.string = text

        scrollView.documentView = textView
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        SyntaxHighlighter.apply(to: textView, language: language, fontSize: fontSize)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.parent = self
        context.coordinator.isApplyingExternalUpdate = true

        if textView.string != text {
            textView.string = text
        }

        (textView as? EditorTextView)?.shortcutHandler = { shortcut in
            context.coordinator.parent.onShortcut(shortcut)
            return true
        }
        if let textView = textView as? EditorTextView {
            registerCommandHandler(for: textView)
        }
        SyntaxHighlighter.apply(to: textView, language: language, fontSize: fontSize)
        (scrollView.verticalRulerView as? LineNumberRulerView)?.invalidateLineNumbers()
        applySelection(selectionRanges, to: textView)
        applyCurrentLineHighlight(to: textView)

        context.coordinator.isApplyingExternalUpdate = false
    }

    private func applySelection(_ ranges: [TextRange], to textView: NSTextView) {
        let textLength = (textView.string as NSString).length
        let values = (ranges.isEmpty ? [.zero] : ranges).map { range in
            let location = min(max(0, range.location), textLength)
            let length = min(max(0, range.length), textLength - location)
            return NSValue(range: NSRange(location: location, length: length))
        }

        if textView.selectedRanges != values {
            textView.selectedRanges = values
            if let last = values.last?.rangeValue {
                textView.scrollRangeToVisible(last)
            }
        }
    }

    private func registerCommandHandler(for textView: EditorTextView) {
        onRegisterEditorCommandHandler { [weak textView] command in
            textView?.performEditorCommand(command) ?? false
        }
    }

    private func applyCurrentLineHighlight(to textView: NSTextView) {
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        var isApplyingExternalUpdate = false

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? NSTextView else {
                return
            }

            parent.text = textView.string
            parent.selectionRanges = textView.selectedRanges.map { TextRange($0.rangeValue) }
            SyntaxHighlighter.apply(to: textView, language: parent.language, fontSize: parent.fontSize)
            parent.applyCurrentLineHighlight(to: textView)
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.invalidateLineNumbers()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? NSTextView else {
                return
            }

            parent.selectionRanges = textView.selectedRanges.map { TextRange($0.rangeValue) }
            SyntaxHighlighter.apply(to: textView, language: parent.language, fontSize: parent.fontSize)
            parent.applyCurrentLineHighlight(to: textView)
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.invalidateLineNumbers()
        }
    }
}

final class EditorTextView: NSTextView {
    var shortcutHandler: ((EditorShortcut) -> Bool)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLineBackground()
    }

    private func drawCurrentLineBackground() {
        guard let lineRect = editorCurrentLineRect() else {
            return
        }

        let visibleRect = self.visibleRect

        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        NSRect(
            x: visibleRect.minX,
            y: lineRect.minY,
            width: visibleRect.width,
            height: lineRect.height
        ).fill()
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

    func performEditorCommand(_ command: EditorCommand) -> Bool {
        switch command {
        case .transform(let transform):
            return performTextTransform(transform)
        }
    }

    private func performTextTransform(_ transform: TextTransform) -> Bool {
        switch transform {
        case .uppercase:
            replaceTargetText { $0.uppercased() }
        case .lowercase:
            replaceTargetText { $0.lowercased() }
        case .titlecase:
            replaceTargetText { $0.capitalized }
        case .sortLines:
            replaceTargetLines { text in
                preserveTrailingNewline(text) { lines in
                    lines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                }
            }
        case .uniqueLines:
            replaceTargetLines { text in
                preserveTrailingNewline(text) { lines in
                    var seen = Set<String>()
                    return lines.filter { seen.insert($0).inserted }
                }
            }
        case .trimTrailingWhitespace:
            replaceTargetLines { text in
                text.components(separatedBy: .newlines)
                    .map { $0.trimmingTrailingWhitespace() }
                    .joined(separator: "\n")
            }
        case .duplicateLine:
            duplicateSelectedLinesOrCurrentLine()
        case .joinLines:
            replaceTargetLines { text in
                text.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
        }
    }

    private func replaceTargetText(_ transform: (String) -> String) -> Bool {
        let nsText = string as NSString
        let ranges = nonEmptySelectedRanges()
        let targetRanges = ranges.isEmpty ? [NSRange(location: 0, length: nsText.length)] : ranges
        let replacements = targetRanges.map { transform(nsText.substring(with: $0)) }
        return replace(ranges: targetRanges, replacements: replacements)
    }

    private func replaceTargetLines(_ transform: (String) -> String) -> Bool {
        let nsText = string as NSString
        let ranges = nonEmptySelectedRanges()
        let targetRanges = ranges.isEmpty
            ? [NSRange(location: 0, length: nsText.length)]
            : mergedLineRanges(for: ranges)
        let replacements = targetRanges.map { transform(nsText.substring(with: $0)) }
        return replace(ranges: targetRanges, replacements: replacements)
    }

    private func duplicateSelectedLinesOrCurrentLine() -> Bool {
        let nsText = string as NSString
        let ranges = nonEmptySelectedRanges()

        if !ranges.isEmpty {
            let replacements = ranges.map { range in
                let selectedText = nsText.substring(with: range)
                return "\(selectedText)\(selectedText)"
            }
            return replace(ranges: ranges, replacements: replacements)
        }

        let cursor = selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
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

        let sorted = zip(ranges, replacements).sorted { lhs, rhs in
            lhs.0.location > rhs.0.location
        }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        var newSelections: [NSValue] = []
        for (range, replacement) in sorted {
            guard shouldChangeText(in: range, replacementString: replacement) else { continue }
            textStorage?.replaceCharacters(in: range, with: replacement)
            didChangeText()
            newSelections.append(NSValue(range: NSRange(location: range.location, length: replacement.utf16.count)))
        }

        selectedRanges = newSelections.reversed()
        return true
    }

    private func nonEmptySelectedRanges() -> [NSRange] {
        selectedRanges.map(\.rangeValue)
            .filter { $0.length > 0 }
            .sorted { $0.location < $1.location }
    }

    private func mergedLineRanges(for ranges: [NSRange]) -> [NSRange] {
        let nsText = string as NSString
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

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last == " " || last == "\t" {
            result.removeLast()
        }
        return result
    }
}
