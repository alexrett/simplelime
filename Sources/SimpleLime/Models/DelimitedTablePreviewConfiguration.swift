import Foundation

enum DelimitedTablePreviewConfiguration {
    static let maximumRowsDefaultsKey = "preview.table.maximumRows"
    static let maximumColumnsDefaultsKey = "preview.table.maximumColumns"
    static let defaultMaximumRows = 50_000
    static let defaultMaximumColumns = 64

    static func maximumRows(defaults: UserDefaults = .standard) -> Int {
        clampedMaximumRows(defaults.object(forKey: maximumRowsDefaultsKey) as? Int ?? defaultMaximumRows)
    }

    static func maximumColumns(defaults: UserDefaults = .standard) -> Int {
        clampedMaximumColumns(defaults.object(forKey: maximumColumnsDefaultsKey) as? Int ?? defaultMaximumColumns)
    }

    static func window(
        rowCount: Int,
        columnCount: Int,
        defaults: UserDefaults = .standard
    ) -> DelimitedTablePreviewWindow {
        DelimitedTablePreviewWindow(
            rowCount: rowCount,
            columnCount: columnCount,
            maximumRows: maximumRows(defaults: defaults),
            maximumColumns: maximumColumns(defaults: defaults)
        )
    }

    static func clampedMaximumRows(_ value: Int) -> Int {
        min(max(value, 500), 100_000)
    }

    static func clampedMaximumColumns(_ value: Int) -> Int {
        min(max(value, 4), 256)
    }
}

struct DelimitedTablePreviewWindow: Equatable {
    static let maximumRows = DelimitedTablePreviewConfiguration.defaultMaximumRows
    static let maximumColumns = DelimitedTablePreviewConfiguration.defaultMaximumColumns

    let rowCount: Int
    let columnCount: Int
    let maximumRows: Int
    let maximumColumns: Int

    init(
        rowCount: Int,
        columnCount: Int,
        maximumRows: Int = DelimitedTablePreviewConfiguration.defaultMaximumRows,
        maximumColumns: Int = DelimitedTablePreviewConfiguration.defaultMaximumColumns
    ) {
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.maximumRows = DelimitedTablePreviewConfiguration.clampedMaximumRows(maximumRows)
        self.maximumColumns = DelimitedTablePreviewConfiguration.clampedMaximumColumns(maximumColumns)
    }

    var displayedColumnCount: Int {
        min(max(columnCount, 0), maximumColumns)
    }

    var displayedRowCount: Int {
        min(max(rowCount, 0), maximumRows)
    }

    var hiddenRowCount: Int {
        max(0, rowCount - displayedRowCount)
    }

    var hiddenColumnCount: Int {
        max(0, columnCount - displayedColumnCount)
    }

    var hasHiddenRows: Bool {
        hiddenRowCount > 0
    }

    var hasHiddenColumns: Bool {
        hiddenColumnCount > 0
    }
}
