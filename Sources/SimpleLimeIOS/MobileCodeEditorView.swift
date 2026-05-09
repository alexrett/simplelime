import STTextView
import SwiftUI
import UIKit

struct MobileCodeEditorView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectionRanges: [TextRange]

    let language: EditorLanguage
    let fontSize: CGFloat
    let wrapsLines: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> STTextView {
        let textView = MobileEditorTextView()
        textView.textDelegate = context.coordinator
        textView.allowsUndo = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.alwaysBounceHorizontal = true
        textView.showsLineNumbers = true
        textView.highlightSelectedLine = true
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 24)
        applyChrome(to: textView)
        return textView
    }

    func updateUIView(_ textView: STTextView, context: Context) {
        context.coordinator.parent = self
        applyChrome(to: textView)

        context.coordinator.isProgrammaticUpdate = true
        if textView.text != text {
            textView.text = text
        }
        applySelection(selectionRanges, to: textView)
        context.coordinator.isProgrammaticUpdate = false

        let appliedSelection = currentSelectionRanges(in: textView)
        MobileSyntaxHighlighter.apply(language: language, to: textView, fontSize: fontSize)
        if appliedSelection.count > 1 {
            applySelection(appliedSelection, to: textView)
        }
    }

    private func applyChrome(to textView: STTextView) {
        let background = UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
        textView.backgroundColor = background
        textView.tintColor = UIColor(red: 0.05, green: 0.52, blue: 1.0, alpha: 1)
        textView.textColor = UIColor(white: 0.86, alpha: 1)
        textView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.isHorizontallyResizable = !wrapsLines
        textView.showsHorizontalScrollIndicator = !wrapsLines
        textView.selectedLineHighlightColor = UIColor(red: 0.10, green: 0.18, blue: 0.30, alpha: 0.72)
        textView.gutterView?.backgroundColor = background
        textView.gutterView?.font = UIFont.monospacedDigitSystemFont(ofSize: max(11, fontSize - 2), weight: .regular)
        textView.gutterView?.textColor = UIColor(white: 0.45, alpha: 1)
        textView.gutterView?.selectedLineTextColor = UIColor(white: 0.72, alpha: 1)
        textView.gutterView?.selectedLineHighlightColor = textView.selectedLineHighlightColor
        textView.gutterView?.separatorColor = UIColor(white: 1, alpha: 0.08)
    }

    private func applySelection(_ ranges: [TextRange], to textView: STTextView) {
        let nsRanges = ranges.map { $0.nsRange }.filter { range in
            range.location != NSNotFound && range.location <= (textView.text as NSString?)?.length ?? 0
        }
        guard !nsRanges.isEmpty else { return }

        if nsRanges.count == 1 {
            textView.textSelection = nsRanges[0]
            textView.scrollRangeToVisible(nsRanges[0])
            return
        }

        let selections = nsRanges
            .compactMap { NSTextRange($0, in: textView.textContentManager) }
            .map { NSTextSelection(range: $0, affinity: .downstream, granularity: .character) }
        guard !selections.isEmpty else { return }
        textView.textLayoutManager.textSelections = selections
        textView.scrollRangeToVisible(nsRanges[0])
        (textView as? MobileEditorTextView)?.updateMultiCursorOverlays()
    }

    private func currentSelectionRanges(in textView: STTextView) -> [TextRange] {
        let ranges = textView.textLayoutManager.textSelections
            .flatMap(\.textRanges)
            .map { TextRange(NSRange($0, in: textView.textContentManager)) }
        return ranges.isEmpty ? [.zero] : ranges
    }

    final class Coordinator: NSObject, STTextViewDelegate {
        var parent: MobileCodeEditorView
        var isProgrammaticUpdate = false

        init(_ parent: MobileCodeEditorView) {
            self.parent = parent
        }

        func textViewDidChangeText(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView = notification.object as? STTextView else { return }
            parent.text = textView.text ?? ""
            (textView as? MobileEditorTextView)?.updateMultiCursorOverlays()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView = notification.object as? STTextView else { return }
            let ranges = textView.textLayoutManager.textSelections
                .flatMap(\.textRanges)
                .map { TextRange(NSRange($0, in: textView.textContentManager)) }
            parent.selectionRanges = ranges.isEmpty ? [.zero] : ranges
            (textView as? MobileEditorTextView)?.updateMultiCursorOverlays()
        }

        func textView(_ textView: STTextView, willChangeTextIn affectedCharRange: NSTextRange, replacementString: String) {
            (textView as? MobileEditorTextView)?.recordSystemMultiCursorEdit(
                range: NSRange(affectedCharRange, in: textView.textContentManager),
                replacement: replacementString
            )
        }
    }
}

private final class MobileEditorTextView: STTextView {
    private var multiCursorViews: [UIView] = []
    private var pendingSystemMultiCursorEdits: [TextEdit] = []
    private var isSystemMultiCursorRestoreScheduled = false

    override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        let cursorAbove = UIKeyCommand(
            input: UIKeyCommand.inputUpArrow,
            modifierFlags: .alternate,
            action: #selector(addCursorAbove)
        )
        cursorAbove.discoverabilityTitle = "Add Cursor Above"
        commands.append(cursorAbove)

        let cursorBelow = UIKeyCommand(
            input: UIKeyCommand.inputDownArrow,
            modifierFlags: .alternate,
            action: #selector(addCursorBelow)
        )
        cursorBelow.discoverabilityTitle = "Add Cursor Below"
        commands.append(cursorBelow)
        return commands
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if handleVerticalCursorPresses(presses) {
            return
        }

        super.pressesBegan(presses, with: event)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateMultiCursorOverlays()
    }

    @objc private func addCursorAbove() {
        _ = addVerticalCursor(direction: -1)
    }

    @objc private func addCursorBelow() {
        _ = addVerticalCursor(direction: 1)
    }

    private func handleVerticalCursorPresses(_ presses: Set<UIPress>) -> Bool {
        guard presses.count == 1,
              let key = presses.first?.key else {
            return false
        }

        let flags = key.modifierFlags
        guard flags.contains(.alternate),
              !flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.shift) else {
            return false
        }

        switch key.keyCode {
        case .keyboardUpArrow:
            return addVerticalCursor(direction: -1)
        case .keyboardDownArrow:
            return addVerticalCursor(direction: 1)
        default:
            return false
        }
    }

    private var editorSelectionRanges: [NSRange] {
        textLayoutManager.textSelections
            .flatMap(\.textRanges)
            .map { NSRange($0, in: textContentManager) }
            .map(normalizedRange)
            .sorted { first, second in
                if first.location == second.location {
                    return first.length < second.length
                }
                return first.location < second.location
            }
    }

    private func setEditorSelectionRanges(_ ranges: [NSRange]) {
        let safeRanges = normalizedRanges(ranges)
        let textRanges = safeRanges.compactMap { NSTextRange($0, in: textContentManager) }
        guard !textRanges.isEmpty else { return }

        textLayoutManager.textSelections = textRanges.map {
            NSTextSelection(range: $0, affinity: .downstream, granularity: .character)
        }
        scrollRangeToVisible(safeRanges.last ?? NSRange(location: 0, length: 0))
        updateMultiCursorOverlays()
        setNeedsLayout()
        setNeedsDisplay()
    }

    private func addVerticalCursor(direction: Int) -> Bool {
        let activeRange = editorSelectionRanges.last ?? NSRange(location: 0, length: 0)
        let activeLocation = activeRange.location + activeRange.length
        guard let lineInfo = lineInfo(for: activeLocation) else { return false }

        let targetLineIndex = lineInfo.index + direction
        guard targetLineIndex >= 0, targetLineIndex < lineRanges.count else {
            return false
        }

        let targetLocation = location(inLineAt: targetLineIndex, column: lineInfo.column)
        var ranges = editorSelectionRanges
        ranges.append(NSRange(location: targetLocation, length: 0))
        setEditorSelectionRanges(ranges)
        return true
    }

    private func selectionsAfterApplying(edits: [TextEdit]) -> [NSRange] {
        var delta = 0
        return edits.map { edit in
            let replacementLength = edit.replacement.utf16.count
            let location = edit.range.location + delta
            delta += replacementLength - edit.range.length
            return NSRange(location: location + replacementLength, length: 0)
        }
    }

    private func nonOverlappingEdits(_ edits: [TextEdit]) -> [TextEdit] {
        var previousEnd = -1
        var seen = Set<String>()
        return edits
            .map { TextEdit(range: normalizedRange($0.range), replacement: $0.replacement) }
            .sorted { $0.range.location < $1.range.location }
            .filter { edit in
                let key = "\(edit.range.location):\(edit.range.length)"
                guard seen.insert(key).inserted else { return false }
                guard edit.range.location >= previousEnd else { return false }
                previousEnd = edit.range.location + edit.range.length
                return true
            }
    }

    func recordSystemMultiCursorEdit(range: NSRange, replacement: String) {
        guard editorSelectionRanges.count > 1 || !pendingSystemMultiCursorEdits.isEmpty else {
            return
        }

        pendingSystemMultiCursorEdits.append(TextEdit(range: range, replacement: replacement))
        scheduleSystemMultiCursorRestore()
    }

    private func scheduleSystemMultiCursorRestore() {
        guard !isSystemMultiCursorRestoreScheduled else { return }
        isSystemMultiCursorRestoreScheduled = true

        DispatchQueue.main.async { [weak self] in
            self?.restoreSystemMultiCursorSelections()
        }
    }

    private func restoreSystemMultiCursorSelections() {
        isSystemMultiCursorRestoreScheduled = false
        let edits = pendingSystemMultiCursorEdits
        pendingSystemMultiCursorEdits.removeAll()

        let preparedEdits = nonOverlappingEdits(edits)
        guard preparedEdits.count > 1 else {
            updateMultiCursorOverlays()
            return
        }

        setEditorSelectionRanges(selectionsAfterApplying(edits: preparedEdits))
    }

    func updateMultiCursorOverlays() {
        multiCursorViews.forEach { $0.removeFromSuperview() }
        multiCursorViews.removeAll()

        let ranges = editorSelectionRanges
        guard ranges.count > 1 else { return }

        for range in ranges where range.length == 0 {
            guard let position = position(from: beginningOfDocument, offset: range.location) else {
                continue
            }

            let caretFrame = caretRect(for: position)
            guard !caretFrame.isNull, !caretFrame.isEmpty else { continue }
            let cursorView = UIView(frame: CGRect(
                x: caretFrame.minX,
                y: caretFrame.minY,
                width: max(2, caretFrame.width),
                height: caretFrame.height
            ))
            cursorView.backgroundColor = tintColor
            cursorView.isUserInteractionEnabled = false
            cursorView.layer.zPosition = 1000
            addSubview(cursorView)
            bringSubviewToFront(cursorView)
            multiCursorViews.append(cursorView)
        }
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

        if nsText.hasTrailingLineBreak {
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

    private func normalizedRanges(_ ranges: [NSRange]) -> [NSRange] {
        var seen = Set<String>()
        let normalized = ranges
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
        return normalized.isEmpty ? [NSRange(location: 0, length: 0)] : normalized
    }

    private func normalizedRange(_ range: NSRange) -> NSRange {
        let textLength = editorNSString.length
        let location = min(max(0, range.location), textLength)
        let length = min(max(0, range.length), textLength - location)
        return NSRange(location: location, length: length)
    }
}

private struct TextEdit {
    var range: NSRange
    var replacement: String
}

private struct LineInfo {
    var index: Int
    var column: Int
}

private extension NSString {
    var hasTrailingLineBreak: Bool {
        guard length > 0 else { return false }
        let lastCharacter = character(at: length - 1)
        return lastCharacter == 10 || lastCharacter == 13
    }
}

private enum MobileSyntaxHighlighter {
    static func apply(language: EditorLanguage, to textView: STTextView, fontSize: CGFloat) {
        let text = textView.text ?? ""
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else { return }

        let baseFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.setAttributes([
            .font: baseFont,
            .foregroundColor: UIColor(white: 0.86, alpha: 1)
        ], range: fullRange)

        switch language {
        case .markdown:
            applyMarkdown(to: textView, text: text, fontSize: fontSize)
        case .json:
            applyJSON(to: textView, text: text)
        default:
            applyCodeComments(to: textView, text: text)
        }
    }

    private static func applyMarkdown(to textView: STTextView, text: String, fontSize: CGFloat) {
        apply(pattern: #"(?m)^#{1,6}\s+.*$"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.10, green: 0.58, blue: 1.0, alpha: 1),
            .font: UIFont.monospacedSystemFont(ofSize: fontSize + 2, weight: .bold)
        ])
        apply(pattern: #"(?m)^\s*[-*+]\s+"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.95, green: 0.58, blue: 0.18, alpha: 1)
        ])
        apply(pattern: #"`[^`]+`"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.50, green: 0.84, blue: 0.48, alpha: 1)
        ])
    }

    private static func applyJSON(to textView: STTextView, text: String) {
        apply(pattern: #""([^"\\]|\\.)*"(?=\s*:)"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 1.0, green: 0.34, blue: 0.34, alpha: 1)
        ])
        apply(pattern: #"(?<=:)\s*"([^"\\]|\\.)*""#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.55, green: 0.76, blue: 1.0, alpha: 1)
        ])
        apply(pattern: #"\b(true|false|null)\b"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.10, green: 0.58, blue: 1.0, alpha: 1)
        ])
        apply(pattern: #"\b-?\d+(\.\d+)?\b"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.95, green: 0.58, blue: 0.18, alpha: 1)
        ])
    }

    private static func applyCodeComments(to textView: STTextView, text: String) {
        apply(pattern: #"(?m)//.*$|#.*$"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(white: 0.45, alpha: 1)
        ])
    }

    private static func apply(pattern: String, text: String, to textView: STTextView, attrs: [NSAttributedString.Key: Any]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: (text as NSString).length)
        regex.matches(in: text, range: range).forEach { match in
            textView.addAttributes(attrs, range: match.range)
        }
    }
}
