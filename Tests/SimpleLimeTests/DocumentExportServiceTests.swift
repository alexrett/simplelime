import AppKit
import PDFKit
import XCTest
@testable import SimpleLime

final class DocumentExportServiceTests: XCTestCase {
    func testExportsMarkdownAsHTMLDocument() {
        let html = DocumentExportService.htmlDocument(
            title: "Draft",
            text:
            """
            # Plan

            - [x] Ship <safe>

            | A | B |
            | --- | --- |
            | 1 | 2 |
            """,
            language: .markdown
        )

        XCTAssertTrue(html.contains("<title>Draft</title>"), html)
        XCTAssertTrue(html.contains("<h1>Plan</h1>"), html)
        XCTAssertTrue(html.contains("&lt;safe&gt;"), html)
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled checked>"), html)
        XCTAssertTrue(html.contains("<table>"), html)
    }

    func testExportsPlainTextAsEscapedPreBlock() {
        let html = DocumentExportService.htmlDocument(
            title: "Snippet",
            text: "if a < b && c > d",
            language: .plain
        )

        XCTAssertTrue(html.contains("<pre>if a &lt; b &amp;&amp; c &gt; d</pre>"), html)
    }

    func testExportsDelimitedTableAsExcelCompatibleHTML() {
        let html = DocumentExportService.excelHTMLWorkbook(
            title: "Sales",
            text: "Name,Total\nAlice,10\nBob,20",
            language: .csv
        )

        XCTAssertTrue(html.contains("urn:schemas-microsoft-com:office:excel"), html)
        XCTAssertTrue(html.contains("<th>Name</th><th>Total</th>"), html)
        XCTAssertTrue(html.contains("<td>Alice</td><td>10</td>"), html)
        XCTAssertTrue(html.contains(#"mso-number-format:"\@""#), html)
    }

    func testExportsNativeExcelWorkbookPackage() {
        let data = DocumentExportService.excelWorkbookData(
            title: "Sales",
            text: "Name,Total\nAlice & Bob,10",
            language: .csv
        )
        let packageText = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(data.starts(with: Data([0x50, 0x4B, 0x03, 0x04])))
        XCTAssertTrue(packageText.contains("xl/workbook.xml"), packageText)
        XCTAssertTrue(packageText.contains("xl/worksheets/sheet1.xml"), packageText)
        XCTAssertTrue(packageText.contains("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"), packageText)
        XCTAssertTrue(packageText.contains(#"<sheet name="Sales""#), packageText)
        XCTAssertTrue(packageText.contains(#"<c r="A1" t="inlineStr"><is><t xml:space="preserve">Name</t></is></c>"#), packageText)
        XCTAssertTrue(packageText.contains("Alice &amp; Bob"), packageText)
    }

    func testExportsTSVToExcelHTML() {
        let html = DocumentExportService.excelHTMLWorkbook(
            title: "TSV",
            text: "Name\tTotal\nAlice\t10",
            language: .tsv
        )

        XCTAssertTrue(html.contains("<td>Alice</td><td>10</td>"), html)
    }

    func testExportsWordCompatibleHTMLDocument() {
        let html = DocumentExportService.wordHTMLDocument(
            title: "Draft",
            text: "# Heading\n\nBody",
            language: .markdown
        )

        XCTAssertTrue(html.contains("urn:schemas-microsoft-com:office:word"), html)
        XCTAssertTrue(html.contains("<w:WordDocument>"), html)
        XCTAssertTrue(html.contains("<h1>Heading</h1>"), html)
    }

    func testExportsNativeWordDocumentPackage() {
        let board = WhiteboardDocument.empty
            .appending(.sticky(rect: WhiteboardRect(x: 0.1, y: 0.1, width: 0.2, height: 0.14), text: "Widget"))
        let data = DocumentExportService.wordDocumentData(
            title: "Draft",
            text:
            """
            # Heading

            Body <safe>

            | Name | Total |
            | --- | --- |
            | Alice | 10 |

            ```sldraw
            \(board.encodedText())
            ```
            """,
            language: .markdown
        )
        let packageText = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(data.starts(with: Data([0x50, 0x4B, 0x03, 0x04])))
        XCTAssertTrue(packageText.contains("word/document.xml"), packageText)
        XCTAssertTrue(packageText.contains("word/styles.xml"), packageText)
        XCTAssertTrue(packageText.contains("application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"), packageText)
        XCTAssertTrue(packageText.contains(#"<w:pStyle w:val="Heading1"/>"#), packageText)
        XCTAssertTrue(packageText.contains(#"<w:t xml:space="preserve">Heading</w:t>"#), packageText)
        XCTAssertTrue(packageText.contains("Body &lt;safe&gt;"), packageText)
        XCTAssertTrue(packageText.contains(#"<w:t xml:space="preserve">Alice</w:t>"#), packageText)
        XCTAssertTrue(packageText.contains("word/media/whiteboard-1.png"), packageText)
        XCTAssertTrue(packageText.contains(#"<a:blip r:embed="rId2"/>"#), packageText)
        XCTAssertTrue(data.contains(Data([0x89, 0x50, 0x4E, 0x47])))
    }

    func testExportsPDFData() throws {
        let data = try DocumentExportService.pdfData(
            title: "Draft",
            text: "Hello PDF",
            language: .plain
        )

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertGreaterThan(data.count, 500)
    }

    func testExportsPDFTextNearTopOfPage() throws {
        let data = try DocumentExportService.pdfData(
            title: "Scratch 4",
            text: "Редактор заметок\n\n- test collaboration 123",
            language: .markdown
        )
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        let image = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        let topInk = nonWhitePixelCount(in: image, yRange: 0..<260)
        let bottomInk = nonWhitePixelCount(in: image, yRange: 532..<792)

        XCTAssertGreaterThan(topInk, 20)
        XCTAssertLessThan(bottomInk, topInk)
    }

    func testExportsPDFPreservesCyrillicTextExtractionOrder() throws {
        let data = try DocumentExportService.pdfData(
            title: "Scratch 4",
            text:
            """
            # Редактор заметок который вышел из под контроля

            - Шаринг по сети
            - Коллаборативное редактирование
            """,
            language: .markdown
        )
        let document = try XCTUnwrap(PDFDocument(data: data))
        let extracted = document.string ?? ""

        XCTAssertTrue(extracted.contains("Scratch 4"), extracted)
        XCTAssertTrue(extracted.contains("Редактор заметок"), extracted)
        XCTAssertTrue(extracted.contains("Шаринг по сети"), extracted)
        XCTAssertLessThan(
            try XCTUnwrap(extracted.range(of: "Scratch 4")?.lowerBound),
            try XCTUnwrap(extracted.range(of: "Редактор заметок")?.lowerBound)
        )
    }

    func testExportsWhiteboardMarkdownWidgetAsInlineSVG() {
        let board = WhiteboardDocument.empty
            .appending(.sticky(rect: WhiteboardRect(x: 0.1, y: 0.1, width: 0.2, height: 0.14), text: "Widget"))
        let html = DocumentExportService.htmlDocument(
            title: "Doc",
            text:
            """
            # Diagram

            ```sldraw
            \(board.encodedText())
            ```
            """,
            language: .markdown
        )

        XCTAssertTrue(html.contains("<figure class=\"whiteboard\">"), html)
        XCTAssertTrue(html.contains("<svg"), html)
        XCTAssertTrue(html.contains("Widget"), html)
    }

    func testExportsWhiteboardMarkdownWidgetIntoPDFAsImage() throws {
        let board = WhiteboardDocument.empty
            .appending(.sticky(rect: WhiteboardRect(x: 0.1, y: 0.1, width: 0.2, height: 0.14), text: "Widget"))
        let data = try DocumentExportService.pdfData(
            title: "Doc",
            text:
            """
            # Diagram

            ```sldraw
            \(board.encodedText())
            ```
            """,
            language: .markdown
        )
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        let image = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)

        XCTAssertGreaterThan(yellowPixelCount(in: image), 100)
    }

    private func nonWhitePixelCount(in image: NSImage, yRange: Range<Int>) -> Int {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return 0
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let clampedRange = max(0, yRange.lowerBound)..<min(height, yRange.upperBound)
        var count = 0
        for y in clampedRange {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.redComponent < 0.92 || color.greenComponent < 0.92 || color.blueComponent < 0.92 {
                    count += 1
                }
            }
        }
        return count
    }

    private func yellowPixelCount(in image: NSImage) -> Int {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return 0
        }

        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.redComponent > 0.75,
                   color.greenComponent > 0.55,
                   color.blueComponent < 0.55 {
                    count += 1
                }
            }
        }
        return count
    }
}
