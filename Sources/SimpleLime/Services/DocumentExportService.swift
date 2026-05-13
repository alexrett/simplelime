import AppKit
import Foundation

enum DocumentExportService {
    enum ExportError: LocalizedError {
        case couldNotCreatePDF

        var errorDescription: String? {
            switch self {
            case .couldNotCreatePDF:
                return "Could not create PDF context."
            }
        }
    }

    private enum PDFElement {
        case text(String)
        case whiteboard(WhiteboardDocument)
    }

    private struct WordDocumentParts {
        var documentXML: String
        var relationshipsXML: String
        var images: [WordImage]
    }

    private struct WordImage {
        var relationshipID: String
        var fileName: String
        var data: Data
    }

    static func htmlDocument(title: String, text: String, language: EditorLanguage) -> String {
        let body: String
        if language.isMarkdown {
            body = markdownBody(text)
        } else if language.isDelimitedTable, let delimiter = language.tableDelimiter {
            body = tableBody(DelimitedTextTable.parse(text, delimiter: delimiter))
        } else {
            body = "<pre>\(escapeHTML(text))</pre>"
        }

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escapeHTML(title))</title>
        <style>
        body { font: 14px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.55; margin: 40px; color: #1f2328; }
        pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
        pre { background: #f6f8fa; padding: 12px; overflow: auto; border-radius: 6px; }
        blockquote { border-left: 3px solid #d0d7de; margin-left: 0; padding-left: 14px; color: #57606a; }
        table { border-collapse: collapse; width: 100%; margin: 14px 0; }
        th, td { border: 1px solid #d0d7de; padding: 6px 8px; text-align: left; vertical-align: top; }
        th { background: #f6f8fa; }
        img, svg { max-width: 100%; }
        .callout { background: #f6f8fa; border-radius: 6px; padding: 10px 12px; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static func wordHTMLDocument(title: String, text: String, language: EditorLanguage) -> String {
        let body: String
        if language.isMarkdown {
            body = markdownBody(text)
        } else if language.isDelimitedTable, let delimiter = language.tableDelimiter {
            body = tableBody(DelimitedTextTable.parse(text, delimiter: delimiter))
        } else {
            body = "<pre>\(escapeHTML(text))</pre>"
        }

        return """
        <html xmlns:o="urn:schemas-microsoft-com:office:office"
              xmlns:w="urn:schemas-microsoft-com:office:word"
              xmlns="http://www.w3.org/TR/REC-html40">
        <head>
        <meta charset="utf-8">
        <title>\(escapeHTML(title))</title>
        <!--[if gte mso 9]><xml><w:WordDocument><w:View>Print</w:View><w:Zoom>100</w:Zoom></w:WordDocument></xml><![endif]-->
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 11pt; line-height: 1.45; }
        pre, code { font-family: Menlo, Consolas, monospace; }
        pre { background: #f6f8fa; padding: 10pt; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1pt solid #999; padding: 4pt 6pt; }
        th { background: #eee; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static func wordDocumentData(title: String, text: String, language: EditorLanguage) -> Data {
        let parts = wordDocumentParts(title: title, text: text, language: language)
        var entries: [String: Data] = [
            "[Content_Types].xml": wordContentTypesXML,
            "_rels/.rels": packageRelationshipsXML(
                officeDocumentPath: "word/document.xml",
                officeDocumentType: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
            ),
            "docProps/app.xml": appPropertiesXML(application: "SimpleLime", documentType: "Document"),
            "docProps/core.xml": corePropertiesXML(title: title),
            "word/_rels/document.xml.rels": parts.relationshipsXML,
            "word/document.xml": parts.documentXML,
            "word/styles.xml": wordStylesXML
        ].mapValues { Data($0.utf8) }

        for image in parts.images {
            entries["word/media/\(image.fileName)"] = image.data
        }

        return OfficeOpenXMLPackage.make(dataEntries: entries)
    }

    static func pdfData(title: String, text: String, language: EditorLanguage) throws -> Data {
        let elements = pdfElements(title: title, text: text, language: language)
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.couldNotCreatePDF
        }

        let pageInset: CGFloat = 54
        let contentRect = CGRect(
            x: pageInset,
            y: pageInset,
            width: mediaBox.width - pageInset * 2,
            height: mediaBox.height - pageInset * 2
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let lineHeight = ceil(NSFont.monospacedSystemFont(ofSize: 11, weight: .regular).boundingRectForFont.height + paragraph.lineSpacing)
        var y = contentRect.minY
        var pageOpen = false

        func beginPage() {
            context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
            context.saveGState()
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: 1, y: -1)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            y = contentRect.minY
            pageOpen = true
        }

        func endPage() {
            NSGraphicsContext.restoreGraphicsState()

            context.restoreGState()
            context.endPDFPage()
            pageOpen = false
        }

        func ensurePage(for height: CGFloat) {
            if !pageOpen {
                beginPage()
            } else if y + height > contentRect.maxY {
                endPage()
                beginPage()
            }
        }

        for element in elements {
            switch element {
            case .text(let value):
                for line in value.components(separatedBy: .newlines) {
                    let lineText = line.isEmpty ? " " : line
                    let attributed = NSAttributedString(string: lineText, attributes: attributes)
                    let measured = attributed.boundingRect(
                        with: CGSize(width: contentRect.width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading]
                    )
                    let height = max(lineHeight, ceil(measured.height))
                    ensurePage(for: height)
                    attributed.draw(
                        with: CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: height),
                        options: [.usesLineFragmentOrigin, .usesFontLeading]
                    )
                    y += height
                }
            case .whiteboard(let document):
                let aspect = WhiteboardExportService.defaultCanvasSize.width / WhiteboardExportService.defaultCanvasSize.height
                let imageHeight = min(contentRect.width / aspect, contentRect.height * 0.6)
                ensurePage(for: imageHeight)
                let image = WhiteboardExportService.image(
                    document: document,
                    size: CGSize(width: 960, height: 600)
                )
                image.draw(
                    in: CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: imageHeight),
                    from: CGRect(origin: .zero, size: image.size),
                    operation: .sourceOver,
                    fraction: 1
                )
                y += imageHeight + lineHeight
            }
        }

        if pageOpen {
            endPage()
        } else {
            beginPage()
            endPage()
        }

        context.closePDF()
        return data as Data
    }

    static func excelHTMLWorkbook(title: String, text: String, language: EditorLanguage) -> String {
        let table: DelimitedTextTable
        if language.isDelimitedTable, let delimiter = language.tableDelimiter {
            table = DelimitedTextTable.parse(text, delimiter: delimiter)
        } else {
            table = DelimitedTextTable(rows: [[text]], delimiter: ",")
        }

        return """
        <html xmlns:o="urn:schemas-microsoft-com:office:office"
              xmlns:x="urn:schemas-microsoft-com:office:excel"
              xmlns="http://www.w3.org/TR/REC-html40">
        <head>
        <meta charset="utf-8">
        <title>\(escapeHTML(title))</title>
        <!--[if gte mso 9]><xml><x:ExcelWorkbook><x:ExcelWorksheets><x:ExcelWorksheet><x:Name>\(escapeHTML(sheetName(title)))</x:Name><x:WorksheetOptions><x:DisplayGridlines/></x:WorksheetOptions></x:ExcelWorksheet></x:ExcelWorksheets></x:ExcelWorkbook></xml><![endif]-->
        <style>
        table { border-collapse: collapse; }
        td, th { border: 1px solid #999; padding: 4px 6px; mso-number-format:"\\@"; }
        th { font-weight: bold; background: #eee; }
        </style>
        </head>
        <body>
        \(tableBody(table))
        </body>
        </html>
        """
    }

    static func excelWorkbookData(title: String, text: String, language: EditorLanguage) -> Data {
        let table: DelimitedTextTable
        if language.isDelimitedTable, let delimiter = language.tableDelimiter {
            table = DelimitedTextTable.parse(text, delimiter: delimiter)
        } else {
            table = DelimitedTextTable(rows: [[text]], delimiter: ",")
        }

        return OfficeOpenXMLPackage.make(entries: [
            "[Content_Types].xml": excelContentTypesXML,
            "_rels/.rels": packageRelationshipsXML(
                officeDocumentPath: "xl/workbook.xml",
                officeDocumentType: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
            ),
            "docProps/app.xml": appPropertiesXML(application: "SimpleLime", documentType: "Spreadsheet"),
            "docProps/core.xml": corePropertiesXML(title: title),
            "xl/_rels/workbook.xml.rels": workbookRelationshipsXML,
            "xl/workbook.xml": workbookXML(title: title),
            "xl/worksheets/sheet1.xml": worksheetXML(table: table)
        ])
    }

    private static func pdfElements(title: String, text: String, language: EditorLanguage) -> [PDFElement] {
        guard language.isMarkdown else {
            return [.text(plainExportText(title: title, text: text, language: language))]
        }

        let document = MarkdownPreviewParser.parseDocument(text)
        var elements: [PDFElement] = [.text(title), .text("")]
        for block in document.blocks {
            switch block.kind {
            case .whiteboard(let value):
                elements.append(.whiteboard(WhiteboardDocument.decode(from: value)))
            default:
                let rendered = plainMarkdownBlockText(block)
                if !rendered.isEmpty {
                    elements.append(.text(rendered))
                }
            }
            elements.append(.text(""))
        }
        return elements
    }

    private static func plainExportText(title: String, text: String, language: EditorLanguage) -> String {
        if language.isDelimitedTable, let delimiter = language.tableDelimiter {
            let table = DelimitedTextTable.parse(text, delimiter: delimiter)
            let rows = table.rows.map { row in row.joined(separator: "\t") }
            return "\(title)\n\n\(rows.joined(separator: "\n"))"
        }

        if language.isMarkdown {
            let document = MarkdownPreviewParser.parseDocument(text)
            let body = document.blocks.map(plainMarkdownBlockText)
            .joined(separator: "\n\n")
            return "\(title)\n\n\(body)"
        }

        return "\(title)\n\n\(text)"
    }

    private static func plainMarkdownBlockText(_ block: MarkdownBlock) -> String {
        switch block.kind {
        case .frontMatter(let value), .paragraph(let value), .quote(let value), .math(let value):
            return value
        case .heading(let level, let value):
            return "\(String(repeating: "#", count: max(1, level))) \(value)"
        case .unorderedList(let items):
            return items.map { item in
                let marker = item.checked.map { $0 ? "[x]" : "[ ]" } ?? "-"
                return "\(String(repeating: "  ", count: item.indentLevel))\(marker) \(item.text)"
            }.joined(separator: "\n")
        case .orderedList(let items):
            return items.enumerated().map { index, item in
                "\(String(repeating: "  ", count: item.indentLevel))\(index + 1). \(item.text)"
            }.joined(separator: "\n")
        case .callout(let title, let value):
            return "\(title)\n\(value)"
        case .code(_, let value), .diagram(_, let value):
            return value
        case .whiteboard:
            return "[Whiteboard drawing]"
        case .table(let table):
            return ([table.headers] + table.rows).map { $0.joined(separator: "\t") }.joined(separator: "\n")
        case .image(let image):
            return image.title ?? image.alt
        case .htmlMedia(let media):
            return media.title ?? media.source
        case .linkReference(let reference):
            return "\(reference.label): \(reference.source)"
        case .footnoteDefinition(let label, let value):
            return "[\(label)] \(value)"
        case .toc(let headings):
            return headings.map(\.title).joined(separator: "\n")
        case .rule:
            return String(repeating: "-", count: 40)
        }
    }

    private static func wordDocumentParts(title: String, text: String, language: EditorLanguage) -> WordDocumentParts {
        var images: [WordImage] = []
        let documentXML = wordDocumentXML(title: title, text: text, language: language, images: &images)
        return WordDocumentParts(
            documentXML: documentXML,
            relationshipsXML: wordDocumentRelationshipsXML(images: images),
            images: images
        )
    }

    private static func wordDocumentXML(
        title: String,
        text: String,
        language: EditorLanguage,
        images: inout [WordImage]
    ) -> String {
        let body: String
        if language.isMarkdown {
            body = wordMarkdownBody(title: title, text: text, images: &images)
        } else if language.isDelimitedTable, let delimiter = language.tableDelimiter {
            let table = DelimitedTextTable.parse(text, delimiter: delimiter)
            body = wordParagraph(title, style: "Title") + wordTable(table)
        } else {
            body = wordParagraph(title, style: "Title") + plainTextWordBody(text)
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                    xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <w:body>
        \(body)
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private static func wordMarkdownBody(title: String, text: String, images: inout [WordImage]) -> String {
        let document = MarkdownPreviewParser.parseDocument(text)
        var parts = [wordParagraph(title, style: "Title")]

        for block in document.blocks {
            switch block.kind {
            case .heading(let level, let value):
                parts.append(wordParagraph(value, style: "Heading\(min(max(level, 1), 3))"))
            case .paragraph(let value), .quote(let value), .math(let value):
                parts.append(contentsOf: wordParagraphs(from: value))
            case .frontMatter(let value), .code(_, let value), .diagram(_, let value):
                parts.append(contentsOf: wordParagraphs(from: value, style: "Code"))
            case .unorderedList(let items):
                parts.append(contentsOf: items.map { item in
                    let marker = item.checked.map { $0 ? "[x]" : "[ ]" } ?? "-"
                    return wordParagraph("\(String(repeating: "  ", count: item.indentLevel))\(marker) \(item.text)")
                })
            case .orderedList(let items):
                parts.append(contentsOf: items.enumerated().map { index, item in
                    wordParagraph("\(String(repeating: "  ", count: item.indentLevel))\(index + 1). \(item.text)")
                })
            case .callout(let title, let value):
                parts.append(wordParagraph(title, style: "Heading3"))
                parts.append(contentsOf: wordParagraphs(from: value))
            case .whiteboard(let value):
                let document = WhiteboardDocument.decode(from: value)
                if let imageParagraph = wordImageParagraph(document: document, images: &images) {
                    parts.append(imageParagraph)
                } else {
                    parts.append(wordParagraph("[Whiteboard drawing]"))
                }
            case .table(let table):
                parts.append(wordMarkdownTable(table))
            case .image(let image):
                parts.append(wordParagraph(image.title ?? image.alt))
            case .htmlMedia(let media):
                parts.append(wordParagraph(media.title ?? media.source))
            case .linkReference(let reference):
                parts.append(wordParagraph("\(reference.label): \(reference.source)"))
            case .footnoteDefinition(let label, let value):
                parts.append(wordParagraph("[\(label)] \(value)"))
            case .toc(let headings):
                parts.append(contentsOf: headings.map { wordParagraph($0.title) })
            case .rule:
                parts.append(wordParagraph(String(repeating: "-", count: 40)))
            }
        }

        return parts.joined()
    }

    private static func plainTextWordBody(_ text: String) -> String {
        wordParagraphs(from: text).joined()
    }

    private static func wordParagraphs(from text: String, style: String? = nil) -> [String] {
        text.components(separatedBy: .newlines).map { wordParagraph($0, style: style) }
    }

    private static func wordParagraph(_ text: String, style: String? = nil) -> String {
        let styleXML = style.map { "<w:pPr><w:pStyle w:val=\"\(escapeXML($0))\"/></w:pPr>" } ?? ""
        let textXML = text.isEmpty
            ? ""
            : "<w:r><w:t xml:space=\"preserve\">\(escapeXML(text))</w:t></w:r>"
        return """
            <w:p>\(styleXML)\(textXML)</w:p>
        """
    }

    private static func wordMarkdownTable(_ table: MarkdownTable) -> String {
        let rows = [table.headers] + table.rows
        return wordTableRows(rows)
    }

    private static func wordTable(_ table: DelimitedTextTable) -> String {
        let rows = (0..<table.rowCount).map { rowIndex in
            (0..<table.columnCount).map { table.cell(row: rowIndex, column: $0) }
        }
        return wordTableRows(rows)
    }

    private static func wordTableRows(_ rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "" }
        let body = rows.map { row in
            let cells = row.map { value in
                """
                <w:tc><w:tcPr><w:tcW w:w="2400" w:type="dxa"/></w:tcPr>\(wordParagraph(value))</w:tc>
                """
            }
            .joined()
            return "<w:tr>\(cells)</w:tr>"
        }
        .joined()

        return """
            <w:tbl>
              <w:tblPr>
                <w:tblW w:w="0" w:type="auto"/>
                <w:tblBorders>
                  <w:top w:val="single" w:sz="4" w:space="0" w:color="C8CDD3"/>
                  <w:left w:val="single" w:sz="4" w:space="0" w:color="C8CDD3"/>
                  <w:bottom w:val="single" w:sz="4" w:space="0" w:color="C8CDD3"/>
                  <w:right w:val="single" w:sz="4" w:space="0" w:color="C8CDD3"/>
                  <w:insideH w:val="single" w:sz="4" w:space="0" w:color="C8CDD3"/>
                  <w:insideV w:val="single" w:sz="4" w:space="0" w:color="C8CDD3"/>
                </w:tblBorders>
              </w:tblPr>
        \(body)
            </w:tbl>
        """
    }

    private static func wordImageParagraph(document: WhiteboardDocument, images: inout [WordImage]) -> String? {
        guard let pngData = WhiteboardExportService.pngData(document: document) else {
            return nil
        }

        let imageNumber = images.count + 1
        let relationshipID = "rId\(imageNumber + 1)"
        let fileName = "whiteboard-\(imageNumber).png"
        images.append(WordImage(relationshipID: relationshipID, fileName: fileName, data: pngData))

        let widthEMU = 6_858_000
        let heightEMU = 4_286_250
        return """
            <w:p>
              <w:r>
                <w:drawing>
                  <wp:inline distT="0" distB="0" distL="0" distR="0">
                    <wp:extent cx="\(widthEMU)" cy="\(heightEMU)"/>
                    <wp:docPr id="\(imageNumber)" name="Whiteboard \(imageNumber)"/>
                    <a:graphic>
                      <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                        <pic:pic>
                          <pic:nvPicPr>
                            <pic:cNvPr id="\(imageNumber)" name="\(escapeXML(fileName))"/>
                            <pic:cNvPicPr/>
                          </pic:nvPicPr>
                          <pic:blipFill>
                            <a:blip r:embed="\(relationshipID)"/>
                            <a:stretch><a:fillRect/></a:stretch>
                          </pic:blipFill>
                          <pic:spPr>
                            <a:xfrm>
                              <a:off x="0" y="0"/>
                              <a:ext cx="\(widthEMU)" cy="\(heightEMU)"/>
                            </a:xfrm>
                            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                          </pic:spPr>
                        </pic:pic>
                      </a:graphicData>
                    </a:graphic>
                  </wp:inline>
                </w:drawing>
              </w:r>
            </w:p>
        """
    }

    private static func wordDocumentRelationshipsXML(images: [WordImage]) -> String {
        let imageRelationships = images.map { image in
            """
              <Relationship Id="\(image.relationshipID)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/\(image.fileName)"/>
            """
        }
        .joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        \(imageRelationships)
        </Relationships>
        """
    }

    private static func workbookXML(title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="\(escapeXML(sheetName(title)))" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
    }

    private static func worksheetXML(table: DelimitedTextTable) -> String {
        let rows = (0..<table.rowCount).map { rowIndex in
            let rowNumber = rowIndex + 1
            let cells = (0..<table.columnCount).map { columnIndex in
                let reference = "\(spreadsheetColumnName(columnIndex))\(rowNumber)"
                return """
                <c r="\(reference)" t="inlineStr"><is><t xml:space="preserve">\(escapeXML(table.cell(row: rowIndex, column: columnIndex)))</t></is></c>
                """
            }
            .joined()
            return "<row r=\"\(rowNumber)\">\(cells)</row>"
        }
        .joined()

        let dimension = table.rowCount > 0 && table.columnCount > 0
            ? "A1:\(spreadsheetColumnName(table.columnCount - 1))\(table.rowCount)"
            : "A1"

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                   xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <dimension ref="\(dimension)"/>
          <sheetViews><sheetView workbookViewId="0"/></sheetViews>
          <sheetData>
        \(rows)
          </sheetData>
        </worksheet>
        """
    }

    private static func markdownBody(_ text: String) -> String {
        let document = MarkdownPreviewParser.parseDocument(text)
        return document.blocks.map { block in
            switch block.kind {
            case .frontMatter(let value):
                return "<pre><code>\(escapeHTML(value))</code></pre>"
            case .heading(let level, let value):
                let clamped = min(max(level, 1), 6)
                return "<h\(clamped)>\(inlineHTML(value))</h\(clamped)>"
            case .paragraph(let value):
                return "<p>\(inlineHTML(value))</p>"
            case .unorderedList(let items):
                return listHTML(items: items, ordered: false)
            case .orderedList(let items):
                return listHTML(items: items, ordered: true)
            case .quote(let value):
                return "<blockquote>\(inlineHTML(value))</blockquote>"
            case .callout(let title, let value):
                return "<div class=\"callout\"><strong>\(escapeHTML(title))</strong><p>\(inlineHTML(value))</p></div>"
            case .code(_, let value), .diagram(_, let value), .math(let value):
                return "<pre><code>\(escapeHTML(value))</code></pre>"
            case .whiteboard(let value):
                let document = WhiteboardDocument.decode(from: value)
                return "<figure class=\"whiteboard\">\(WhiteboardExportService.svgDocument(title: "Whiteboard", document: document, size: CGSize(width: 960, height: 600)))</figure>"
            case .table(let table):
                return markdownTableBody(table)
            case .image(let image):
                let title = image.title.map { " title=\"\(escapeHTML($0))\"" } ?? ""
                return "<p><img src=\"\(escapeHTML(image.source))\" alt=\"\(escapeHTML(image.alt))\"\(title)></p>"
            case .htmlMedia(let media):
                return "<p><a href=\"\(escapeHTML(media.source))\">\(escapeHTML(media.title ?? media.source))</a></p>"
            case .linkReference(let reference):
                return "<p><a href=\"\(escapeHTML(reference.source))\">\(escapeHTML(reference.label))</a></p>"
            case .footnoteDefinition(let label, let value):
                return "<p><sup>\(escapeHTML(label))</sup> \(inlineHTML(value))</p>"
            case .toc(let headings):
                let items = headings.map { "<li><a href=\"#\">\(escapeHTML($0.title))</a></li>" }.joined()
                return "<nav><ul>\(items)</ul></nav>"
            case .rule:
                return "<hr>"
            }
        }
        .joined(separator: "\n")
    }

    private static func listHTML(items: [MarkdownListItem], ordered: Bool) -> String {
        let tag = ordered ? "ol" : "ul"
        let body = items.map { item in
            let prefix: String
            if let checked = item.checked {
                prefix = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")> "
            } else {
                prefix = ""
            }
            return "<li>\(prefix)\(inlineHTML(item.text))</li>"
        }
        .joined()
        return "<\(tag)>\(body)</\(tag)>"
    }

    private static func markdownTableBody(_ table: MarkdownTable) -> String {
        let header = table.headers.map { "<th>\(inlineHTML($0))</th>" }.joined()
        let rows = table.rows.map { row in
            "<tr>\(row.map { "<td>\(inlineHTML($0))</td>" }.joined())</tr>"
        }
        .joined()
        return "<table><thead><tr>\(header)</tr></thead><tbody>\(rows)</tbody></table>"
    }

    private static func tableBody(_ table: DelimitedTextTable) -> String {
        guard table.rowCount > 0, table.columnCount > 0 else {
            return "<table></table>"
        }

        let header = (0..<table.columnCount)
            .map { "<th>\(escapeHTML(table.cell(row: 0, column: $0)))</th>" }
            .joined()
        let rows = (1..<table.rowCount).map { rowIndex in
            let cells = (0..<table.columnCount)
                .map { "<td>\(escapeHTML(table.cell(row: rowIndex, column: $0)))</td>" }
                .joined()
            return "<tr>\(cells)</tr>"
        }
        .joined()
        return "<table><thead><tr>\(header)</tr></thead><tbody>\(rows)</tbody></table>"
    }

    private static func inlineHTML(_ value: String) -> String {
        escapeHTML(value)
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func sheetName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: #"[]:*?/\"#)
        let cleaned = title
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "Sheet1" : cleaned).prefix(31))
    }

    private static func spreadsheetColumnName(_ zeroBasedIndex: Int) -> String {
        var value = max(0, zeroBasedIndex)
        var scalars: [UnicodeScalar] = []
        repeat {
            let remainder = value % 26
            scalars.insert(UnicodeScalar(65 + remainder)!, at: 0)
            value = (value / 26) - 1
        } while value >= 0
        return String(String.UnicodeScalarView(scalars))
    }

    private static func packageRelationshipsXML(officeDocumentPath: String, officeDocumentType: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="\(officeDocumentType)" Target="\(officeDocumentPath)"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
    }

    private static var workbookRelationshipsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """
    }

    private static func appPropertiesXML(application: String, documentType: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
                    xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>\(escapeXML(application))</Application>
          <DocSecurity>0</DocSecurity>
          <ScaleCrop>false</ScaleCrop>
          <HeadingPairs>
            <vt:vector size="2" baseType="variant">
              <vt:variant><vt:lpstr>\(escapeXML(documentType))</vt:lpstr></vt:variant>
              <vt:variant><vt:i4>1</vt:i4></vt:variant>
            </vt:vector>
          </HeadingPairs>
        </Properties>
        """
    }

    private static func corePropertiesXML(title: String) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
                           xmlns:dc="http://purl.org/dc/elements/1.1/"
                           xmlns:dcterms="http://purl.org/dc/terms/"
                           xmlns:dcmitype="http://purl.org/dc/dcmitype/"
                           xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(escapeXML(title))</dc:title>
          <dc:creator>SimpleLime</dc:creator>
          <cp:lastModifiedBy>SimpleLime</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(timestamp)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(timestamp)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private static var wordContentTypesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Default Extension="png" ContentType="image/png"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        </Types>
        """
    }

    private static var excelContentTypesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        </Types>
        """
    }

    private static var wordStylesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:style w:type="paragraph" w:styleId="Title">
            <w:name w:val="Title"/>
            <w:pPr><w:spacing w:after="240"/></w:pPr>
            <w:rPr><w:b/><w:sz w:val="36"/></w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading1">
            <w:name w:val="Heading 1"/>
            <w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr>
            <w:rPr><w:b/><w:sz w:val="30"/></w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading2">
            <w:name w:val="Heading 2"/>
            <w:pPr><w:spacing w:before="200" w:after="100"/></w:pPr>
            <w:rPr><w:b/><w:sz w:val="26"/></w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading3">
            <w:name w:val="Heading 3"/>
            <w:pPr><w:spacing w:before="160" w:after="80"/></w:pPr>
            <w:rPr><w:b/><w:sz w:val="22"/></w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Code">
            <w:name w:val="Code"/>
            <w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo"/><w:sz w:val="20"/></w:rPr>
          </w:style>
        </w:styles>
        """
    }
}

private enum OfficeOpenXMLPackage {
    static func make(entries: [String: String]) -> Data {
        make(dataEntries: entries.mapValues { Data($0.utf8) })
    }

    static func make(dataEntries entries: [String: Data]) -> Data {
        let sortedEntries = entries
            .map { (path: $0.key, data: $0.value) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        var archive = Data()
        var centralDirectory = Data()

        for entry in sortedEntries {
            let nameData = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let localHeaderOffset = UInt32(archive.count)

            archive.appendUInt32LE(0x04034B50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(crc)
            archive.appendUInt32LE(UInt32(entry.data.count))
            archive.appendUInt32LE(UInt32(entry.data.count))
            archive.appendUInt16LE(UInt16(nameData.count))
            archive.appendUInt16LE(0)
            archive.append(nameData)
            archive.append(entry.data)

            centralDirectory.appendUInt32LE(0x02014B50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(crc)
            centralDirectory.appendUInt32LE(UInt32(entry.data.count))
            centralDirectory.appendUInt32LE(UInt32(entry.data.count))
            centralDirectory.appendUInt16LE(UInt16(nameData.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(localHeaderOffset)
            centralDirectory.append(nameData)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendUInt32LE(0x06054B50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(UInt16(sortedEntries.count))
        archive.appendUInt16LE(UInt16(sortedEntries.count))
        archive.appendUInt32LE(UInt32(centralDirectory.count))
        archive.appendUInt32LE(centralDirectoryOffset)
        archive.appendUInt16LE(0)

        return archive
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0...255).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = 0xEDB88320 ^ (crc >> 1)
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
