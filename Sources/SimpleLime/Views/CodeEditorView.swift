import AppKit
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
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.string = text

        scrollView.documentView = textView
        configureWrapping(textView: textView, in: scrollView, wrapsLines: wrapsLines)
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
            (textView as? EditorTextView)?.needsSyntaxHighlight = true
        }

        (textView as? EditorTextView)?.shortcutHandler = { shortcut in
            context.coordinator.parent.onShortcut(shortcut)
            return true
        }
        if let textView = textView as? EditorTextView {
            registerCommandHandler(for: textView)
        }
        configureWrapping(textView: textView, in: scrollView, wrapsLines: wrapsLines)
        applySyntaxHighlighting(to: textView, language: language, fontSize: CGFloat(fontSize))
        (scrollView.verticalRulerView as? LineNumberRulerView)?.invalidateLineNumbers()
        applySelection(selectionRanges, to: textView)
        applyCurrentLineHighlight(to: textView)

        context.coordinator.isApplyingExternalUpdate = false
    }

    private func applySelection(_ ranges: [TextRange], to textView: NSTextView) {
        let textLength = (textView.string as NSString).length
        let normalizedRanges = (ranges.isEmpty ? [.zero] : ranges).map { range in
            let location = min(max(0, range.location), textLength)
            let length = min(max(0, range.length), textLength - location)
            return NSRange(location: location, length: length)
        }

        if let editorTextView = textView as? EditorTextView {
            if editorTextView.editorSelectionRanges != normalizedRanges {
                editorTextView.setEditorSelectionRanges(normalizedRanges, scrollToLast: true)
            }
        } else {
            let values = normalizedRanges.map(NSValue.init(range:))
            if textView.selectedRanges != values {
                textView.selectedRanges = values
            }

            if let last = values.last?.rangeValue {
                textView.scrollRangeToVisible(last)
            }
        }
    }

    private func configureWrapping(textView: NSTextView, in scrollView: NSScrollView, wrapsLines: Bool) {
        if let editorTextView = textView as? EditorTextView,
           editorTextView.configuredWrapsLines == wrapsLines {
            return
        }

        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        if wrapsLines {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(
                width: scrollView.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
            if textView.frame.width != scrollView.contentSize.width {
                textView.frame.size.width = scrollView.contentSize.width
            }
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = [.height]
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.frame.size.width = max(textView.frame.width, scrollView.contentSize.width)
        }

        textView.needsDisplay = true
        (textView as? EditorTextView)?.configuredWrapsLines = wrapsLines
        textView.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length), actualCharacterRange: nil)
    }

    private func registerCommandHandler(for textView: EditorTextView) {
        onRegisterEditorCommandHandler { [weak textView] command in
            textView?.performEditorCommand(command) ?? false
        }
    }

    private func applyCurrentLineHighlight(to textView: NSTextView) {
        textView.needsDisplay = true
    }

    private func applySyntaxHighlighting(to textView: NSTextView, language: EditorLanguage, fontSize: CGFloat) {
        guard let editorTextView = textView as? EditorTextView else {
            SyntaxHighlighter.apply(to: textView, language: language, fontSize: fontSize)
            return
        }

        guard editorTextView.needsSyntaxHighlight ||
            editorTextView.highlightedLanguage != language ||
            editorTextView.highlightedFontSize != fontSize else {
            return
        }

        SyntaxHighlighter.apply(to: textView, language: language, fontSize: fontSize)
        editorTextView.needsSyntaxHighlight = false
        editorTextView.highlightedLanguage = language
        editorTextView.highlightedFontSize = fontSize
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
            parent.selectionRanges = (textView as? EditorTextView)?.editorSelectionRanges.map(TextRange.init) ??
                textView.selectedRanges.map { TextRange($0.rangeValue) }
            (textView as? EditorTextView)?.needsSyntaxHighlight = true
            parent.applySyntaxHighlighting(to: textView, language: parent.language, fontSize: CGFloat(parent.fontSize))
            parent.applyCurrentLineHighlight(to: textView)
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.invalidateLineNumbers()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? NSTextView else {
                return
            }

            (textView as? EditorTextView)?.handleNativeSelectionDidChange()
            parent.selectionRanges = (textView as? EditorTextView)?.editorSelectionRanges.map(TextRange.init) ??
                textView.selectedRanges.map { TextRange($0.rangeValue) }
            parent.applyCurrentLineHighlight(to: textView)
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.invalidateLineNumbers()
        }
    }
}

final class EditorTextView: NSTextView {
    var shortcutHandler: ((EditorShortcut) -> Bool)?
    var needsSyntaxHighlight = true
    var highlightedLanguage: EditorLanguage?
    var highlightedFontSize: CGFloat?
    var configuredWrapsLines: Bool?
    private var multiCursorDragState: MultiCursorDragState?
    private var customInsertionRanges: [NSRange]?
    private var multiSelectionAnchors: [Int]?
    private var isSettingEditorSelection = false

    var editorSelectionRanges: [NSRange] {
        customInsertionRanges ?? selectedRanges.map(\.rangeValue)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func setEditorSelectionRanges(
        _ ranges: [NSRange],
        anchors: [Int]? = nil,
        scrollToLast: Bool = false
    ) {
        let oldRanges = editorSelectionRanges
        let normalizedState = normalizedSelectionState(ranges: ranges, anchors: anchors)
        let normalized = normalizedState.ranges
        let newRanges = normalized.isEmpty ? [NSRange(location: 0, length: 0)] : normalized
        let newAnchors = normalizedState.anchors

        if newRanges.count > 1, newRanges.allSatisfy({ $0.length == 0 }) {
            customInsertionRanges = newRanges
            multiSelectionAnchors = newAnchors ?? newRanges.map(\.location)
            if let primaryRange = newRanges.last {
                setNativeSelectionValues([NSValue(range: primaryRange)])
                if scrollToLast {
                    scrollRangeToVisible(primaryRange)
                }
            }
        } else {
            customInsertionRanges = nil
            multiSelectionAnchors = newRanges.count > 1 ? newAnchors : nil
            let values = newRanges.map(NSValue.init(range:))
            setNativeSelectionValues(values)
            if scrollToLast, let last = newRanges.last {
                scrollRangeToVisible(last)
            }
        }

        invalidateSelectionDisplay()
        if oldRanges != newRanges {
            NotificationCenter.default.post(name: NSTextView.didChangeSelectionNotification, object: self)
        }
    }

    func handleNativeSelectionDidChange() {
        guard !isSettingEditorSelection else { return }

        if let customInsertionRanges {
            let nativeRanges = selectedRanges.map(\.rangeValue)
            if nativeRanges.count == 1, nativeRanges.first == customInsertionRanges.last {
                invalidateSelectionDisplay()
                return
            }

            self.customInsertionRanges = nil
            multiSelectionAnchors = nil
        }

        invalidateSelectionDisplay()
    }

    private func setNativeSelectionValues(_ values: [NSValue]) {
        isSettingEditorSelection = true
        defer { isSettingEditorSelection = false }
        selectedRanges = values
    }

    private func clearCustomInsertionRanges() {
        guard customInsertionRanges != nil else { return }
        customInsertionRanges = nil
        multiSelectionAnchors = nil
        invalidateSelectionDisplay()
    }

    private func invalidateSelectionDisplay() {
        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLineBackground()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawAdditionalInsertionPoints()
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

    private func drawAdditionalInsertionPoints() {
        guard let customInsertionRanges, customInsertionRanges.count > 1 else { return }

        NSColor.controlAccentColor.setFill()
        for range in customInsertionRanges {
            guard let caretRect = caretRect(for: range.location),
                  caretRect.intersects(visibleRect) else {
                continue
            }

            caretRect.fill()
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

    override func mouseDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isColumnCursorMouseModifier(flags),
              let location = insertionLocation(for: convert(event.locationInWindow, from: nil)) else {
            clearCustomInsertionRanges()
            super.mouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        multiCursorDragState = MultiCursorDragState(
            anchorPoint: convert(event.locationInWindow, from: nil),
            anchorLocation: location
        )
        trackMultiCursorDrag(from: event, anchorLocation: location)
    }

    private func trackMultiCursorDrag(from event: NSEvent, anchorLocation: Int) {
        guard let window else { return }

        var dragState = MultiCursorDragState(
            anchorPoint: convert(event.locationInWindow, from: nil),
            anchorLocation: anchorLocation
        )
        var currentPoint = dragState.anchorPoint
        var createsSelections = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.shift)
        multiCursorDragState = dragState

        while let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch nextEvent.type {
            case .leftMouseDragged:
                dragState.didDrag = true
                multiCursorDragState = dragState
                let flags = nextEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                currentPoint = convert(nextEvent.locationInWindow, from: nil)
                createsSelections = flags.contains(.shift)
                let ranges = columnRanges(
                    from: dragState.anchorPoint,
                    to: currentPoint,
                    createsSelections: createsSelections
                )
                if !ranges.isEmpty {
                    setEditorSelectionRanges(ranges)
                }

            case .leftMouseUp:
                createsSelections = nextEvent.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .contains(.shift)
                multiCursorDragState = nil
                if !dragState.didDrag {
                    var ranges = editorSelectionRanges
                    ranges.append(NSRange(location: anchorLocation, length: 0))
                    setEditorSelectionRanges(ranges)
                } else {
                    let finalPoint = convert(nextEvent.locationInWindow, from: nil)
                    if finalPoint != currentPoint {
                        currentPoint = finalPoint
                    }

                    let ranges = columnRanges(
                        from: dragState.anchorPoint,
                        to: currentPoint,
                        createsSelections: createsSelections
                    )
                    if !ranges.isEmpty {
                        setEditorSelectionRanges(ranges)
                    }
                }
                return

            default:
                window.sendEvent(nextEvent)
            }
        }

        multiCursorDragState = nil
    }

    private func isColumnCursorMouseModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option) && (flags.contains(.command) || flags.contains(.function))
    }

    override func mouseDragged(with event: NSEvent) {
        guard var dragState = multiCursorDragState else {
            super.mouseDragged(with: event)
            return
        }

        dragState.didDrag = true
        multiCursorDragState = dragState

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let point = convert(event.locationInWindow, from: nil)
        let ranges = columnRanges(
            from: dragState.anchorPoint,
            to: point,
            createsSelections: flags.contains(.shift)
        )

        guard !ranges.isEmpty else { return }
        setEditorSelectionRanges(ranges)
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragState = multiCursorDragState else {
            super.mouseUp(with: event)
            return
        }

        multiCursorDragState = nil
        guard !dragState.didDrag else { return }

        var ranges = editorSelectionRanges
        ranges.append(NSRange(location: dragState.anchorLocation, length: 0))
        setEditorSelectionRanges(ranges)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard shouldApplyMultiCursorEdit else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let replacement: String
        if let attributed = insertString as? NSAttributedString {
            replacement = attributed.string
        } else {
            replacement = "\(insertString)"
        }

        let ranges = editorSelectionRanges
        _ = replaceForTyping(ranges: ranges, replacement: replacement)
    }

    override func insertNewline(_ sender: Any?) {
        guard shouldApplyMultiCursorEdit else {
            super.insertNewline(sender)
            return
        }

        let ranges = editorSelectionRanges
        _ = replaceForTyping(ranges: ranges, replacement: "\n")
    }

    override func insertTab(_ sender: Any?) {
        guard shouldApplyMultiCursorEdit else {
            super.insertTab(sender)
            return
        }

        let ranges = editorSelectionRanges
        _ = replaceForTyping(ranges: ranges, replacement: "\t")
    }

    override func moveBackward(_ sender: Any?) {
        guard moveMultipleSelections(.characterBackward, modifiesSelection: false) else {
            super.moveBackward(sender)
            return
        }
    }

    override func moveForward(_ sender: Any?) {
        guard moveMultipleSelections(.characterForward, modifiesSelection: false) else {
            super.moveForward(sender)
            return
        }
    }

    override func moveLeft(_ sender: Any?) {
        guard moveMultipleSelections(.characterBackward, modifiesSelection: false) else {
            super.moveLeft(sender)
            return
        }
    }

    override func moveRight(_ sender: Any?) {
        guard moveMultipleSelections(.characterForward, modifiesSelection: false) else {
            super.moveRight(sender)
            return
        }
    }

    override func moveUp(_ sender: Any?) {
        guard moveMultipleSelections(.visualUp, modifiesSelection: false) else {
            super.moveUp(sender)
            return
        }
    }

    override func moveDown(_ sender: Any?) {
        guard moveMultipleSelections(.visualDown, modifiesSelection: false) else {
            super.moveDown(sender)
            return
        }
    }

    override func deleteBackward(_ sender: Any?) {
        guard shouldApplyMultiCursorEdit else {
            super.deleteBackward(sender)
            return
        }

        let ranges = deletionRanges(backward: true)
        guard !ranges.isEmpty else { return }
        _ = replaceForTyping(ranges: ranges, replacement: "")
    }

    override func deleteForward(_ sender: Any?) {
        guard shouldApplyMultiCursorEdit else {
            super.deleteForward(sender)
            return
        }

        let ranges = deletionRanges(backward: false)
        guard !ranges.isEmpty else { return }
        _ = replaceForTyping(ranges: ranges, replacement: "")
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let movement = multiCursorMovement(for: event.keyCode, flags: flags),
           moveMultipleSelections(movement, modifiesSelection: flags.contains(.shift)) {
            return
        }

        if flags.contains(.option), !flags.contains(.command), !flags.contains(.control) {
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

    private func replaceForTyping(ranges: [NSRange], replacement: String) -> Bool {
        let edits = normalizedRanges(ranges).map { TextEdit(range: $0, replacement: replacement) }
        return apply(edits: edits, selectionMode: .cursorAfterReplacement)
    }

    private func apply(edits: [TextEdit], selectionMode: MultiEditSelectionMode) -> Bool {
        let preparedEdits = nonOverlappingEdits(edits)
        guard !preparedEdits.isEmpty else { return false }

        let allowedEdits = preparedEdits.filter {
            shouldChangeText(in: $0.range, replacementString: $0.replacement)
        }
        guard !allowedEdits.isEmpty else { return false }

        let newSelections = selectionsAfterApplying(edits: allowedEdits, selectionMode: selectionMode)

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        textStorage?.beginEditing()
        for edit in allowedEdits.reversed() {
            textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        textStorage?.endEditing()
        didChangeText()

        setEditorSelectionRanges(newSelections)
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

    private var shouldApplyMultiCursorEdit: Bool {
        editorSelectionRanges.count > 1
    }

    private func moveMultipleSelections(
        _ movement: MultiCursorMovement,
        modifiesSelection: Bool
    ) -> Bool {
        let ranges = editorSelectionRanges
        guard ranges.count > 1 else {
            return false
        }

        if modifiesSelection {
            let anchors = selectionAnchors(for: ranges, movement: movement)
            let movedRanges = zip(ranges, anchors).map { range, anchor in
                let activeLocation = activeSelectionLocation(for: range, anchor: anchor)
                let movedLocation = movedLocation(from: activeLocation, movement: movement)
                return selectionRange(anchor: anchor, activeLocation: movedLocation)
            }
            setEditorSelectionRanges(movedRanges, anchors: anchors, scrollToLast: true)
            return true
        }

        let movedRanges = ranges.map { range in
            let location: Int
            if range.length > 0 {
                location = movement.collapsesToStart ? range.location : range.location + range.length
            } else {
                location = movedLocation(from: range.location, movement: movement)
            }

            return NSRange(location: location, length: 0)
        }
        setEditorSelectionRanges(movedRanges, scrollToLast: true)
        return true
    }

    private func selectionAnchors(
        for ranges: [NSRange],
        movement: MultiCursorMovement
    ) -> [Int] {
        if let multiSelectionAnchors, multiSelectionAnchors.count == ranges.count {
            return multiSelectionAnchors
        }

        return ranges.map { range in
            guard range.length > 0 else { return range.location }
            return movement.extendsFromStart ? range.location : range.location + range.length
        }
    }

    private func activeSelectionLocation(for range: NSRange, anchor: Int) -> Int {
        if range.length == 0 {
            return range.location
        }

        if anchor <= range.location {
            return range.location + range.length
        }

        if anchor >= range.location + range.length {
            return range.location
        }

        return range.location + range.length
    }

    private func selectionRange(anchor: Int, activeLocation: Int) -> NSRange {
        NSRange(
            location: min(anchor, activeLocation),
            length: abs(activeLocation - anchor)
        )
    }

    private func movedLocation(from location: Int, movement: MultiCursorMovement) -> Int {
        let nsText = string as NSString
        let textLength = nsText.length
        let clampedLocation = min(max(0, location), textLength)

        switch movement {
        case .characterBackward:
            guard clampedLocation > 0 else { return 0 }
            return nsText.rangeOfComposedCharacterSequence(at: clampedLocation - 1).location

        case .characterForward:
            guard clampedLocation < textLength else { return textLength }
            let range = nsText.rangeOfComposedCharacterSequence(at: clampedLocation)
            return min(textLength, range.location + range.length)

        case .wordBackward:
            return wordBoundary(before: clampedLocation)

        case .wordForward:
            return wordBoundary(after: clampedLocation)

        case .lineStart:
            return lineContentRange(containing: clampedLocation).location

        case .lineEnd:
            let lineRange = lineContentRange(containing: clampedLocation)
            return lineRange.location + lineRange.length

        case .documentStart:
            return 0

        case .documentEnd:
            return textLength

        case .visualUp, .visualDown:
            guard let point = caretPoint(for: clampedLocation),
                  let targetLocation = insertionLocation(
                    for: NSPoint(
                        x: point.x,
                        y: point.y + (movement == .visualUp ? -editorLineHeight : editorLineHeight)
                    )
                  ) else {
                return clampedLocation
            }

            return targetLocation
        }
    }

    private func multiCursorMovement(
        for keyCode: UInt16,
        flags: NSEvent.ModifierFlags
    ) -> MultiCursorMovement? {
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)

        switch keyCode {
        case 123:
            if hasCommand { return .lineStart }
            if hasOption { return .wordBackward }
            return .characterBackward
        case 124:
            if hasCommand { return .lineEnd }
            if hasOption { return .wordForward }
            return .characterForward
        case 125:
            if hasCommand { return .documentEnd }
            if hasOption, !flags.contains(.shift) { return nil }
            return .visualDown
        case 126:
            if hasCommand { return .documentStart }
            if hasOption, !flags.contains(.shift) { return nil }
            return .visualUp
        default:
            return nil
        }
    }

    private func wordBoundary(before location: Int) -> Int {
        let nsText = string as NSString
        var index = min(max(0, location), nsText.length)
        guard index > 0 else { return 0 }

        if index > 0, isWordSeparator(before: index, in: nsText) {
            while index > 0, isWordSeparator(before: index, in: nsText) {
                index = previousCharacterLocation(before: index, in: nsText)
            }
        }

        while index > 0, !isWordSeparator(before: index, in: nsText) {
            index = previousCharacterLocation(before: index, in: nsText)
        }

        return index
    }

    private func wordBoundary(after location: Int) -> Int {
        let nsText = string as NSString
        var index = min(max(0, location), nsText.length)
        guard index < nsText.length else { return nsText.length }

        if isWordSeparator(at: index, in: nsText) {
            while index < nsText.length, isWordSeparator(at: index, in: nsText) {
                index = nextCharacterLocation(after: index, in: nsText)
            }
        }

        while index < nsText.length, !isWordSeparator(at: index, in: nsText) {
            index = nextCharacterLocation(after: index, in: nsText)
        }

        return index
    }

    private func lineContentRange(containing location: Int) -> NSRange {
        let nsText = string as NSString
        guard nsText.length > 0 else { return NSRange(location: 0, length: 0) }

        let safeLocation = min(max(0, location), max(0, nsText.length - 1))
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        var length = lineRange.length
        while length > 0 {
            let character = nsText.character(at: lineRange.location + length - 1)
            guard character == 10 || character == 13 else { break }
            length -= 1
        }

        return NSRange(location: lineRange.location, length: length)
    }

    private func isWordSeparator(before location: Int, in text: NSString) -> Bool {
        guard location > 0 else { return true }
        let range = text.rangeOfComposedCharacterSequence(at: location - 1)
        return isWordSeparator(text.substring(with: range))
    }

    private func isWordSeparator(at location: Int, in text: NSString) -> Bool {
        guard location < text.length else { return true }
        let range = text.rangeOfComposedCharacterSequence(at: location)
        return isWordSeparator(text.substring(with: range))
    }

    private func isWordSeparator(_ character: String) -> Bool {
        character.rangeOfCharacter(from: .alphanumerics) == nil && character != "_"
    }

    private func previousCharacterLocation(before location: Int, in text: NSString) -> Int {
        guard location > 0 else { return 0 }
        return text.rangeOfComposedCharacterSequence(at: location - 1).location
    }

    private func nextCharacterLocation(after location: Int, in text: NSString) -> Int {
        guard location < text.length else { return text.length }
        let range = text.rangeOfComposedCharacterSequence(at: location)
        return min(text.length, range.location + range.length)
    }

    private func addVerticalCursor(direction: Int) -> Bool {
        let cursor = editorSelectionRanges.last ?? NSRange(location: 0, length: 0)
        let location = cursor.location + cursor.length
        guard let currentPoint = caretPoint(for: location),
              let targetLocation = insertionLocation(
                for: NSPoint(
                    x: currentPoint.x,
                    y: currentPoint.y + (direction < 0 ? -editorLineHeight : editorLineHeight)
                )
              ) else {
            return false
        }

        var ranges = editorSelectionRanges
        ranges.append(NSRange(location: targetLocation, length: 0))
        setEditorSelectionRanges(ranges)
        return true
    }

    private func columnRanges(
        from anchorPoint: NSPoint,
        to point: NSPoint,
        createsSelections: Bool
    ) -> [NSRange] {
        let fragments = lineFragmentsBetween(anchorPoint, point)
        guard !fragments.isEmpty else {
            return [NSRange(location: multiCursorDragState?.anchorLocation ?? 0, length: 0)]
        }

        return fragments.compactMap { fragment in
            let y = fragment.midY
            if createsSelections {
                guard let start = insertionLocation(for: NSPoint(x: anchorPoint.x, y: y)),
                      let end = insertionLocation(for: NSPoint(x: point.x, y: y)) else {
                    return nil
                }

                return NSRange(location: min(start, end), length: abs(end - start))
            }

            guard let location = insertionLocation(for: NSPoint(x: anchorPoint.x, y: y)) else {
                return nil
            }

            return NSRange(location: location, length: 0)
        }
    }

    private func lineFragmentsBetween(_ firstPoint: NSPoint, _ secondPoint: NSPoint) -> [NSRect] {
        guard let layoutManager,
              let textContainer else {
            return []
        }

        layoutManager.ensureLayout(for: textContainer)

        let minY = min(firstPoint.y, secondPoint.y)
        let maxY = max(firstPoint.y, secondPoint.y)
        let origin = textContainerOrigin
        var fragments: [NSRect] = []

        if layoutManager.numberOfGlyphs == 0 {
            return [
                NSRect(
                    x: origin.x,
                    y: origin.y,
                    width: visibleRect.width,
                    height: editorLineHeight
                )
            ]
        }

        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { rect, _, _, _, _ in
            let translated = NSRect(
                x: rect.minX + origin.x,
                y: rect.minY + origin.y,
                width: max(rect.width, self.visibleRect.width),
                height: rect.height
            )
            if translated.maxY >= minY, translated.minY <= maxY {
                fragments.append(translated)
            }
        }

        let extraLineRect = layoutManager.extraLineFragmentRect
        if !extraLineRect.isEmpty, extraLineRect.height > 0 {
            let translated = NSRect(
                x: extraLineRect.minX + origin.x,
                y: extraLineRect.minY + origin.y,
                width: max(extraLineRect.width, visibleRect.width),
                height: extraLineRect.height
            )
            if translated.maxY >= minY, translated.minY <= maxY {
                fragments.append(translated)
            }
        }

        return fragments.sorted { $0.minY < $1.minY }
    }

    private func deletionRanges(backward: Bool) -> [NSRange] {
        let nsText = string as NSString
        return normalizedRanges(editorSelectionRanges).compactMap { range in
            if range.length > 0 {
                return range
            }

            if backward {
                guard range.location > 0 else { return nil }
                return nsText.rangeOfComposedCharacterSequence(at: range.location - 1)
            }

            guard range.location < nsText.length else { return nil }
            return nsText.rangeOfComposedCharacterSequence(at: range.location)
        }
    }

    private func insertionLocation(for point: NSPoint) -> Int? {
        guard let layoutManager,
              let textContainer else {
            return nil
        }

        let nsText = string as NSString
        guard nsText.length > 0 else { return 0 }

        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        layoutManager.ensureLayout(for: textContainer)

        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: &fraction
        )
        var characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        if fraction > 0.5, characterIndex < nsText.length {
            characterIndex += 1
        }

        return min(max(0, characterIndex), nsText.length)
    }

    private func caretPoint(for location: Int) -> NSPoint? {
        guard let rect = caretRect(for: location) else { return nil }
        return NSPoint(x: rect.minX, y: rect.midY)
    }

    private func caretRect(for location: Int) -> NSRect? {
        guard let layoutManager,
              let textContainer else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let textLength = (string as NSString).length
        let clampedLocation = min(max(0, location), textLength)
        let origin = textContainerOrigin

        guard textLength > 0, layoutManager.numberOfGlyphs > 0 else {
            return NSRect(x: origin.x, y: origin.y, width: 2, height: editorLineHeight)
        }

        if clampedLocation == textLength, (string as NSString).endsWithLineBreak {
            let extraLineRect = layoutManager.extraLineFragmentRect
            if !extraLineRect.isEmpty {
                return NSRect(
                    x: extraLineRect.minX + origin.x,
                    y: extraLineRect.minY + origin.y,
                    width: 2,
                    height: max(editorLineHeight, extraLineRect.height)
                )
            }
        }

        let characterIndex = min(clampedLocation, textLength - 1)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )

        let isAfterLastCharacter = clampedLocation == textLength
        return NSRect(
            x: (isAfterLastCharacter ? glyphRect.maxX : glyphRect.minX) + origin.x,
            y: lineRect.minY + origin.y,
            width: 2,
            height: max(editorLineHeight, lineRect.height)
        )
    }

    private func normalizedRanges(_ ranges: [NSRange]) -> [NSRange] {
        let textLength = (string as NSString).length
        var seen = Set<String>()

        return ranges.compactMap { range -> NSRange? in
            let location = min(max(0, range.location), textLength)
            let length = min(max(0, range.length), textLength - location)
            let key = "\(location):\(length)"
            guard seen.insert(key).inserted else { return nil }
            return NSRange(location: location, length: length)
        }
        .sorted { $0.location < $1.location }
    }

    private func normalizedSelectionState(
        ranges: [NSRange],
        anchors: [Int]?
    ) -> (ranges: [NSRange], anchors: [Int]?) {
        let textLength = (string as NSString).length
        var seen = Set<String>()

        let states = ranges.enumerated().compactMap { index, range -> (range: NSRange, anchor: Int?)? in
            let location = min(max(0, range.location), textLength)
            let length = min(max(0, range.length), textLength - location)
            let normalizedRange = NSRange(location: location, length: length)
            let key = "\(location):\(length)"
            guard seen.insert(key).inserted else { return nil }

            let anchor = anchors?[safe: index].map { min(max(0, $0), textLength) }
            return (normalizedRange, anchor)
        }
        .sorted { first, second in
            if first.range.location == second.range.location {
                return first.range.length < second.range.length
            }

            return first.range.location < second.range.location
        }

        return (
            ranges: states.map(\.range),
            anchors: anchors == nil ? nil : states.map { $0.anchor ?? $0.range.location }
        )
    }

    private func nonOverlappingEdits(_ edits: [TextEdit]) -> [TextEdit] {
        var previousEnd = -1
        var seen = Set<String>()
        return edits
            .map { edit in
                TextEdit(
                    range: normalizedRanges([edit.range]).first ?? NSRange(location: 0, length: 0),
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

private struct MultiCursorDragState {
    var anchorPoint: NSPoint
    var anchorLocation: Int
    var didDrag = false
}

private struct TextEdit {
    var range: NSRange
    var replacement: String
}

private enum MultiCursorMovement {
    case characterBackward
    case characterForward
    case wordBackward
    case wordForward
    case lineStart
    case lineEnd
    case documentStart
    case documentEnd
    case visualUp
    case visualDown

    var collapsesToStart: Bool {
        switch self {
        case .characterBackward, .wordBackward, .lineStart, .documentStart, .visualUp:
            return true
        case .characterForward, .wordForward, .lineEnd, .documentEnd, .visualDown:
            return false
        }
    }

    var extendsFromStart: Bool {
        !collapsesToStart
    }
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
