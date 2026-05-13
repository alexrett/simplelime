import XCTest
@testable import SimpleLime

final class EditorMiniMapLayoutTests: XCTestCase {
    func testLineHitTestingCoversEntireDocumentWhenCompressed() {
        let layout = EditorMiniMapLayout(lineCount: 1_000, height: 500)

        XCTAssertEqual(layout.lineNumber(at: 0), 1)
        XCTAssertEqual(layout.lineNumber(at: 250), 501)
        XCTAssertEqual(layout.lineNumber(at: 499.9), 1_000)
        XCTAssertEqual(layout.lineNumber(at: 900), 1_000)
    }

    func testLineHitTestingKeepsShortDocumentsTopAligned() {
        let layout = EditorMiniMapLayout(lineCount: 3, height: 100)

        XCTAssertEqual(layout.rowHeight, 4)
        XCTAssertEqual(layout.top, 0)
        XCTAssertEqual(layout.lineNumber(at: 0), 1)
        XCTAssertEqual(layout.lineNumber(at: 4), 2)
        XCTAssertEqual(layout.lineNumber(at: 99), 3)
    }

    func testViewportRectClampsVisibleRangeToDocument() {
        let layout = EditorMiniMapLayout(lineCount: 20, height: 200)

        let rect = layout.viewportRect(for: 18...40, width: 86)

        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxY, 200)
        XCTAssertEqual(layout.clampedRange(18...40), 18...20)
    }
}
