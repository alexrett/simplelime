import XCTest
@testable import SimpleLime

final class DelimitedTextTableTests: XCTestCase {
    func testParsesQuotedCSVFields() {
        let table = DelimitedTextTable.parse(
            "Name,Note\nAlice,\"hello, world\"\nBob,\"quote \"\"inside\"\"\"",
            delimiter: ","
        )

        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 2)
        XCTAssertEqual(table.cell(row: 1, column: 1), "hello, world")
        XCTAssertEqual(table.cell(row: 2, column: 1), "quote \"inside\"")
    }

    func testParsesTSVFields() {
        let table = DelimitedTextTable.parse("Name\tScore\nAlice\t10", delimiter: "\t")

        XCTAssertEqual(table.rows, [["Name", "Score"], ["Alice", "10"]])
        XCTAssertEqual(table.cell(row: 20, column: 0), "")
    }

    func testKeepsQuotedLineBreaksButDoesNotCreateTrailingBlankRow() {
        let table = DelimitedTextTable.parse("Name,Note\nAlice,\"line one\nline two\"\n", delimiter: ",")

        XCTAssertEqual(table.rows, [["Name", "Note"], ["Alice", "line one\nline two"]])
    }

    func testParsesCRLFRowsAsRowsInsteadOfOneWideRow() {
        let table = DelimitedTextTable.parse("A,B\r\n1,2\r\n3,4\r\n", delimiter: ",")

        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 2)
        XCTAssertEqual(table.rows, [["A", "B"], ["1", "2"], ["3", "4"]])
    }

    func testPreservesTrailingEmptyField() {
        let table = DelimitedTextTable.parse("a,b,", delimiter: ",")

        XCTAssertEqual(table.rows, [["a", "b", ""]])
    }

    func testPreviewWindowCapsLargeTablesByRowsAndColumns() {
        let window = DelimitedTablePreviewWindow(rowCount: 60_000, columnCount: 300)

        XCTAssertEqual(window.displayedColumnCount, DelimitedTablePreviewWindow.maximumColumns)
        XCTAssertEqual(window.displayedRowCount, DelimitedTablePreviewWindow.maximumRows)
        XCTAssertEqual(window.hiddenColumnCount, 236)
        XCTAssertEqual(window.hiddenRowCount, 10_000)
    }

    func testPreviewWindowUsesConfiguredCaps() throws {
        let defaults = try makeDefaults()
        defaults.set(1_500, forKey: DelimitedTablePreviewConfiguration.maximumRowsDefaultsKey)
        defaults.set(12, forKey: DelimitedTablePreviewConfiguration.maximumColumnsDefaultsKey)

        let window = DelimitedTablePreviewConfiguration.window(
            rowCount: 2_000,
            columnCount: 30,
            defaults: defaults
        )

        XCTAssertEqual(window.displayedRowCount, 1_500)
        XCTAssertEqual(window.displayedColumnCount, 12)
        XCTAssertEqual(window.hiddenRowCount, 500)
        XCTAssertEqual(window.hiddenColumnCount, 18)
    }

    func testPreviewConfigurationClampsOutOfRangeCaps() throws {
        let defaults = try makeDefaults()
        defaults.set(1, forKey: DelimitedTablePreviewConfiguration.maximumRowsDefaultsKey)
        defaults.set(1_000, forKey: DelimitedTablePreviewConfiguration.maximumColumnsDefaultsKey)

        XCTAssertEqual(DelimitedTablePreviewConfiguration.maximumRows(defaults: defaults), 500)
        XCTAssertEqual(DelimitedTablePreviewConfiguration.maximumColumns(defaults: defaults), 256)
    }

    func testPreviewWindowKeepsSmallTablesFullyVisible() {
        let window = DelimitedTablePreviewWindow(rowCount: 12, columnCount: 4)

        XCTAssertEqual(window.displayedRowCount, 12)
        XCTAssertEqual(window.displayedColumnCount, 4)
        XCTAssertFalse(window.hasHiddenRows)
        XCTAssertFalse(window.hasHiddenColumns)
    }

    func testLargeFilePreviewMarkerIsNotParsedAsTableRow() {
        let text = """
        A,B
        1,2

        [SimpleLime large-file preview: showing 64 KB from 0 bytes-64 KB of 6 MB. Use the status-bar arrows to page through the file. Saving is disabled to avoid overwriting the full file.]
        """

        let cleaned = DelimitedTablePreviewView.removingLargeFilePreviewMarker(from: text)
        let table = DelimitedTextTable.parse(cleaned, delimiter: ",")

        XCTAssertEqual(table.rowCount, 2)
        XCTAssertEqual(table.columnCount, 2)
        XCTAssertEqual(table.cell(row: 1, column: 1), "2")
    }

    func testParsesGeneratedSixteenThousandRowCSVWithoutColumnExplosion() {
        let header = (0..<27).map { "Column\($0)" }.joined(separator: ",")
        let body = (0..<16_738).map { row in
            (0..<27).map { column in "\(row)-\(column)" }.joined(separator: ",")
        }
        let table = DelimitedTextTable.parse(([header] + body).joined(separator: "\n"), delimiter: ",")

        XCTAssertEqual(table.rowCount, 16_739)
        XCTAssertEqual(table.columnCount, 27)
        XCTAssertEqual(table.cell(row: 16_738, column: 26), "16737-26")
    }

    func testPreviewParserCountsWholeCSVButStoresOnlyRenderedWindow() {
        let header = (0..<27).map { "Column\($0)" }.joined(separator: ",")
        let body = (0..<16_738).map { row in
            (0..<27).map { column in "\(row)-\(column)" }.joined(separator: ",")
        }

        let table = DelimitedTextTable.parsePreview(
            ([header] + body).joined(separator: "\n"),
            delimiter: ",",
            maximumStoredRows: 12,
            maximumStoredColumns: 6
        )

        XCTAssertEqual(table.rowCount, 16_739)
        XCTAssertEqual(table.columnCount, 27)
        XCTAssertEqual(table.rows.count, 12)
        XCTAssertEqual(table.rows.first?.count, 6)
        XCTAssertEqual(table.cell(row: 11, column: 5), "10-5")
        XCTAssertEqual(table.cell(row: 12, column: 0), "")
        XCTAssertEqual(table.cell(row: 0, column: 6), "")
    }

    func testVisiblePreviewParserStopsAfterStoredWindow() {
        let header = (0..<27).map { "Column\($0)" }.joined(separator: ",")
        let body = (0..<16_738).map { row in
            (0..<27).map { column in "\(row)-\(column)" }.joined(separator: ",")
        }

        let table = DelimitedTextTable.parseVisiblePreview(
            ([header] + body).joined(separator: "\n"),
            delimiter: ",",
            maximumStoredRows: 12,
            maximumStoredColumns: 6
        )

        XCTAssertEqual(table.rows.count, 12)
        XCTAssertEqual(table.rows.first?.count, 6)
        XCTAssertGreaterThan(table.rowCount, 12)
        XCTAssertGreaterThan(table.columnCount, 6)
        XCTAssertFalse(table.rowCountIsExact)
        XCTAssertFalse(table.columnCountIsExact)
        XCTAssertEqual(table.cell(row: 11, column: 5), "10-5")
        XCTAssertEqual(table.cell(row: 12, column: 0), "")
        XCTAssertEqual(table.cell(row: 0, column: 6), "")
    }

    func testProvidedBuyersPlanCSVParsesAsRowsWhenPresent() throws {
        let url = URL(fileURLWithPath: "/Users/malikov/Downloads/[O][Buyers] plan - API RUN V2.csv")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Local buyers-plan CSV fixture is not available.")
        }

        let text = try String(contentsOf: url)
        let table = DelimitedTextTable.parse(text, delimiter: ",")

        XCTAssertGreaterThan(table.rowCount, 16_000)
        XCTAssertEqual(table.columnCount, 27)
        XCTAssertEqual(table.cell(row: 0, column: 0), "Keybin")
        XCTAssertEqual(table.cell(row: 0, column: 26), "On/Off")
    }

    func testProvidedBuyersPlanCSVPreviewParserAvoidsMaterializingAllRowsWhenPresent() throws {
        let url = URL(fileURLWithPath: "/Users/malikov/Downloads/[O][Buyers] plan - API RUN V2.csv")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Local buyers-plan CSV fixture is not available.")
        }

        let text = try String(contentsOf: url)
        let table = DelimitedTextTable.parsePreview(
            text,
            delimiter: ",",
            maximumStoredRows: 100,
            maximumStoredColumns: 8
        )

        XCTAssertGreaterThan(table.rowCount, 16_000)
        XCTAssertEqual(table.columnCount, 27)
        XCTAssertEqual(table.rows.count, 100)
        XCTAssertEqual(table.rows.first?.count, 8)
        XCTAssertEqual(table.cell(row: 0, column: 0), "Keybin")
        XCTAssertEqual(table.cell(row: 0, column: 8), "")
    }

    func testProvidedBuyersPlanCSVVisiblePreviewDoesNotMaterializeAllRowsWhenPresent() throws {
        let url = URL(fileURLWithPath: "/Users/malikov/Downloads/[O][Buyers] plan - API RUN V2.csv")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Local buyers-plan CSV fixture is not available.")
        }

        let text = try String(contentsOf: url)
        let table = DelimitedTextTable.parseVisiblePreview(
            text,
            delimiter: ",",
            maximumStoredRows: 100,
            maximumStoredColumns: 8
        )

        XCTAssertGreaterThan(table.rowCount, 100)
        XCTAssertEqual(table.columnCount, 27)
        XCTAssertEqual(table.rows.count, 100)
        XCTAssertEqual(table.rows.first?.count, 8)
        XCTAssertEqual(table.cell(row: 0, column: 0), "Keybin")
        XCTAssertEqual(table.cell(row: 0, column: 8), "")
        XCTAssertFalse(table.rowCountIsExact)
        XCTAssertFalse(table.columnCountIsExact)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SimpleLimeDelimitedTextTableTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
