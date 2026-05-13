import AppKit
import XCTest
@testable import SimpleLime

final class EditorCorePerformanceProbeTests: XCTestCase {
    func testLargeVirtualTextDocumentHeadlessProbeStaysBounded() throws {
        let directoryURL = try makeTemporaryDirectory(named: "SimpleLimeEditorCoreProbeText")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("large-source.jsonl")
        let text = (1...25_000).map { lineNumber in
            #"{"line": \#(lineNumber), "title": "item-\#(lineNumber)", "enabled": \#(lineNumber.isMultiple(of: 2) ? "true" : "false")}"#
        }.joined(separator: "\n")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let openResult = try timed("largeText.index") {
            try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 256)
        }
        let visibleResult = try timed("largeText.visibleLines") {
            try openResult.value.lines(in: 12_480...12_560)
        }

        XCTAssertEqual(openResult.value.lineCount, 25_000)
        XCTAssertEqual(visibleResult.value.count, 81)
        XCTAssertEqual(visibleResult.value.first?.number, 12_480)
        XCTAssertEqual(visibleResult.value.last?.number, 12_560)
        XCTAssertTrue(try XCTUnwrap(visibleResult.value.first?.text).contains(#""line": 12480"#))
        XCTAssertLessThan(openResult.milliseconds, 5_000, "Large text indexing should stay bounded in debug test builds.")
        XCTAssertLessThan(visibleResult.milliseconds, 1_000, "Visible range reads should stay bounded in debug test builds.")

        print(
            editorCoreProbeLine(
                "largeText",
                [
                    "indexMs": openResult.milliseconds,
                    "visibleMs": visibleResult.milliseconds,
                    "lines": Double(openResult.value.lineCount)
                ]
            )
        )
    }

    func testDelimitedVirtualTableHeadlessProbeStaysBounded() throws {
        let directoryURL = try makeTemporaryDirectory(named: "SimpleLimeEditorCoreProbeCSV")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("large-table.csv")
        let header = (0..<27).map { "Column\($0)" }.joined(separator: ",")
        let rows = (1...16_000).map { rowNumber in
            (0..<27).map { column in
                column == 0 ? "row-\(rowNumber)" : "\(rowNumber)-\(column)"
            }.joined(separator: ",")
        }
        try ([header] + rows).joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let openResult = try timed("largeCSV.index") {
            try DelimitedVirtualTableDocument.open(at: fileURL, delimiter: ",")
        }
        let visibleResult = try timed("largeCSV.visibleRows") {
            try openResult.value.rows(in: 8_000...8_040, maximumColumns: 27)
        }

        XCTAssertEqual(openResult.value.rowCount, 16_001)
        XCTAssertEqual(openResult.value.columnCount, 27)
        XCTAssertEqual(visibleResult.value.count, 41)
        XCTAssertEqual(visibleResult.value.first?.number, 8_000)
        XCTAssertEqual(visibleResult.value.first?.cell(0), "row-7999")
        XCTAssertLessThan(openResult.milliseconds, 5_000, "Large CSV indexing should stay bounded in debug test builds.")
        XCTAssertLessThan(visibleResult.milliseconds, 1_000, "Visible CSV row reads should stay bounded in debug test builds.")

        print(
            editorCoreProbeLine(
                "largeCSV",
                [
                    "indexMs": openResult.milliseconds,
                    "visibleMs": visibleResult.milliseconds,
                    "rows": Double(openResult.value.rowCount),
                    "columns": Double(openResult.value.columnCount)
                ]
            )
        )
    }

    func testVisibleSyntaxHighlightingHeadlessProbeStaysBounded() throws {
        let lines = (1...240).map { lineNumber in
            #"{"line": \#(lineNumber), "name": "item-\#(lineNumber)", "active": true, "score": \#(lineNumber * 3)}"#
        }

        let highlightResult = timed("visibleSyntax.jsonLines") {
            lines.map {
                SyntaxHighlighter.attributedLine($0, language: .json, fontSize: 13)
            }
        }

        XCTAssertEqual(highlightResult.value.count, 240)
        XCTAssertTrue(highlightResult.value[199].string.contains(#""line": 200"#))
        XCTAssertLessThan(highlightResult.milliseconds, 1_000, "Visible JSON syntax highlighting should stay bounded in debug test builds.")

        print(
            editorCoreProbeLine(
                "visibleSyntax",
                [
                    "jsonLineHighlightMs": highlightResult.milliseconds,
                    "lines": Double(highlightResult.value.count)
                ]
            )
        )
    }

    private struct TimedValue<T> {
        var value: T
        var milliseconds: Double
    }

    private func timed<T>(_ label: String, _ work: () throws -> T) rethrows -> TimedValue<T> {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try work()
        let end = DispatchTime.now().uptimeNanoseconds
        let milliseconds = Double(end - start) / 1_000_000
        print(editorCoreProbeLine(label, ["ms": milliseconds]))
        return TimedValue(value: value, milliseconds: milliseconds)
    }

    private func makeTemporaryDirectory(named prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func editorCoreProbeLine(_ label: String, _ metrics: [String: Double]) -> String {
        let renderedMetrics = metrics
            .sorted { $0.key < $1.key }
            .map { key, value in
                if value.rounded() == value {
                    return "\(key)=\(Int(value))"
                }
                return "\(key)=\(String(format: "%.2f", value))"
            }
            .joined(separator: " ")
        return "[EditorCoreProbe] \(label) \(renderedMetrics)"
    }
}
