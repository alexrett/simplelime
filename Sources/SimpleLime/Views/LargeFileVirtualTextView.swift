import AppKit
import SwiftUI

struct LargeFileVirtualTextView: NSViewRepresentable {
    var fileURL: URL
    var language: EditorLanguage
    var fileSizeBytes: Int64?
    var fontSize: Double
    var targetByteOffset: Int64?
    var contentRevision: TimeInterval
    var onLineActivation: (Int) -> Void
    var onLineReplacementRequest: (Int, String) -> Void
    var onLineInsertionRequest: (Int, String) -> Void
    var onLineDeletionRequest: (Int) -> Void
    var onVisibleLineRangeChange: (ClosedRange<Int>) -> Void

    init(
        fileURL: URL,
        language: EditorLanguage,
        fileSizeBytes: Int64?,
        fontSize: Double,
        targetByteOffset: Int64?,
        contentRevision: TimeInterval = 0,
        onLineActivation: @escaping (Int) -> Void = { _ in },
        onLineReplacementRequest: @escaping (Int, String) -> Void = { _, _ in },
        onLineInsertionRequest: @escaping (Int, String) -> Void = { _, _ in },
        onLineDeletionRequest: @escaping (Int) -> Void = { _ in },
        onVisibleLineRangeChange: @escaping (ClosedRange<Int>) -> Void
    ) {
        self.fileURL = fileURL
        self.language = language
        self.fileSizeBytes = fileSizeBytes
        self.fontSize = fontSize
        self.targetByteOffset = targetByteOffset
        self.contentRevision = contentRevision
        self.onLineActivation = onLineActivation
        self.onLineReplacementRequest = onLineReplacementRequest
        self.onLineInsertionRequest = onLineInsertionRequest
        self.onLineDeletionRequest = onLineDeletionRequest
        self.onVisibleLineRangeChange = onVisibleLineRangeChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true

        let tableView = LargeFileVirtualTableView()
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.gridStyleMask = []
        tableView.backgroundColor = .textBackgroundColor
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.rowHeight = max(20, CGFloat(fontSize) + 8)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        let lineColumn = NSTableColumn(identifier: Coordinator.lineColumnID)
        lineColumn.width = 68
        lineColumn.minWidth = 52
        lineColumn.maxWidth = 96
        tableView.addTableColumn(lineColumn)

        let textColumn = NSTableColumn(identifier: Coordinator.textColumnID)
        textColumn.width = 2_400
        textColumn.minWidth = 800
        tableView.addTableColumn(textColumn)

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        tableView.onBeginInlineEditRow = { [weak coordinator = context.coordinator] row, clickPoint in
            coordinator?.beginInlineEditing(row: row, clickPointInTable: clickPoint)
        }
        tableView.onActivateRow = { [weak coordinator = context.coordinator] row in
            coordinator?.activateLineForEditing(row: row)
        }
        tableView.onDeleteRow = { [weak coordinator = context.coordinator] row in
            coordinator?.requestDeleteLine(row: row)
        }
        tableView.menuProvider = { [weak coordinator = context.coordinator] row in
            coordinator?.menu(forVirtualRow: row)
        }
        context.coordinator.observeVisibleRows()
        context.coordinator.configure(parent: self)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }

        tableView.rowHeight = max(20, CGFloat(fontSize) + 8)
        tableView.backgroundColor = .textBackgroundColor
        scrollView.backgroundColor = .textBackgroundColor
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        if let tableView = tableView as? LargeFileVirtualTableView {
            tableView.onBeginInlineEditRow = { [weak coordinator = context.coordinator] row, clickPoint in
                coordinator?.beginInlineEditing(row: row, clickPointInTable: clickPoint)
            }
            tableView.onActivateRow = { [weak coordinator = context.coordinator] row in
                coordinator?.activateLineForEditing(row: row)
            }
            tableView.onDeleteRow = { [weak coordinator = context.coordinator] row in
                coordinator?.requestDeleteLine(row: row)
            }
            tableView.menuProvider = { [weak coordinator = context.coordinator] row in
                coordinator?.menu(forVirtualRow: row)
            }
        }
        context.coordinator.configure(parent: self)
        context.coordinator.publishVisibleLineRange()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let lineColumnID = NSUserInterfaceItemIdentifier("line")
        static let textColumnID = NSUserInterfaceItemIdentifier("text")

        private var parent: LargeFileVirtualTextView
        private var document: LargeFileVirtualTextDocument?
        private var loadTask: Task<Void, Never>?
        private var prefetchTask: Task<Void, Never>?
        private var loadKey: String?
        private var renderKey: String?
        private var loadingMessage = "Indexing large file..."
        private var errorMessage: String?
        private var attributedLineCache: [Int: NSAttributedString] = [:]
        private var cachedLineOrder: [Int] = []
        private var prefetchRangeInFlight: ClosedRange<Int>?
        private var lastVisibleLineRange: ClosedRange<Int>?
        private var lastAppliedTargetByteOffset: Int64?
        private var inlineEditor: LargeFileInlineLineEditor?
        private(set) var inlineEditingLineNumber: Int?

        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?

        init(_ parent: LargeFileVirtualTextView) {
            self.parent = parent
        }

        deinit {
            loadTask?.cancel()
            prefetchTask?.cancel()
            NotificationCenter.default.removeObserver(self)
        }

        func configure(parent: LargeFileVirtualTextView) {
            self.parent = parent
            let renderKey = "\(parent.language.rawValue)|\(parent.fontSize)"
            if renderKey != self.renderKey {
                self.renderKey = renderKey
                cancelInlineEditing()
                attributedLineCache.removeAll(keepingCapacity: true)
                cachedLineOrder.removeAll(keepingCapacity: true)
                tableView?.reloadData()
            }

            let key = loadKey(for: parent)
            guard key != loadKey else {
                scrollToTargetByteOffsetIfNeeded()
                return
            }

            loadTask?.cancel()
            prefetchTask?.cancel()
            cancelInlineEditing()
            loadKey = key
            document = nil
            attributedLineCache.removeAll(keepingCapacity: true)
            cachedLineOrder.removeAll(keepingCapacity: true)
            prefetchRangeInFlight = nil
            loadingMessage = "Indexing large file..."
            errorMessage = nil
            lastAppliedTargetByteOffset = nil
            tableView?.reloadData()

            let url = parent.fileURL
            loadTask = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    let document = try LargeFileVirtualTextDocument.open(at: url)
                    try Task.checkCancellation()
                    await self?.finishLoad(key: key, document: document)
                } catch is CancellationError {
                } catch {
                    await self?.finishLoadFailure(key: key, error: error)
                }
            }
        }

        private func finishLoad(key: String, document: LargeFileVirtualTextDocument) {
            guard loadKey == key else { return }
            self.document = document
            errorMessage = nil
            loadingMessage = ""
            tableView?.reloadData()
            prefetchLines(around: 1...min(max(1, document.lineCount), 120))
            scrollToTargetByteOffsetIfNeeded()
            publishVisibleLineRange()
        }

        private func finishLoadFailure(key: String, error: Error) {
            guard loadKey == key else { return }
            document = nil
            errorMessage = "Could not index large file: \(error.localizedDescription)"
            tableView?.reloadData()
        }

        func observeVisibleRows() {
            guard let contentView = scrollView?.contentView else { return }
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(visibleBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            document?.lineCount ?? 1
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            let columnID = tableColumn?.identifier ?? Self.textColumnID
            let cell = reusableCell(for: columnID, tableView: tableView)
            let textField = cell.textField

            if let document {
                let lineNumber = row + 1
                if columnID == Self.lineColumnID {
                    textField?.stringValue = "\(lineNumber)"
                    textField?.attributedStringValue = NSAttributedString(string: "\(lineNumber)")
                    textField?.font = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(parent.fontSize), weight: .regular)
                    textField?.textColor = .tertiaryLabelColor
                    textField?.alignment = .right
                } else {
                    textField?.alignment = .left
                    textField?.attributedStringValue = attributedLine(lineNumber, document: document)
                }
            } else {
                if columnID == Self.lineColumnID {
                    textField?.stringValue = ""
                    textField?.attributedStringValue = NSAttributedString(string: "")
                } else {
                    textField?.alignment = .left
                    textField?.stringValue = errorMessage ?? loadingMessage
                    textField?.attributedStringValue = NSAttributedString(
                        string: errorMessage ?? loadingMessage,
                        attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: CGFloat(parent.fontSize), weight: .regular),
                            .foregroundColor: errorMessage == nil ? NSColor.secondaryLabelColor : NSColor.systemRed
                        ]
                    )
                }
            }

            return cell
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
        }

        func beginInlineEditing(row: Int, clickPointInTable: NSPoint? = nil) {
            guard row >= 0,
                  let document,
                  let tableView else {
                return
            }

            let lineNumber = row + 1
            guard lineNumber <= document.lineCount,
                  let lineText = lineText(lineNumber: lineNumber) else {
                return
            }

            let textColumn = tableView.column(withIdentifier: Self.textColumnID)
            guard textColumn != NSNotFound else { return }

            tableView.scrollRowToVisible(row)
            tableView.layoutSubtreeIfNeeded()

            let cellRect = tableView.frameOfCell(atColumn: textColumn, row: row)
            guard !cellRect.isEmpty else { return }

            cancelInlineEditing()

            let editor = LargeFileInlineLineEditor()
            editor.string = lineText
            editor.font = NSFont.monospacedSystemFont(ofSize: CGFloat(parent.fontSize), weight: .regular)
            editor.textColor = .labelColor
            editor.insertionPointColor = .controlAccentColor
            editor.backgroundColor = .textBackgroundColor
            editor.drawsBackground = true
            editor.isRichText = false
            editor.importsGraphics = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isHorizontallyResizable = true
            editor.isVerticallyResizable = false
            editor.textContainer?.widthTracksTextView = false
            editor.textContainer?.heightTracksTextView = true
            editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: cellRect.height)
            editor.textContainerInset = NSSize(width: 4, height: max(1, (cellRect.height - CGFloat(parent.fontSize) - 4) / 2))
            editor.frame = cellRect.insetBy(dx: 8, dy: 2)
            editor.onCommit = { [weak self, weak editor] text in
                guard let self, editor === self.inlineEditor else { return }
                self.commitInlineEditing(replacementText: text)
            }
            editor.onCancel = { [weak self, weak editor] in
                guard let self, editor === self.inlineEditor else { return }
                self.cancelInlineEditing()
            }

            inlineEditingLineNumber = lineNumber
            inlineEditor = editor
            tableView.addSubview(editor)
            tableView.window?.makeFirstResponder(editor)
            if let clickPointInTable {
                let clickPointInEditor = editor.convert(clickPointInTable, from: tableView)
                let caretLocation = LargeFileInlineLineEditor.caretLocation(
                    in: lineText,
                    clickX: clickPointInEditor.x,
                    font: editor.font ?? NSFont.monospacedSystemFont(ofSize: CGFloat(parent.fontSize), weight: .regular),
                    insetWidth: editor.textContainerInset.width
                )
                editor.setSelectedRange(NSRange(location: caretLocation, length: 0))
            } else {
                editor.selectAll(nil)
            }
        }

        func commitInlineEditing(replacementText: String) {
            guard let lineNumber = inlineEditingLineNumber else { return }
            cancelInlineEditing()
            requestReplaceLine(row: lineNumber - 1, replacementText: replacementText)
        }

        func cancelInlineEditing() {
            inlineEditor?.removeFromSuperview()
            inlineEditor = nil
            inlineEditingLineNumber = nil
        }

        func activateLineForEditing(row: Int) {
            guard row >= 0 else { return }
            cancelInlineEditing()
            parent.onLineActivation(row + 1)
        }

        func requestReplaceLine(row: Int, replacementText: String) {
            guard row >= 0,
                  !replacementText.contains(where: { $0 == "\n" || $0 == "\r" }) else {
                return
            }

            parent.onLineReplacementRequest(row + 1, replacementText)
        }

        func requestInsertLine(row: Int, insertedText: String) {
            guard row >= 0,
                  !insertedText.contains(where: { $0 == "\n" || $0 == "\r" }) else {
                return
            }

            parent.onLineInsertionRequest(row + 1, insertedText)
        }

        func requestDeleteLine(row: Int) {
            guard row >= 0 else { return }
            parent.onLineDeletionRequest(row + 1)
        }

        func menu(forVirtualRow row: Int) -> NSMenu? {
            guard row >= 0 else { return nil }

            let lineNumber = row + 1
            let menu = NSMenu()
            menu.addItem(menuItem("Open Editable Chunk", action: #selector(openEditableChunkFromMenu(_:)), lineNumber: lineNumber))
            menu.addItem(.separator())
            menu.addItem(menuItem("Replace Line...", action: #selector(replaceLineFromMenu(_:)), lineNumber: lineNumber))
            menu.addItem(menuItem("Insert Line Before...", action: #selector(insertLineBeforeFromMenu(_:)), lineNumber: lineNumber))
            menu.addItem(menuItem("Delete Line", action: #selector(deleteLineFromMenu(_:)), lineNumber: lineNumber))
            return menu
        }

        private func menuItem(_ title: String, action: Selector, lineNumber: Int) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = lineNumber
            return item
        }

        @objc private func openEditableChunkFromMenu(_ sender: NSMenuItem) {
            guard let lineNumber = sender.representedObject as? Int else { return }
            parent.onLineActivation(lineNumber)
        }

        @objc private func replaceLineFromMenu(_ sender: NSMenuItem) {
            guard let lineNumber = sender.representedObject as? Int else { return }
            promptForLineReplacement(lineNumber: lineNumber)
        }

        @objc private func insertLineBeforeFromMenu(_ sender: NSMenuItem) {
            guard let lineNumber = sender.representedObject as? Int else { return }
            promptForLineInsertion(lineNumber: lineNumber)
        }

        @objc private func deleteLineFromMenu(_ sender: NSMenuItem) {
            guard let lineNumber = sender.representedObject as? Int else { return }
            confirmLineDeletion(lineNumber: lineNumber)
        }

        private func promptForLineReplacement(lineNumber: Int) {
            let alert = NSAlert()
            alert.messageText = "Replace Line \(lineNumber)"
            alert.informativeText = "Rewrite this source line without loading the full file into the editor."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 520, height: 24))
            field.stringValue = lineText(lineNumber: lineNumber) ?? ""
            alert.accessoryView = field

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            requestReplaceLine(row: lineNumber - 1, replacementText: field.stringValue)
        }

        private func promptForLineInsertion(lineNumber: Int) {
            let alert = NSAlert()
            alert.messageText = "Insert Before Line \(lineNumber)"
            alert.informativeText = "Insert one source line without loading the full file into the editor."
            alert.addButton(withTitle: "Insert")
            alert.addButton(withTitle: "Cancel")

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 520, height: 24))
            field.placeholderString = "Inserted text"
            alert.accessoryView = field

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            requestInsertLine(row: lineNumber - 1, insertedText: field.stringValue)
        }

        private func confirmLineDeletion(lineNumber: Int) {
            let alert = NSAlert()
            alert.messageText = "Delete Line \(lineNumber)?"
            alert.informativeText = "This rewrites the source file without loading the full file into the editor."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            requestDeleteLine(row: lineNumber - 1)
        }

        private func lineText(lineNumber: Int) -> String? {
            guard let document else { return nil }
            return try? document.line(lineNumber)?.text
        }

        @objc private func visibleBoundsDidChange(_ notification: Notification) {
            publishVisibleLineRange()
        }

        func publishVisibleLineRange() {
            guard let tableView, document != nil else { return }
            let rows = tableView.rows(in: tableView.visibleRect)
            guard rows.length > 0 else { return }

            let lower = max(1, rows.location + 1)
            let upper = max(lower, rows.location + rows.length)
            let range = lower...upper
            guard range != lastVisibleLineRange else { return }

            lastVisibleLineRange = range
            DispatchQueue.main.async { [parent] in
                parent.onVisibleLineRangeChange(range)
            }
            prefetchLines(around: range)
        }

        private func scrollToTargetByteOffsetIfNeeded() {
            guard let targetByteOffset = parent.targetByteOffset,
                  targetByteOffset != lastAppliedTargetByteOffset,
                  let document,
                  let tableView else {
                return
            }

            do {
                let lineNumber = try document.lineNumber(containingByteOffset: targetByteOffset)
                let row = max(0, min(document.lineCount - 1, lineNumber - 1))
                tableView.scrollRowToVisible(row)
                lastAppliedTargetByteOffset = targetByteOffset
                publishVisibleLineRange()
            } catch {
                errorMessage = "Could not scroll to target: \(error.localizedDescription)"
            }
        }

        private func attributedLine(
            _ lineNumber: Int,
            document: LargeFileVirtualTextDocument
        ) -> NSAttributedString {
            if let cached = attributedLineCache[lineNumber] {
                return cached
            }

            prefetchLines(around: lineNumber...lineNumber)
            return NSAttributedString(
                string: "",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: CGFloat(parent.fontSize), weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        }

        private func remember(_ attributed: NSAttributedString, for lineNumber: Int) {
            let isNewEntry = attributedLineCache[lineNumber] == nil
            attributedLineCache[lineNumber] = attributed
            if isNewEntry {
                cachedLineOrder.append(lineNumber)
            }

            let limit = 2_000
            if cachedLineOrder.count > limit {
                let overflow = cachedLineOrder.count - limit
                for oldLine in cachedLineOrder.prefix(overflow) {
                    attributedLineCache.removeValue(forKey: oldLine)
                }
                cachedLineOrder.removeFirst(overflow)
            }
        }

        private func prefetchLines(around range: ClosedRange<Int>) {
            guard let document else { return }

            let lower = max(1, range.lowerBound - 80)
            let upper = min(document.lineCount, range.upperBound + 160)
            guard lower <= upper else { return }

            let requestedRange = lower...upper
            if requestedRange.allSatisfy({ attributedLineCache[$0] != nil }) {
                return
            }
            if let inFlight = prefetchRangeInFlight,
               inFlight.lowerBound <= requestedRange.lowerBound,
               inFlight.upperBound >= requestedRange.upperBound {
                return
            }

            prefetchTask?.cancel()
            prefetchRangeInFlight = requestedRange

            prefetchTask = Task.detached(priority: .utility) { [weak self, document] in
                do {
                    let lines = try document.lines(in: requestedRange)
                    try Task.checkCancellation()
                    await self?.finishPrefetch(range: requestedRange, lines: lines)
                } catch is CancellationError {
                } catch {
                    await self?.finishPrefetchFailure(range: requestedRange, error: error)
                }
            }
        }

        private func finishPrefetch(
            range: ClosedRange<Int>,
            lines: [LargeFileVirtualLine]
        ) {
            guard prefetchRangeInFlight == range else { return }
            prefetchRangeInFlight = nil

            var changedRows = IndexSet()
            let textColumnIndex = tableView?.column(withIdentifier: Self.textColumnID) ?? NSNotFound
            let visibleRows = tableView?.rows(in: tableView?.visibleRect ?? .zero) ?? NSRange(location: 0, length: 0)

            for line in lines {
                let attributed = SyntaxHighlighter.attributedLine(
                    line.text,
                    language: parent.language,
                    fontSize: CGFloat(parent.fontSize)
                )
                remember(attributed, for: line.number)

                let row = line.number - 1
                if NSLocationInRange(row, visibleRows) {
                    changedRows.insert(row)
                }
            }

            guard textColumnIndex != NSNotFound else {
                tableView?.reloadData()
                return
            }

            if changedRows.isEmpty {
                tableView?.reloadData()
            } else {
                tableView?.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integer: textColumnIndex))
            }
        }

        private func finishPrefetchFailure(range: ClosedRange<Int>, error: Error) {
            guard prefetchRangeInFlight == range else { return }
            prefetchRangeInFlight = nil

            let message = "[SimpleLime: could not read lines \(range.lowerBound)-\(range.upperBound): \(error.localizedDescription)]"
            let attributed = NSAttributedString(
                string: message,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: CGFloat(parent.fontSize), weight: .regular),
                    .foregroundColor: NSColor.systemRed
                ]
            )
            remember(attributed, for: range.lowerBound)
            tableView?.reloadData()
        }

        private func reusableCell(
            for columnID: NSUserInterfaceItemIdentifier,
            tableView: NSTableView
        ) -> NSTableCellView {
            let identifier = NSUserInterfaceItemIdentifier("large-file-\(columnID.rawValue)-cell")
            if let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
                return cell
            }

            let cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isBezeled = false
            textField.drawsBackground = false
            textField.isEditable = false
            textField.isSelectable = false
            textField.refusesFirstResponder = true
            textField.focusRingType = .none
            textField.lineBreakMode = .byClipping
            textField.maximumNumberOfLines = 1
            textField.usesSingleLineMode = true
            textField.allowsDefaultTighteningForTruncation = false

            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: columnID == Self.lineColumnID ? 0 : 10),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: columnID == Self.lineColumnID ? -8 : -12),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

        private func loadKey(for parent: LargeFileVirtualTextView) -> String {
            let size = parent.fileSizeBytes ?? 0
            return "\(parent.fileURL.standardizedFileURL.path)|\(size)|\(parent.contentRevision)"
        }
    }
}

final class LargeFileVirtualTableView: NSTableView {
    var onBeginInlineEditRow: ((Int, NSPoint?) -> Void)?
    var onActivateRow: ((Int) -> Void)?
    var onDeleteRow: ((Int) -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?
    private(set) var focusedVirtualRow: Int?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        window?.makeFirstResponder(self)

        if handleClickedRow(clickedRow, clickCount: event.clickCount, pointInTable: point) {
            return
        }

        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        guard clickedRow >= 0 else { return nil }
        return menuProvider?(clickedRow)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            moveFocusedRow(by: -1)
        case 125:
            moveFocusedRow(by: 1)
        case 36, 76:
            beginEditingFocusedRow()
        case 51, 117:
            deleteFocusedRow()
        default:
            super.keyDown(with: event)
        }
    }

    @discardableResult
    func handleClickedRow(_ clickedRow: Int, clickCount: Int, pointInTable: NSPoint? = nil) -> Bool {
        guard clickedRow >= 0 else { return false }
        focusVirtualRow(clickedRow)
        if clickCount >= 2 {
            onActivateRow?(clickedRow)
        } else {
            onBeginInlineEditRow?(clickedRow, pointInTable)
        }
        return true
    }

    func focusVirtualRow(_ row: Int) {
        guard row >= 0, row < numberOfRows else { return }
        focusedVirtualRow = row
        scrollRowToVisible(row)
    }

    func moveFocusedRow(by delta: Int) {
        guard numberOfRows > 0 else { return }
        let baseRow = focusedVirtualRow ?? firstVisibleRow()
        let nextRow = min(max(0, baseRow + delta), numberOfRows - 1)
        focusVirtualRow(nextRow)
    }

    func beginEditingFocusedRow() {
        guard let focusedVirtualRow else { return }
        onBeginInlineEditRow?(focusedVirtualRow, nil)
    }

    func activateFocusedRow() {
        guard let focusedVirtualRow else { return }
        onActivateRow?(focusedVirtualRow)
    }

    func deleteFocusedRow() {
        guard let focusedVirtualRow else { return }
        onDeleteRow?(focusedVirtualRow)
    }

    private func firstVisibleRow() -> Int {
        let visibleRows = rows(in: visibleRect)
        guard visibleRows.length > 0 else { return 0 }
        return min(max(0, visibleRows.location), max(0, numberOfRows - 1))
    }
}

final class LargeFileInlineLineEditor: NSTextView {
    enum EditingAction {
        case commit
        case cancel
    }

    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    static func caretLocation(
        in text: String,
        clickX: CGFloat,
        font: NSFont,
        insetWidth: CGFloat
    ) -> Int {
        guard !text.isEmpty else { return 0 }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let characterWidth = max(1, ("M" as NSString).size(withAttributes: attributes).width)
        let adjustedX = max(0, clickX - insetWidth)
        let utf16Length = (text as NSString).length
        let candidate = Int((adjustedX / characterWidth).rounded())
        return min(max(0, candidate), utf16Length)
    }

    static func editingAction(
        keyCode: UInt16,
        characters: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> EditingAction? {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandOnly = flags.contains(.command)
            && !flags.contains(.option)
            && !flags.contains(.control)

        if isCommandOnly, keyCode == 1 {
            return .commit
        }
        if isCommandOnly, keyCode == 47 {
            return .cancel
        }

        switch characters {
        case "\r", "\n":
            return .commit
        case "\u{1b}":
            return .cancel
        default:
            return nil
        }
    }

    override func keyDown(with event: NSEvent) {
        let action = Self.editingAction(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers ?? event.characters,
            modifierFlags: event.modifierFlags
        )
        switch action {
        case .commit:
            onCommit?(string)
        case .cancel:
            onCancel?()
        case nil:
            super.keyDown(with: event)
        }
    }
}
