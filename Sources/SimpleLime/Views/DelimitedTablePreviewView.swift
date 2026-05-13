import AppKit
import SwiftUI

struct DelimitedTablePreviewView: View {
    let text: String
    let language: EditorLanguage
    var isLargeFilePreview: Bool = false

    private let measuredRowLimit = 200

    private var table: DelimitedTextTable {
        DelimitedTextTable.parseVisiblePreview(
            tableText,
            delimiter: language.tableDelimiter ?? ",",
            maximumStoredRows: DelimitedTablePreviewConfiguration.maximumRows(),
            maximumStoredColumns: DelimitedTablePreviewConfiguration.maximumColumns()
        )
    }

    private var tableText: String {
        guard isLargeFilePreview else { return text }
        return Self.removingLargeFilePreviewMarker(from: text)
    }

    var body: some View {
        let table = table

        Group {
            if table.rowCount == 0 || table.columnCount == 0 {
                emptyState
            } else {
                tableBody(table)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No table rows")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func tableBody(_ table: DelimitedTextTable) -> some View {
        let window = DelimitedTablePreviewConfiguration.window(
            rowCount: table.rowCount,
            columnCount: table.columnCount
        )
        let widths = columnWidths(for: table, displayedColumnCount: window.displayedColumnCount)

        return VStack(alignment: .leading, spacing: 0) {
            DelimitedTablePreviewRepresentable(
                table: table,
                window: window,
                columnWidths: widths
            )

            if window.hasHiddenRows || window.hasHiddenColumns {
                Text(truncationMessage(for: window, table: table))
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

    static func displayValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    static func removingLargeFilePreviewMarker(from text: String) -> String {
        let markerPrefix = "[SimpleLime large-file preview:"
        guard let markerRange = text.range(of: markerPrefix, options: .backwards) else {
            return text
        }

        var trimmed = String(text[..<markerRange.lowerBound])
        while trimmed.last == "\n" || trimmed.last == "\r" {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func truncationMessage(for window: DelimitedTablePreviewWindow, table: DelimitedTextTable) -> String {
        [
            window.hasHiddenRows ? hiddenCountText(
                exactCount: window.hiddenRowCount,
                noun: "row",
                isExact: table.rowCountIsExact
            ) : nil,
            window.hasHiddenColumns ? hiddenCountText(
                exactCount: window.hiddenColumnCount,
                noun: "column",
                isExact: table.columnCountIsExact
            ) : nil
        ]
        .compactMap { $0 }
        .joined(separator: " and ") + " not rendered"
    }

    private func hiddenCountText(exactCount: Int, noun: String, isExact: Bool) -> String {
        guard isExact else { return "More \(noun)s" }
        return "\(exactCount) more \(noun)\(exactCount == 1 ? "" : "s")"
    }

    private func columnWidths(for table: DelimitedTextTable, displayedColumnCount: Int) -> [CGFloat] {
        guard displayedColumnCount > 0 else { return [] }

        return (0..<displayedColumnCount).map { columnIndex in
            let measuredLength = table.rows
                .prefix(measuredRowLimit)
                .map { row in
                    row.indices.contains(columnIndex)
                        ? Self.displayValue(row[columnIndex]).count
                        : 0
                }
                .max() ?? 0
            let clampedCharacters = min(max(measuredLength, 6), 34)
            return CGFloat(clampedCharacters * 8 + 26)
        }
    }
}

private struct DelimitedTablePreviewRepresentable: NSViewRepresentable {
    let table: DelimitedTextTable
    let window: DelimitedTablePreviewWindow
    let columnWidths: [CGFloat]

    func makeCoordinator() -> Coordinator {
        Coordinator(table: table, window: window, columnWidths: columnWidths)
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
        context.coordinator.update(table: table, window: window, columnWidths: columnWidths)
        context.coordinator.tableView = tableView
        context.coordinator.configureColumns()
        tableView.reloadData()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private static let rowNumberColumnID = NSUserInterfaceItemIdentifier("rowNumber")
        private static let cellID = NSUserInterfaceItemIdentifier("DelimitedTableCell")

        private var table: DelimitedTextTable
        private var window: DelimitedTablePreviewWindow
        private var columnWidths: [CGFloat]
        weak var tableView: NSTableView?

        init(
            table: DelimitedTextTable,
            window: DelimitedTablePreviewWindow,
            columnWidths: [CGFloat]
        ) {
            self.table = table
            self.window = window
            self.columnWidths = columnWidths
        }

        func update(
            table: DelimitedTextTable,
            window: DelimitedTablePreviewWindow,
            columnWidths: [CGFloat]
        ) {
            self.table = table
            self.window = window
            self.columnWidths = columnWidths
        }

        func configureColumns() {
            guard let tableView else { return }

            let expectedIDs = [Self.rowNumberColumnID] + (0..<window.displayedColumnCount).map(columnID)
            if tableView.tableColumns.map(\.identifier) == expectedIDs {
                updateColumnWidths(in: tableView)
                return
            }

            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            let rowColumn = NSTableColumn(identifier: Self.rowNumberColumnID)
            rowColumn.width = 56
            rowColumn.minWidth = 56
            rowColumn.maxWidth = 56
            rowColumn.resizingMask = []
            tableView.addTableColumn(rowColumn)

            for columnIndex in 0..<window.displayedColumnCount {
                let column = NSTableColumn(identifier: columnID(columnIndex))
                column.width = columnWidths.indices.contains(columnIndex) ? columnWidths[columnIndex] : 120
                column.minWidth = 80
                column.maxWidth = 420
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

        private func updateColumnWidths(in tableView: NSTableView) {
            for columnIndex in 0..<window.displayedColumnCount {
                let id = columnID(columnIndex)
                guard let column = tableView.tableColumn(withIdentifier: id),
                      columnWidths.indices.contains(columnIndex) else {
                    continue
                }
                column.width = columnWidths[columnIndex]
            }
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

        private func value(for identifier: NSUserInterfaceItemIdentifier, row: Int) -> String {
            guard identifier != Self.rowNumberColumnID else {
                return "\(row + 1)"
            }

            guard let columnIndex = columnIndex(for: identifier) else { return "" }
            return DelimitedTablePreviewView.displayValue(table.cell(row: row, column: columnIndex))
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
