import Foundation

struct DelimitedTextTable: Equatable {
    let rows: [[String]]
    let delimiter: Character
    private let totalRowCount: Int?
    private let totalColumnCount: Int?
    let rowCountIsExact: Bool
    let columnCountIsExact: Bool

    init(
        rows: [[String]],
        delimiter: Character,
        totalRowCount: Int? = nil,
        totalColumnCount: Int? = nil,
        rowCountIsExact: Bool = true,
        columnCountIsExact: Bool = true
    ) {
        self.rows = rows
        self.delimiter = delimiter
        self.totalRowCount = totalRowCount
        self.totalColumnCount = totalColumnCount
        self.rowCountIsExact = rowCountIsExact
        self.columnCountIsExact = columnCountIsExact
    }

    var rowCount: Int {
        totalRowCount ?? rows.count
    }

    var columnCount: Int {
        totalColumnCount ?? rows.map(\.count).max() ?? 0
    }

    func cell(row: Int, column: Int) -> String {
        guard rows.indices.contains(row),
              rows[row].indices.contains(column) else {
            return ""
        }

        return rows[row][column]
    }

    static func parse(_ text: String, delimiter: Character) -> DelimitedTextTable {
        parse(text, delimiter: delimiter, maximumStoredRows: nil, maximumStoredColumns: nil)
    }

    static func parsePreview(
        _ text: String,
        delimiter: Character,
        maximumStoredRows: Int,
        maximumStoredColumns: Int
    ) -> DelimitedTextTable {
        parse(
            text,
            delimiter: delimiter,
            maximumStoredRows: max(0, maximumStoredRows),
            maximumStoredColumns: max(0, maximumStoredColumns),
            stopAfterStoredWindow: false
        )
    }

    static func parseVisiblePreview(
        _ text: String,
        delimiter: Character,
        maximumStoredRows: Int,
        maximumStoredColumns: Int
    ) -> DelimitedTextTable {
        parse(
            text,
            delimiter: delimiter,
            maximumStoredRows: max(0, maximumStoredRows),
            maximumStoredColumns: max(0, maximumStoredColumns),
            stopAfterStoredWindow: true
        )
    }

    private static func parse(
        _ text: String,
        delimiter: Character,
        maximumStoredRows: Int?,
        maximumStoredColumns: Int?,
        stopAfterStoredWindow: Bool = false
    ) -> DelimitedTextTable {
        guard !text.isEmpty else {
            return DelimitedTextTable(
                rows: [],
                delimiter: delimiter,
                totalRowCount: maximumStoredRows == nil ? nil : 0,
                totalColumnCount: maximumStoredColumns == nil ? nil : 0
            )
        }

        let rowLimit = maximumStoredRows ?? Int.max
        let columnLimit = maximumStoredColumns ?? Int.max
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var fieldCount = 0
        var totalRowCount = 0
        var totalColumnCount = 0
        var isInsideQuotedField = false
        var fieldStarted = false
        var index = text.startIndex
        var stoppedAfterStoredWindow = false

        func shouldCaptureField() -> Bool {
            rows.count < rowLimit && fieldCount < columnLimit
        }

        func appendToField(_ character: Character) {
            if shouldCaptureField() {
                field.append(character)
            }
        }

        func finishField() {
            if shouldCaptureField() {
                row.append(field)
            }
            field = ""
            fieldStarted = false
            fieldCount += 1
        }

        func finishRow() {
            finishField()
            totalRowCount += 1
            totalColumnCount = max(totalColumnCount, fieldCount)
            if rows.count < rowLimit {
                rows.append(row)
            }
            row = []
            fieldCount = 0
        }

        func shouldStopAfterStoredWindow() -> Bool {
            stopAfterStoredWindow && maximumStoredRows != nil && totalRowCount > rowLimit
        }

        while index < text.endIndex {
            let character = text[index]

            if isInsideQuotedField {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        appendToField("\"")
                        index = next
                    } else {
                        isInsideQuotedField = false
                    }
                } else {
                    appendToField(character)
                }
            } else if character == "\"" && !fieldStarted {
                isInsideQuotedField = true
                fieldStarted = true
            } else if character == delimiter {
                finishField()
            } else if character.isNewline {
                finishRow()
                if shouldStopAfterStoredWindow() {
                    stoppedAfterStoredWindow = true
                    break
                }
            } else {
                appendToField(character)
                fieldStarted = true
            }

            index = text.index(after: index)
        }

        if !stoppedAfterStoredWindow,
           fieldStarted || !field.isEmpty || !row.isEmpty || fieldCount > 0 || text.last == delimiter {
            finishField()
            totalRowCount += 1
            totalColumnCount = max(totalColumnCount, fieldCount)
            if rows.count < rowLimit {
                rows.append(row)
            }
        }

        return DelimitedTextTable(
            rows: rows,
            delimiter: delimiter,
            totalRowCount: maximumStoredRows == nil ? nil : totalRowCount,
            totalColumnCount: maximumStoredColumns == nil ? nil : totalColumnCount,
            rowCountIsExact: !stoppedAfterStoredWindow,
            columnCountIsExact: !stoppedAfterStoredWindow
        )
    }
}
