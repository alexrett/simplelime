import XCTest
@testable import SimpleLime

final class DelimitedVirtualTableDocumentTests: XCTestCase {
    func testVirtualCSVIndexesGeneratedSixteenThousandRowsAndReadsLastRow() throws {
        let url = try makeTemporaryCSV()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try DelimitedVirtualTableDocument.open(at: url, delimiter: ",")

        XCTAssertEqual(document.rowCount, 16_739)
        XCTAssertEqual(document.columnCount, 27)
        XCTAssertEqual(try document.row(1, maximumColumns: 27)?.cell(0), "Column0")
        XCTAssertEqual(try document.row(16_739, maximumColumns: 27)?.cell(26), "16737-26")
    }

    func testProvidedBuyersPlanCSVVirtualizesFullFileWhenPresent() throws {
        let url = URL(fileURLWithPath: "/Users/malikov/Downloads/[O][Buyers] plan - API RUN V2.csv")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Local buyers-plan CSV fixture is not available.")
        }

        let document = try DelimitedVirtualTableDocument.open(at: url, delimiter: ",")

        XCTAssertGreaterThan(document.rowCount, 16_000)
        XCTAssertEqual(document.columnCount, 27)
        XCTAssertEqual(try document.row(1, maximumColumns: 27)?.cell(0), "Keybin")
        XCTAssertEqual(try document.row(1, maximumColumns: 27)?.cell(26), "On/Off")
        XCTAssertFalse(try XCTUnwrap(document.row(16_000, maximumColumns: 27)).cells.isEmpty)
    }

    func testVirtualCSVHandlesQuotedLineBreaksAndEscapedQuotes() throws {
        let url = try writeTemporaryFile(
            "Name,Note\nAlice,\"line one\nline two\"\nBob,\"quote \"\"inside\"\"\"\n"
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try DelimitedVirtualTableDocument.open(at: url, delimiter: ",")

        XCTAssertEqual(document.rowCount, 3)
        XCTAssertEqual(document.columnCount, 2)
        XCTAssertEqual(try document.row(2, maximumColumns: 2)?.cell(1), "line one\nline two")
        XCTAssertEqual(try document.row(3, maximumColumns: 2)?.cell(1), #"quote "inside""#)
    }

    func testVirtualCSVDoesNotCreateExtraRowForSingleTrailingNewline() throws {
        let url = try writeTemporaryFile("A,B\n1,2\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try DelimitedVirtualTableDocument.open(at: url, delimiter: ",")

        XCTAssertEqual(document.rowCount, 2)
        XCTAssertEqual(document.columnCount, 2)
        XCTAssertEqual(try document.row(2, maximumColumns: 2)?.cell(1), "2")
    }

    func testVirtualTSVReadsCellsWithTabDelimiter() throws {
        let url = try writeTemporaryFile("Name\tScore\nAlice\t10\nBob\t20")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try DelimitedVirtualTableDocument.open(at: url, delimiter: "\t")

        XCTAssertEqual(document.rowCount, 3)
        XCTAssertEqual(document.columnCount, 2)
        XCTAssertEqual(try document.row(3, maximumColumns: 2)?.cell(0), "Bob")
        XCTAssertEqual(try document.row(3, maximumColumns: 2)?.cell(1), "20")
    }

    private func makeTemporaryCSV() throws -> URL {
        let header = (0..<27).map { "Column\($0)" }.joined(separator: ",")
        let body = (0..<16_738).map { row in
            (0..<27).map { column in "\(row)-\(column)" }.joined(separator: ",")
        }
        return try writeTemporaryFile(([header] + body).joined(separator: "\n"))
    }

    private func writeTemporaryFile(_ text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleLimeDelimitedVirtualTable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
