import XCTest
@testable import SimpleLime

final class EditorLanguageTests: XCTestCase {
    func testDetectsDelimitedTableFiles() {
        XCTAssertEqual(EditorLanguage.detect(fileName: "data.csv"), .csv)
        XCTAssertEqual(EditorLanguage.detect(fileName: "data.tsv"), .tsv)
        XCTAssertEqual(EditorLanguage.detect(fileName: "data.tab"), .tsv)
    }

    func testDetectsBinaryPreviewFiles() {
        XCTAssertEqual(EditorLanguage.detect(fileName: "shot.png"), .image)
        XCTAssertEqual(EditorLanguage.detect(fileName: "scan.jpeg"), .image)
        XCTAssertEqual(EditorLanguage.detect(fileName: "brief.pdf"), .pdf)
        XCTAssertTrue(EditorLanguage.image.isBinaryPreview)
        XCTAssertTrue(EditorLanguage.pdf.isBinaryPreview)
        XCTAssertTrue(EditorLanguage.hex.isBinaryPreview)
        XCTAssertFalse(EditorLanguage.image.supportsRenderedPreview)
    }

    func testDelimitedTablePreviewMetadata() {
        XCTAssertTrue(EditorLanguage.csv.isDelimitedTable)
        XCTAssertTrue(EditorLanguage.tsv.supportsRenderedPreview)
        XCTAssertEqual(EditorLanguage.csv.tableDelimiter, ",")
        XCTAssertEqual(EditorLanguage.tsv.tableDelimiter, "\t")
        XCTAssertFalse(EditorLanguage.json.supportsRenderedPreview)
    }

    func testDetectsDrawingFiles() {
        XCTAssertEqual(EditorLanguage.detect(fileName: "board.sldraw"), .drawing)
        XCTAssertEqual(EditorLanguage.detect(fileName: "planning.whiteboard"), .drawing)
        XCTAssertTrue(EditorLanguage.drawing.isWhiteboard)
        XCTAssertEqual(SaveFileType.preferred(for: .drawing), .drawing)
        XCTAssertEqual(SaveFileType.drawing.fileExtension, "sldraw")
    }
}
