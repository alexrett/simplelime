import AppKit
import XCTest
@testable import SimpleLime

final class LargeFileVirtualTextDocumentTests: XCTestCase {
    func testVirtualDocumentReadsLinesFarBeyondInitialPreviewWindow() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("large.json")
        let lines = (1...1_500).map { lineNumber in
            #"{"line": \#(lineNumber), "value": "row-\#(lineNumber)"}"#
        }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 64)

        XCTAssertEqual(document.lineCount, 1_500)
        XCTAssertEqual(try document.line(1)?.text, #"{"line": 1, "value": "row-1"}"#)
        XCTAssertEqual(try document.line(1_250)?.text, #"{"line": 1250, "value": "row-1250"}"#)
        XCTAssertEqual(try document.lineNumber(containingByteOffset: try XCTUnwrap(document.line(1_250)?.byteOffset)), 1_250)
    }

    func testProvidedOpenAPIFileIndexesFullDocumentWhenPresent() throws {
        let fileURL = URL(fileURLWithPath: "/Users/malikov/Downloads/openapi.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("openapi.json fixture is not present")
        }

        let document = try LargeFileVirtualTextDocument.open(at: fileURL)

        XCTAssertGreaterThan(document.lineCount, 20_000)
        XCTAssertNotNil(try document.line(1))
        XCTAssertNotNil(try document.line(document.lineCount))
        XCTAssertFalse(try XCTUnwrap(document.line(1)?.text).contains("SimpleLime large-file preview"))
    }

    func testVirtualDocumentReadsVisibleLineBatchWithSingleRange() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("batch.json")
        let lines = (1...300).map { lineNumber in
            #"{"line": \#(lineNumber), "value": "row-\#(lineNumber)"}"#
        }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 32)
        let visibleLines = try document.lines(in: 120...145)

        XCTAssertEqual(visibleLines.count, 26)
        XCTAssertEqual(visibleLines.first?.number, 120)
        XCTAssertEqual(visibleLines.first?.text, #"{"line": 120, "value": "row-120"}"#)
        XCTAssertEqual(visibleLines.last?.number, 145)
        XCTAssertEqual(visibleLines.last?.text, #"{"line": 145, "value": "row-145"}"#)
        XCTAssertEqual(try document.lineNumber(containingByteOffset: try XCTUnwrap(visibleLines.last?.byteOffset)), 145)
    }

    func testVirtualDocumentReplacesLineWithoutLoadingWholeFile() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("editable-lines.json")
        let lines = (1...2_000).map { lineNumber in
            #"{"line": \#(lineNumber), "value": "row-\#(lineNumber)"}"#
        }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 64)
        let originalSize = document.fileSizeBytes
        let originalLine = try XCTUnwrap(document.line(1_500))
        let result = try document.replacingLine(
            1_500,
            with: #"{"line": 1500, "value": "edited"}"#
        )
        let reopened = try LargeFileVirtualTextDocument.open(at: fileURL, cachedIndex: result.index)

        XCTAssertEqual(result.lineNumber, 1_500)
        XCTAssertEqual(result.byteOffset, originalLine.byteOffset)
        XCTAssertEqual(result.oldByteCount, originalLine.byteCount)
        XCTAssertNotEqual(result.fileSizeBytes, originalSize)
        XCTAssertEqual(reopened.index, result.index)
        XCTAssertEqual(try reopened.line(1_499)?.text, #"{"line": 1499, "value": "row-1499"}"#)
        XCTAssertEqual(try reopened.line(1_500)?.text, #"{"line": 1500, "value": "edited"}"#)
        XCTAssertEqual(try reopened.line(1_501)?.text, #"{"line": 1501, "value": "row-1501"}"#)
    }

    func testVirtualDocumentLineReplacePreservesCRLFLineEndings() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("crlf.txt")
        try "one\r\ntwo\r\nthree".write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 1)
        _ = try document.replacingLine(2, with: "TWO\n")

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "one\r\nTWO\r\nthree")
    }

    func testVirtualDocumentLineReplaceRejectsMultiLineReplacement() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("single-line.txt")
        try "one\ntwo\nthree".write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 1)

        XCTAssertThrowsError(try document.replacingLine(2, with: "two\nextra")) { error in
            XCTAssertEqual(error as? LargeFileVirtualEditError, .replacementContainsLineBreak)
        }
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "one\ntwo\nthree")
    }

    func testVirtualDocumentReplacesLineRangeWithMultiLineBlockWithoutLoadingWholeFile() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("replace-range.txt")
        let lines = (1...2_000).map { "line-\($0)" }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 64)
        let firstEditedLine = try XCTUnwrap(document.line(1_200))
        let result = try document.replacingLines(
            1_200...1_202,
            with: "edited-a\nedited-b\n"
        )
        let reopened = try LargeFileVirtualTextDocument.open(at: fileURL, cachedIndex: result.index)

        XCTAssertEqual(result.lineNumber, 1_200)
        XCTAssertEqual(result.byteOffset, firstEditedLine.byteOffset)
        XCTAssertEqual(try reopened.line(1_199)?.text, "line-1199")
        XCTAssertEqual(try reopened.line(1_200)?.text, "edited-a")
        XCTAssertEqual(try reopened.line(1_201)?.text, "edited-b")
        XCTAssertEqual(try reopened.line(1_202)?.text, "line-1203")
        XCTAssertEqual(reopened.lineCount, 1_999)
    }

    func testVirtualDocumentRangeReplacePreservesCRLFLineEndings() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("range-crlf.txt")
        try "one\r\ntwo\r\nthree\r\nfour".write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 1)
        _ = try document.replacingLines(2...3, with: "TWO\nTHREE")

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "one\r\nTWO\r\nTHREE\r\nfour")
    }

    func testVirtualDocumentInsertsLineWithoutLoadingWholeFile() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("insert-lines.txt")
        let lines = (1...2_000).map { "line-\($0)" }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 64)
        let result = try document.insertingLine(1_500, text: "line-inserted")
        let reopened = try LargeFileVirtualTextDocument.open(at: fileURL, cachedIndex: result.index)

        XCTAssertEqual(result.lineNumber, 1_500)
        XCTAssertEqual(result.oldByteCount, 0)
        XCTAssertGreaterThan(result.newByteCount, 0)
        XCTAssertEqual(reopened.index, result.index)
        XCTAssertEqual(try reopened.line(1_499)?.text, "line-1499")
        XCTAssertEqual(try reopened.line(1_500)?.text, "line-inserted")
        XCTAssertEqual(try reopened.line(1_501)?.text, "line-1500")
    }

    func testVirtualDocumentInsertsLineBlockWithoutLoadingWholeFile() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("insert-block.txt")
        let lines = (1...2_000).map { "line-\($0)" }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 64)
        let result = try document.insertingLines(1_500, text: "insert-a\ninsert-b\n")
        let reopened = try LargeFileVirtualTextDocument.open(at: fileURL, cachedIndex: result.index)

        XCTAssertEqual(result.lineNumber, 1_500)
        XCTAssertEqual(result.oldByteCount, 0)
        XCTAssertGreaterThan(result.newByteCount, 0)
        XCTAssertEqual(try reopened.line(1_499)?.text, "line-1499")
        XCTAssertEqual(try reopened.line(1_500)?.text, "insert-a")
        XCTAssertEqual(try reopened.line(1_501)?.text, "insert-b")
        XCTAssertEqual(try reopened.line(1_502)?.text, "line-1500")
        XCTAssertEqual(reopened.lineCount, 2_002)
    }

    func testVirtualDocumentAppendLinePreservesCRLFLineEndings() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("append-crlf.txt")
        try "one\r\ntwo".write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 1)
        _ = try document.insertingLine(3, text: "three")

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "one\r\ntwo\r\nthree")
    }

    func testVirtualDocumentDeletesMiddleAndLastLines() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("delete-lines.txt")
        try "one\ntwo\nthree".write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 1)
        let middleResult = try document.deletingLine(2)
        var reopened = try LargeFileVirtualTextDocument.open(at: fileURL, cachedIndex: middleResult.index)

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "one\nthree")
        XCTAssertEqual(try reopened.line(1)?.text, "one")
        XCTAssertEqual(try reopened.line(2)?.text, "three")

        let lastResult = try reopened.deletingLine(2)
        reopened = try LargeFileVirtualTextDocument.open(at: fileURL, cachedIndex: lastResult.index)

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "one")
        XCTAssertEqual(reopened.lineCount, 1)
        XCTAssertEqual(try reopened.line(1)?.text, "one")
    }

    func testVirtualDocumentDeletesLineRangeWithoutLoadingWholeFile() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("delete-range.txt")
        let lines = (1...2_000).map { "line-\($0)" }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let document = try LargeFileVirtualTextDocument.open(at: fileURL, checkpointInterval: 64)
        let result = try document.deletingLines(1_200...1_202)
        let reopened = try LargeFileVirtualTextDocument.open(at: fileURL, cachedIndex: result.index)

        XCTAssertEqual(result.lineNumber, 1_200)
        XCTAssertEqual(try reopened.line(1_199)?.text, "line-1199")
        XCTAssertEqual(try reopened.line(1_200)?.text, "line-1203")
        XCTAssertEqual(reopened.lineCount, 1_997)
        XCTAssertFalse(try String(contentsOf: fileURL, encoding: .utf8).contains("line-1200"))
    }

    func testAttributedLineHighlightsJSONTokensForVirtualRenderer() {
        let attributed = SyntaxHighlighter.attributedLine(
            #"{"enabled": true, "count": 42}"#,
            language: .json,
            fontSize: 13
        )
        let nsText = attributed.string as NSString
        let trueRange = nsText.range(of: "true")
        let numberRange = nsText.range(of: "42")

        XCTAssertNotEqual(trueRange.location, NSNotFound)
        XCTAssertNotEqual(numberRange.location, NSNotFound)
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: trueRange.location, effectiveRange: nil) as? NSColor, NSColor.systemBlue)
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: numberRange.location, effectiveRange: nil) as? NSColor, NSColor.systemOrange)
    }

    @MainActor
    func testVirtualRendererCellsDoNotAcceptTextSelectionThatOverridesSyntaxColors() throws {
        let view = LargeFileVirtualTextView(
            fileURL: URL(fileURLWithPath: "/tmp/missing.json"),
            language: .json,
            fileSizeBytes: nil,
            fontSize: 13,
            targetByteOffset: nil,
            onVisibleLineRangeChange: { _ in }
        )
        let coordinator = LargeFileVirtualTextView.Coordinator(view)
        let tableView = NSTableView()
        let textColumn = NSTableColumn(identifier: LargeFileVirtualTextView.Coordinator.textColumnID)
        tableView.addTableColumn(textColumn)

        let cell = coordinator.tableView(tableView, viewFor: textColumn, row: 0) as? NSTableCellView
        let textField = try XCTUnwrap(cell?.textField)

        XCTAssertFalse(textField.isSelectable)
        XCTAssertTrue(textField.refusesFirstResponder)
        XCTAssertEqual(textField.focusRingType, .none)
        XCTAssertFalse(coordinator.tableView(tableView, shouldSelectRow: 0))
    }

    @MainActor
    func testVirtualRendererActivatesVisibleLineForChunkEditing() {
        var activatedLine: Int?
        let view = LargeFileVirtualTextView(
            fileURL: URL(fileURLWithPath: "/tmp/missing.json"),
            language: .json,
            fileSizeBytes: nil,
            fontSize: 13,
            targetByteOffset: nil,
            onLineActivation: { lineNumber in
                activatedLine = lineNumber
            },
            onVisibleLineRangeChange: { _ in }
        )
        let coordinator = LargeFileVirtualTextView.Coordinator(view)

        coordinator.activateLineForEditing(row: 41)

        XCTAssertEqual(activatedLine, 42)
    }

    @MainActor
    func testVirtualRendererInlineEditCommitRoutesToLineReplacement() {
        var replacements: [(line: Int, text: String)] = []
        let view = LargeFileVirtualTextView(
            fileURL: URL(fileURLWithPath: "/tmp/missing.json"),
            language: .json,
            fileSizeBytes: nil,
            fontSize: 13,
            targetByteOffset: nil,
            onLineReplacementRequest: { lineNumber, text in
                replacements.append((lineNumber, text))
            },
            onVisibleLineRangeChange: { _ in }
        )
        let coordinator = LargeFileVirtualTextView.Coordinator(view)

        coordinator.requestReplaceLine(row: 41, replacementText: #"{"inline":true}"#)
        coordinator.requestReplaceLine(row: 42, replacementText: "two\nlines")

        XCTAssertEqual(replacements.map(\.line), [42])
        XCTAssertEqual(replacements.map(\.text), [#"{"inline":true}"#])
    }

    @MainActor
    func testVirtualRendererLineEditActionsRouteToVisibleLineCallbacks() {
        var replacements: [(line: Int, text: String)] = []
        var insertions: [(line: Int, text: String)] = []
        var deletions: [Int] = []
        let view = LargeFileVirtualTextView(
            fileURL: URL(fileURLWithPath: "/tmp/missing.json"),
            language: .json,
            fileSizeBytes: nil,
            fontSize: 13,
            targetByteOffset: nil,
            onLineReplacementRequest: { lineNumber, text in
                replacements.append((lineNumber, text))
            },
            onLineInsertionRequest: { lineNumber, text in
                insertions.append((lineNumber, text))
            },
            onLineDeletionRequest: { lineNumber in
                deletions.append(lineNumber)
            },
            onVisibleLineRangeChange: { _ in }
        )
        let coordinator = LargeFileVirtualTextView.Coordinator(view)

        coordinator.requestReplaceLine(row: 41, replacementText: #"{"edited":true}"#)
        coordinator.requestInsertLine(row: 42, insertedText: #"{"inserted":true}"#)
        coordinator.requestDeleteLine(row: 43)
        coordinator.requestReplaceLine(row: 44, replacementText: "two\nlines")
        coordinator.requestInsertLine(row: 45, insertedText: "two\nlines")

        XCTAssertEqual(replacements.map(\.line), [42])
        XCTAssertEqual(replacements.map(\.text), [#"{"edited":true}"#])
        XCTAssertEqual(insertions.map(\.line), [43])
        XCTAssertEqual(insertions.map(\.text), [#"{"inserted":true}"#])
        XCTAssertEqual(deletions, [44])
    }

    @MainActor
    func testVirtualRendererContextMenuExposesLineEditActionsForClickedRow() throws {
        let view = LargeFileVirtualTextView(
            fileURL: URL(fileURLWithPath: "/tmp/missing.json"),
            language: .json,
            fileSizeBytes: nil,
            fontSize: 13,
            targetByteOffset: nil,
            onVisibleLineRangeChange: { _ in }
        )
        let coordinator = LargeFileVirtualTextView.Coordinator(view)

        let menu = try XCTUnwrap(coordinator.menu(forVirtualRow: 41))
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)

        XCTAssertEqual(
            titles,
            [
                "Open Editable Chunk",
                "Replace Line...",
                "Insert Line Before...",
                "Delete Line"
            ]
        )
        XCTAssertEqual(menu.item(withTitle: "Replace Line...")?.representedObject as? Int, 42)
        XCTAssertEqual(menu.item(withTitle: "Insert Line Before...")?.representedObject as? Int, 42)
        XCTAssertEqual(menu.item(withTitle: "Delete Line")?.representedObject as? Int, 42)
    }

    @MainActor
    func testVirtualRendererTableSingleClickBeginsInlineEditAndDoubleClickActivatesChunk() {
        var inlineRows: [(row: Int, point: NSPoint?)] = []
        var activatedRows: [Int] = []
        let tableView = LargeFileVirtualTableView()
        tableView.onBeginInlineEditRow = { row, point in
            inlineRows.append((row, point))
        }
        tableView.onActivateRow = { row in
            activatedRows.append(row)
        }

        XCTAssertFalse(tableView.handleClickedRow(-1, clickCount: 1))
        XCTAssertTrue(tableView.handleClickedRow(41, clickCount: 1, pointInTable: NSPoint(x: 120, y: 8)))
        XCTAssertTrue(tableView.handleClickedRow(42, clickCount: 2))

        XCTAssertEqual(inlineRows.map(\.row), [41])
        XCTAssertEqual(inlineRows.first?.point, NSPoint(x: 120, y: 8))
        XCTAssertEqual(activatedRows, [42])
    }

    @MainActor
    func testVirtualRendererTableKeyboardFocusRoutesInlineEditAndDelete() {
        let rows = VirtualTableRows(count: 5)
        var inlineRows: [Int] = []
        var deletedRows: [Int] = []
        let tableView = LargeFileVirtualTableView()
        tableView.dataSource = rows
        tableView.reloadData()
        tableView.onBeginInlineEditRow = { row, point in
            XCTAssertNil(point)
            inlineRows.append(row)
        }
        tableView.onDeleteRow = { row in
            deletedRows.append(row)
        }

        tableView.focusVirtualRow(2)
        tableView.moveFocusedRow(by: 1)
        tableView.beginEditingFocusedRow()
        tableView.deleteFocusedRow()
        tableView.moveFocusedRow(by: 100)
        tableView.beginEditingFocusedRow()

        XCTAssertEqual(tableView.focusedVirtualRow, 4)
        XCTAssertEqual(inlineRows, [3, 4])
        XCTAssertEqual(deletedRows, [3])
    }

    func testInlineLineEditorCaretLocationTracksMonospacedClickPosition() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let characterWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        let text = #"{"name":"Dashboard"}"#

        XCTAssertEqual(
            LargeFileInlineLineEditor.caretLocation(
                in: text,
                clickX: 4,
                font: font,
                insetWidth: 4
            ),
            0
        )
        XCTAssertEqual(
            LargeFileInlineLineEditor.caretLocation(
                in: text,
                clickX: 4 + characterWidth * 8.2,
                font: font,
                insetWidth: 4
            ),
            8
        )
        XCTAssertEqual(
            LargeFileInlineLineEditor.caretLocation(
                in: text,
                clickX: 4 + characterWidth * 1_000,
                font: font,
                insetWidth: 4
            ),
            (text as NSString).length
        )
    }

    func testInlineLineEditorKeyboardShortcutsCommitAndCancel() {
        XCTAssertEqual(
            LargeFileInlineLineEditor.editingAction(
                keyCode: 36,
                characters: "\r",
                modifierFlags: []
            ),
            .commit
        )
        XCTAssertEqual(
            LargeFileInlineLineEditor.editingAction(
                keyCode: 1,
                characters: "s",
                modifierFlags: .command
            ),
            .commit
        )
        XCTAssertEqual(
            LargeFileInlineLineEditor.editingAction(
                keyCode: 53,
                characters: "\u{1b}",
                modifierFlags: []
            ),
            .cancel
        )
        XCTAssertEqual(
            LargeFileInlineLineEditor.editingAction(
                keyCode: 47,
                characters: ".",
                modifierFlags: .command
            ),
            .cancel
        )
        XCTAssertNil(
            LargeFileInlineLineEditor.editingAction(
                keyCode: 1,
                characters: "s",
                modifierFlags: [.command, .option]
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class VirtualTableRows: NSObject, NSTableViewDataSource {
    private let count: Int

    init(count: Int) {
        self.count = count
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        count
    }
}
