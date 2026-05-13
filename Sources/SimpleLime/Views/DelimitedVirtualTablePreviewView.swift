import AppKit
import SwiftUI

struct DelimitedVirtualTablePreviewView: View {
    let fileURL: URL
    let language: EditorLanguage

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case loaded(DelimitedVirtualTableDocument)
        case failed(String)
    }

    private var delimiter: Character {
        language.tableDelimiter ?? ","
    }

    private var loadKey: String {
        [
            fileURL.path,
            String(delimiter),
            "\(DelimitedTablePreviewConfiguration.maximumRows())",
            "\(DelimitedTablePreviewConfiguration.maximumColumns())"
        ].joined(separator: "\u{1f}")
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                statusView("Loading table...")
            case .failed(let message):
                statusView(message)
            case .loaded(let document):
                if document.rowCount == 0 || document.columnCount == 0 {
                    statusView("No table rows")
                } else {
                    tableBody(document)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: loadKey) {
            await loadDocument()
        }
    }

    private func tableBody(_ document: DelimitedVirtualTableDocument) -> some View {
        let window = DelimitedTablePreviewConfiguration.window(
            rowCount: document.rowCount,
            columnCount: document.columnCount
        )

        return VStack(alignment: .leading, spacing: 0) {
            DelimitedVirtualTableRepresentable(
                document: document,
                window: window
            )

            if window.hasHiddenRows || window.hasHiddenColumns {
                Text(truncationMessage(for: window))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statusView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "tablecells")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func loadDocument() async {
        await MainActor.run {
            phase = .loading
        }

        do {
            let delimiter = delimiter
            let fileURL = fileURL
            let document = try await Task.detached(priority: .userInitiated) {
                try DelimitedVirtualTableDocument.open(at: fileURL, delimiter: delimiter)
            }.value
            try Task.checkCancellation()
            await MainActor.run {
                phase = .loaded(document)
            }
        } catch is CancellationError {
            return
        } catch {
            await MainActor.run {
                phase = .failed("Could not load table: \(error.localizedDescription)")
            }
        }
    }

    private func truncationMessage(for window: DelimitedTablePreviewWindow) -> String {
        [
            window.hasHiddenRows ? "\(window.hiddenRowCount) more row\(window.hiddenRowCount == 1 ? "" : "s")" : nil,
            window.hasHiddenColumns ? "\(window.hiddenColumnCount) more column\(window.hiddenColumnCount == 1 ? "" : "s")" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " and ") + " not rendered"
    }
}

private struct DelimitedVirtualTableRepresentable: NSViewRepresentable {
    let document: DelimitedVirtualTableDocument
    let window: DelimitedTablePreviewWindow

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, window: window)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.backgroundColor = .textBackgroundColor
        tableView.allowsColumnResizing = true

        let scrollView = NSScrollView()
        scrollView.contentView = TopAlignedClipView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder

        context.coordinator.tableView = tableView
        context.coordinator.configureColumns()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.update(document: document, window: window)
        context.coordinator.tableView = tableView
        context.coordinator.configureColumns()
        tableView.reloadData()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private static let rowNumberColumnID = NSUserInterfaceItemIdentifier("rowNumber")
        private static let cellID = NSUserInterfaceItemIdentifier("DelimitedVirtualTableCell")

        private var document: DelimitedVirtualTableDocument
        private var window: DelimitedTablePreviewWindow
        private var rowCache: [Int: DelimitedVirtualTableRow] = [:]
        weak var tableView: NSTableView?

        init(document: DelimitedVirtualTableDocument, window: DelimitedTablePreviewWindow) {
            self.document = document
            self.window = window
        }

        func update(document: DelimitedVirtualTableDocument, window: DelimitedTablePreviewWindow) {
            if self.document != document || self.window != window {
                rowCache.removeAll(keepingCapacity: true)
            }
            self.document = document
            self.window = window
        }

        func configureColumns() {
            guard let tableView else { return }

            let expectedIDs = [Self.rowNumberColumnID] + (0..<window.displayedColumnCount).map(columnID)
            if tableView.tableColumns.map(\.identifier) == expectedIDs {
                return
            }

            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            let rowColumn = NSTableColumn(identifier: Self.rowNumberColumnID)
            rowColumn.width = 64
            rowColumn.minWidth = 64
            rowColumn.maxWidth = 64
            rowColumn.resizingMask = []
            tableView.addTableColumn(rowColumn)

            for columnIndex in 0..<window.displayedColumnCount {
                let column = NSTableColumn(identifier: columnID(columnIndex))
                column.width = defaultWidth(for: columnIndex)
                column.minWidth = 80
                column.maxWidth = 460
                column.resizingMask = .userResizingMask
                tableView.addTableColumn(column)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            window.displayedRowCount
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let tableColumn else { return nil }

            let cellView = tableView.makeView(withIdentifier: Self.cellID, owner: self) as? NSTableCellView
                ?? makeCellView()
            let textField = cellView.textField
            textField?.font = NSFont.monospacedSystemFont(
                ofSize: 12,
                weight: row == 0 ? .semibold : .regular
            )
            textField?.textColor = tableColumn.identifier == Self.rowNumberColumnID
                ? .secondaryLabelColor
                : .labelColor
            textField?.alignment = tableColumn.identifier == Self.rowNumberColumnID ? .right : .left
            textField?.stringValue = value(for: tableColumn.identifier, row: row)
            return cellView
        }

        private func makeCellView() -> NSTableCellView {
            let cellView = NSTableCellView()
            cellView.identifier = Self.cellID

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 1
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            cellView.textField = textField
            cellView.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])

            return cellView
        }

        private func value(for identifier: NSUserInterfaceItemIdentifier, row rowIndex: Int) -> String {
            guard identifier != Self.rowNumberColumnID else {
                return "\(rowIndex + 1)"
            }

            guard let columnIndex = columnIndex(for: identifier) else { return "" }
            return DelimitedTablePreviewView.displayValue(row(at: rowIndex).cell(columnIndex))
        }

        private func row(at zeroBasedRow: Int) -> DelimitedVirtualTableRow {
            if let cached = rowCache[zeroBasedRow] {
                return cached
            }

            let loaded = (try? document.row(
                zeroBasedRow + 1,
                maximumColumns: window.displayedColumnCount
            )) ?? DelimitedVirtualTableRow(
                number: zeroBasedRow + 1,
                cells: [],
                byteOffset: 0,
                byteCount: 0,
                isTruncated: false
            )
            rowCache[zeroBasedRow] = loaded
            if rowCache.count > 2_000, let oldestKey = rowCache.keys.min() {
                rowCache.removeValue(forKey: oldestKey)
            }
            return loaded
        }

        private func defaultWidth(for columnIndex: Int) -> CGFloat {
            guard let header = try? document.row(1, maximumColumns: window.displayedColumnCount) else {
                return 140
            }

            let measuredLength = header.cells.indices.contains(columnIndex)
                ? DelimitedTablePreviewView.displayValue(header.cells[columnIndex]).count
                : 0
            let clampedCharacters = min(max(measuredLength, 8), 36)
            return CGFloat(clampedCharacters * 8 + 28)
        }

        private func columnID(_ index: Int) -> NSUserInterfaceItemIdentifier {
            NSUserInterfaceItemIdentifier("column-\(index)")
        }

        private func columnIndex(for identifier: NSUserInterfaceItemIdentifier) -> Int? {
            let raw = identifier.rawValue
            guard raw.hasPrefix("column-") else { return nil }
            return Int(raw.dropFirst("column-".count))
        }
    }
}
