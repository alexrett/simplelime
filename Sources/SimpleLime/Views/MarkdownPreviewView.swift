import AppKit
import SwiftUI
import WebKit

struct MarkdownPreviewView: View {
    let text: String
    var baseURL: URL?

    var body: some View {
        let document = MarkdownPreviewParser.parseDocument(text)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(document.blocks) { block in
                    blockView(block, references: document.references)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, references: [String: MarkdownLinkReference]) -> some View {
        switch block.kind {
        case .frontMatter(let value):
            MarkdownCodeBlockView(language: "yaml", value: value)

        case .heading(let level, let value):
            Text(inlineMarkdown(value, references: references))
                .font(.system(size: headingSize(for: level), weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, level == 1 ? 0 : 8)

        case .paragraph(let value):
            Text(inlineMarkdown(value, references: references))
                .font(.system(size: 14))
                .lineSpacing(4)
                .textSelection(.enabled)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let checked = item.checked {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                        } else {
                            Text("•")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                        }

                        Text(inlineMarkdown(item.text, references: references))
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(item.indentLevel) * 18)
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .trailing)

                        Text(inlineMarkdown(item.text, references: references))
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(item.indentLevel) * 18)
                }
            }

        case .quote(let value):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 3)
                Text(inlineMarkdown(value, references: references))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)

        case .callout(let title, let value):
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(inlineMarkdown(value, references: references))
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .code(let language, let value):
            MarkdownCodeBlockView(language: language, value: value)

        case .diagram(let language, let value):
            MermaidPreviewView(code: value, language: language)
                .frame(minHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                }

        case .math(let value):
            VStack(alignment: .leading, spacing: 6) {
                Text("Math")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 15, design: .serif))
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .table(let table):
            MarkdownTableView(table: table) { value in
                inlineMarkdown(value, references: references)
            }

        case .image(let image):
            MarkdownImageView(image: image, baseURL: baseURL)

        case .htmlMedia(let media):
            MarkdownHTMLMediaView(media: media)

        case .linkReference(let reference):
            MarkdownReferenceView(reference: reference)

        case .footnoteDefinition(let label, let value):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(inlineMarkdown(value, references: references))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }

        case .toc(let headings):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(headings) { heading in
                    Text(heading.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.leading, CGFloat(max(0, heading.level - 1)) * 14)
                }
            }
            .padding(.vertical, 4)

        case .rule:
            Divider()
                .padding(.vertical, 6)
        }
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 28
        case 2: return 22
        case 3: return 18
        default: return 16
        }
    }

    private func inlineMarkdown(_ value: String, references: [String: MarkdownLinkReference]) -> AttributedString {
        MarkdownPreviewInlineRenderer.attributedString(value, references: references)
    }
}

struct MarkdownPreviewDocument {
    let blocks: [MarkdownBlock]
    let references: [String: MarkdownLinkReference]
}

struct MarkdownBlock: Identifiable {
    enum Kind {
        case frontMatter(String)
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([MarkdownListItem])
        case orderedList([MarkdownListItem])
        case quote(String)
        case callout(title: String, text: String)
        case code(language: String?, text: String)
        case diagram(language: String, text: String)
        case math(String)
        case table(MarkdownTable)
        case image(MarkdownImage)
        case htmlMedia(MarkdownHTMLMedia)
        case linkReference(MarkdownLinkReference)
        case footnoteDefinition(label: String, text: String)
        case toc([MarkdownHeading])
        case rule
    }

    let id = UUID()
    let kind: Kind
}

struct MarkdownListItem: Identifiable {
    let id = UUID()
    let text: String
    let checked: Bool?
    let indentLevel: Int
}

struct MarkdownImage: Identifiable {
    let id = UUID()
    let alt: String
    let source: String
    let title: String?
}

struct MarkdownHTMLMedia: Identifiable {
    let id = UUID()
    let tag: String
    let source: String
    let title: String?
    let width: String?
    let height: String?
}

struct MarkdownLinkReference {
    let label: String
    let key: String
    let source: String
    let title: String?
}

struct MarkdownTable: Identifiable {
    let id = UUID()
    let headers: [String]
    let alignments: [MarkdownTableAlignment]
    let rows: [[String]]
}

enum MarkdownTableAlignment {
    case leading
    case center
    case trailing
}

private struct MarkdownCodeBlockView: View {
    let language: String?
    let value: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                }
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, language == nil ? 12 : 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct MarkdownHTMLMediaView: View {
    let media: MarkdownHTMLMedia

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: media.tag == "iframe" ? "globe" : "play.rectangle")
                    .foregroundStyle(.secondary)
                Text(media.tag.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let title = media.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            Text(media.source)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct MarkdownReferenceView: View {
    let reference: MarkdownLinkReference

    var body: some View {
        Text(referenceText)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(.vertical, 2)
    }

    private var referenceText: String {
        let title = reference.title.map { " \"\($0)\"" } ?? ""
        return "[\(reference.label)]: \(reference.source)\(title)"
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    let inlineMarkdown: (String) -> AttributedString

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                tableRow(table.headers, isHeader: true)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, isHeader: false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            }
        }
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<max(table.headers.count, cells.count), id: \.self) { index in
                Text(inlineMarkdown(index < cells.count ? cells[index] : ""))
                    .font(.system(size: 13, weight: isHeader ? .semibold : .regular))
                    .frame(width: 150, alignment: alignment(for: index))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .border(Color(nsColor: .separatorColor), width: 0.5)
            }
        }
        .background(isHeader ? Color(nsColor: .controlBackgroundColor) : Color.clear)
    }

    private func alignment(for index: Int) -> Alignment {
        guard table.alignments.indices.contains(index) else { return .leading }

        switch table.alignments[index] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

private struct MarkdownImageView: View {
    let image: MarkdownImage
    let baseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = resolvedURL, url.isFileURL, let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let url = resolvedURL, url.scheme?.hasPrefix("http") == true {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .failure:
                        missingImage
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    @unknown default:
                        missingImage
                    }
                }
            } else {
                missingImage
            }

            if let title = image.title ?? (image.alt.isEmpty ? nil : image.alt) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var missingImage: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
            Text(image.alt.isEmpty ? image.source : image.alt)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var resolvedURL: URL? {
        if let url = URL(string: image.source), url.scheme != nil {
            return url
        }

        guard let baseURL else {
            return URL(fileURLWithPath: image.source)
        }

        return URL(fileURLWithPath: image.source, relativeTo: baseURL).standardizedFileURL
    }
}

private struct MermaidPreviewView: NSViewRepresentable {
    let code: String
    let language: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    private var html: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
              color: #d8d8d8;
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            }
            .wrap {
              padding: 14px;
              min-height: 210px;
              box-sizing: border-box;
              display: flex;
              align-items: center;
              justify-content: center;
            }
            pre {
              white-space: pre-wrap;
              text-align: left;
              color: #d8d8d8;
            }
            svg {
              max-width: 100%;
              height: auto;
            }
          </style>
          <script type="module">
            const source = \(javaScriptLiteral(code));
            const diagram = document.getElementById('diagram');
            try {
              const module = await import('https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs');
              const mermaid = module.default;
              mermaid.initialize({ startOnLoad: false, theme: 'dark' });
              const result = await mermaid.render('simplelime-preview-diagram', source);
              diagram.innerHTML = result.svg;
            } catch {
              // Keep the deterministic local fallback below.
            }
          </script>
        </head>
        <body>
          <div class="wrap">
            <div id="diagram">\(fallbackSVG)</div>
          </div>
        </body>
        </html>
        """
    }

    private var fallbackSVG: String {
        let lines = code.components(separatedBy: .newlines)
        let width = 520
        let height = max(120, lines.count * 20 + 58)
        let body = lines.enumerated().map { index, line in
            "<text x=\"18\" y=\"\(48 + index * 20)\" font-size=\"13\" fill=\"currentColor\">\(escapedHTML(line))</text>"
        }.joined()

        return """
        <svg data-simplelime-diagram="source" viewBox="0 0 \(width) \(height)" role="img" aria-label="\(escapedHTML(language)) source">
          <rect x="1" y="1" width="\(width - 2)" height="\(height - 2)" rx="8" fill="rgba(255,255,255,0.06)" stroke="currentColor" opacity="0.75"/>
          <text x="18" y="24" font-size="12" fill="currentColor" opacity="0.68">\(escapedHTML(language))</text>
          \(body)
        </svg>
        """
    }

    private func escapedHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func javaScriptLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return "\"\""
        }

        return String(encoded.dropFirst().dropLast())
    }
}

enum MarkdownPreviewInlineRenderer {
    static func attributedString(_ value: String, references: [String: MarkdownLinkReference]) -> AttributedString {
        let prepared = markdown(value, references: references)
        return (try? AttributedString(markdown: prepared)) ?? AttributedString(prepared)
    }

    static func markdown(_ value: String, references: [String: MarkdownLinkReference]) -> String {
        var output = value

        output = replace(output, pattern: #"<(u|kbd)\b[^>]*>([\s\S]*?)</\1>"#, options: [.caseInsensitive]) { match, source in
            source.substring(with: match.range(at: 2))
        }

        output = replace(output, pattern: #"\[\^([^\]]+)\]"#) { match, source in
            "[\(source.substring(with: match.range(at: 1)))]"
        }

        output = replace(output, pattern: #"!\[([^\]]*)\]\[([^\]]*)\]"#) { match, source in
            let alt = source.substring(with: match.range(at: 1))
            let label = source.substring(with: match.range(at: 2))
            let resolvedLabel = label.isEmpty ? alt : label
            guard let reference = references[MarkdownPreviewParser.normalizeReferenceLabel(resolvedLabel)] else {
                return source.substring(with: match.range)
            }
            return markdownLink(text: alt.isEmpty ? reference.source : alt, source: reference.source)
        }

        output = replace(output, pattern: #"\[([^\]]+)\]\[([^\]]*)\]"#) { match, source in
            let text = source.substring(with: match.range(at: 1))
            let label = source.substring(with: match.range(at: 2))
            let resolvedLabel = label.isEmpty ? text : label
            guard let reference = references[MarkdownPreviewParser.normalizeReferenceLabel(resolvedLabel)] else {
                return source.substring(with: match.range)
            }
            return markdownLink(text: text, source: reference.source)
        }

        output = replace(output, pattern: #"<(https?://[^>\s]+)>"#) { match, source in
            let url = source.substring(with: match.range(at: 1))
            return markdownLink(text: url, source: url)
        }

        output = replace(output, pattern: #"\$([^$\n]+)\$"#) { match, source in
            source.substring(with: match.range(at: 1))
        }

        output = replace(output, pattern: #"==([^=\n]+)=="#) { match, source in
            source.substring(with: match.range(at: 1))
        }

        return output
    }

    private static func markdownLink(text: String, source: String) -> String {
        "[\(text)](\(markdownDestination(source)))"
    }

    private static func markdownDestination(_ source: String) -> String {
        if source.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || source.contains(")") {
            return "<\(source)>"
        }

        return source
    }

    private static func replace(
        _ value: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        transform: (NSTextCheckingResult, NSString) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return value
        }

        let source = value as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var result = ""
        var cursor = 0

        for match in regex.matches(in: value, range: fullRange) {
            if match.range.location > cursor {
                result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            result += transform(match, source)
            cursor = match.range.location + match.range.length
        }

        if cursor < source.length {
            result += source.substring(from: cursor)
        }

        return result
    }
}

enum MarkdownPreviewParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        parseDocument(text).blocks
    }

    static func parseDocument(_ text: String) -> MarkdownPreviewDocument {
        let lines = text.components(separatedBy: .newlines)
        let headings = MarkdownDocumentInfo.headings(in: text)
        let references = references(in: text)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if index == 0, trimmed == "---" {
                let startIndex = index
                var yamlLines: [String] = []
                var didCloseFrontMatter = false
                index += 1
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if current == "---" || current == "..." {
                        index += 1
                        didCloseFrontMatter = true
                        blocks.append(MarkdownBlock(kind: .frontMatter(yamlLines.joined(separator: "\n"))))
                        break
                    }
                    yamlLines.append(lines[index])
                    index += 1
                }
                if didCloseFrontMatter {
                    continue
                }
                index = startIndex
            }

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.lowercased() == "[toc]" {
                blocks.append(MarkdownBlock(kind: .toc(headings)))
                index += 1
                continue
            }

            if trimmed == "$$" {
                var mathLines: [String] = []
                index += 1
                while index < lines.count {
                    let current = lines[index]
                    if current.trimmingCharacters(in: .whitespaces) == "$$" {
                        index += 1
                        break
                    }
                    mathLines.append(current)
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .math(mathLines.joined(separator: "\n"))))
                continue
            }

            if isFence(trimmed) {
                let fenceInfo = parseFence(trimmed)
                let fence = fenceInfo.marker
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let current = lines[index]
                    if current.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        index += 1
                        break
                    }
                    codeLines.append(current)
                    index += 1
                }
                let code = codeLines.joined(separator: "\n")
                if let language = fenceInfo.language,
                   ["mermaid", "sequence", "flow"].contains(language.lowercased()) {
                    blocks.append(MarkdownBlock(kind: .diagram(language: language, text: code)))
                } else {
                    blocks.append(MarkdownBlock(kind: .code(language: fenceInfo.language, text: code)))
                }
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(MarkdownBlock(kind: .heading(level: heading.level, text: heading.text)))
                index += 1
                continue
            }

            if isRule(trimmed) {
                blocks.append(MarkdownBlock(kind: .rule))
                index += 1
                continue
            }

            if let parsedTable = parseTable(lines: lines, startIndex: index) {
                blocks.append(MarkdownBlock(kind: .table(parsedTable.table)))
                index = parsedTable.nextIndex
                continue
            }

            if let image = parseImage(trimmed) ?? parseHTMLImage(trimmed) {
                blocks.append(MarkdownBlock(kind: .image(image)))
                index += 1
                continue
            }

            if let media = parseHTMLMedia(trimmed) {
                blocks.append(MarkdownBlock(kind: .htmlMedia(media)))
                index += 1
                continue
            }

            if let reference = parseReferenceDefinition(trimmed) {
                blocks.append(MarkdownBlock(kind: .linkReference(reference)))
                index += 1
                continue
            }

            if let footnote = parseFootnoteDefinition(trimmed) {
                blocks.append(MarkdownBlock(kind: .footnoteDefinition(label: footnote.label, text: footnote.text)))
                index += 1
                continue
            }

            if let firstItem = parseUnorderedItem(line) {
                var items = [firstItem]
                index += 1
                while index < lines.count {
                    guard let item = parseUnorderedItem(lines[index]) else { break }
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .unorderedList(items)))
                continue
            }

            if let firstItem = parseOrderedItem(line) {
                var items = [firstItem]
                index += 1
                while index < lines.count {
                    guard let item = parseOrderedItem(lines[index]) else { break }
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .orderedList(items)))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    quoteLines.append(stripQuoteMarker(current))
                    index += 1
                }
                if let callout = parseCallout(quoteLines) {
                    blocks.append(MarkdownBlock(kind: .callout(title: callout.title, text: callout.text)))
                } else {
                    blocks.append(MarkdownBlock(kind: .quote(quoteLines.joined(separator: "\n"))))
                }
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let current = lines[index].trimmingCharacters(in: .whitespaces)
                guard !current.isEmpty, !isBlockStart(current) else { break }
                paragraphLines.append(current)
                index += 1
            }
            blocks.append(MarkdownBlock(kind: .paragraph(paragraphLines.joined(separator: " "))))
        }

        return MarkdownPreviewDocument(blocks: blocks, references: references)
    }

    private static func isBlockStart(_ line: String) -> Bool {
        isFence(line)
            || line == "$$"
            || line.lowercased() == "[toc]"
            || parseHeading(line) != nil
            || isRule(line)
            || parseImage(line) != nil
            || parseHTMLImage(line) != nil
            || parseHTMLMedia(line) != nil
            || parseReferenceDefinition(line) != nil
            || parseFootnoteDefinition(line) != nil
            || parseUnorderedItem(line) != nil
            || parseOrderedItem(line) != nil
            || line.hasPrefix(">")
    }

    private static func isFence(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
    }

    private static func parseFence(_ line: String) -> (marker: String, language: String?) {
        let marker = line.hasPrefix("~~~") ? "~~~" : "```"
        let language = line.dropFirst(marker.count)
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .first
            .map(String.init)

        return (marker, language?.isEmpty == true ? nil : language)
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" }
            || compact.allSatisfy { $0 == "*" }
            || compact.allSatisfy { $0 == "_" }
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level),
              line.dropFirst(level).first?.isWhitespace == true else {
            return nil
        }

        let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func parseUnorderedItem(_ line: String) -> MarkdownListItem? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)([-*+])\s+(.+)$"#) else {
            return nil
        }

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange) else {
            return nil
        }

        let indent = indentLevel(nsLine.substring(with: match.range(at: 1)))
        let rawText = nsLine.substring(with: match.range(at: 3))
        let parsed = parseTask(rawText)
        return MarkdownListItem(text: parsed.text, checked: parsed.checked, indentLevel: indent)
    }

    private static func parseOrderedItem(_ line: String) -> MarkdownListItem? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)\d+[.)]\s+(.+)$"#) else {
            return nil
        }

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange) else {
            return nil
        }

        return MarkdownListItem(
            text: nsLine.substring(with: match.range(at: 2)),
            checked: nil,
            indentLevel: indentLevel(nsLine.substring(with: match.range(at: 1)))
        )
    }

    private static func indentLevel(_ value: String) -> Int {
        let width = value.reduce(0) { result, character in
            result + (character == "\t" ? 4 : 1)
        }
        return max(0, width / 2)
    }

    private static func parseTable(lines: [String], startIndex: Int) -> (table: MarkdownTable, nextIndex: Int)? {
        guard startIndex + 1 < lines.count else { return nil }

        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let delimiterLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)
        guard headerLine.contains("|"),
              delimiterLine.contains("|") else {
            return nil
        }

        let headers = splitTableRow(headerLine)
        let delimiters = splitTableRow(delimiterLine)
        guard !headers.isEmpty,
              headers.count == delimiters.count,
              delimiters.allSatisfy(isTableDelimiter) else {
            return nil
        }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count {
            let current = lines[index].trimmingCharacters(in: .whitespaces)
            guard current.contains("|"), !current.isEmpty else { break }
            let row = splitTableRow(current)
            guard !row.isEmpty else { break }
            rows.append(row)
            index += 1
        }

        let table = MarkdownTable(
            headers: headers,
            alignments: delimiters.map(tableAlignment),
            rows: rows
        )
        return (table, index)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var value = line
        if value.hasPrefix("|") {
            value.removeFirst()
        }
        if value.hasSuffix("|") {
            value.removeLast()
        }

        return value.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableDelimiter(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" || $0 == ":" }
            && trimmed.contains("-")
    }

    private static func tableAlignment(_ value: String) -> MarkdownTableAlignment {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(":"), trimmed.hasSuffix(":") {
            return .center
        }
        if trimmed.hasSuffix(":") {
            return .trailing
        }
        return .leading
    }

    private static func parseImage(_ line: String) -> MarkdownImage? {
        guard let regex = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\((.*)\)$"#) else {
            return nil
        }

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange) else {
            return nil
        }

        let alt = nsLine.substring(with: match.range(at: 1))
        let body = nsLine.substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespaces)
        let parsed = parseImageBody(body)
        guard !parsed.source.isEmpty else { return nil }

        let source = parsed.source
        let title = parsed.title
        return MarkdownImage(alt: alt, source: source, title: title)
    }

    private static func parseImageBody(_ body: String) -> (source: String, title: String?) {
        guard let regex = try? NSRegularExpression(pattern: #"^(.*?)(?:\s+"([^"]*)")\s*$"#) else {
            return (body, nil)
        }

        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)
        if let match = regex.firstMatch(in: body, range: fullRange),
           match.range(at: 1).location != NSNotFound,
           match.range(at: 2).location != NSNotFound {
            return (
                trimAngleBrackets(nsBody.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)),
                nsBody.substring(with: match.range(at: 2))
            )
        }

        return (trimAngleBrackets(body), nil)
    }

    private static func trimAngleBrackets(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), trimmed.count >= 2 else {
            return trimmed
        }

        return String(trimmed.dropFirst().dropLast())
    }

    private static func parseHTMLImage(_ line: String) -> MarkdownImage? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("<img "),
              trimmed.hasSuffix(">") else {
            return nil
        }

        let attributes = htmlAttributes(in: trimmed)
        guard let source = attributes["src"], !source.isEmpty else {
            return nil
        }

        return MarkdownImage(
            alt: attributes["alt"] ?? "",
            source: source,
            title: attributes["title"]
        )
    }

    private static func parseHTMLMedia(_ line: String) -> MarkdownHTMLMedia? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let tag = htmlTag(in: trimmed),
              ["audio", "iframe", "video"].contains(tag) else {
            return nil
        }

        let attributes = htmlAttributes(in: trimmed)
        guard let source = attributes["src"], !source.isEmpty else {
            return nil
        }

        return MarkdownHTMLMedia(
            tag: tag,
            source: source,
            title: attributes["title"],
            width: attributes["width"],
            height: attributes["height"]
        )
    }

    private static func htmlTag(in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^<\s*([A-Za-z][A-Za-z0-9-]*)\b"#) else {
            return nil
        }

        let nsValue = value as NSString
        let fullRange = NSRange(location: 0, length: nsValue.length)
        guard let match = regex.firstMatch(in: value, range: fullRange) else {
            return nil
        }

        return nsValue.substring(with: match.range(at: 1)).lowercased()
    }

    static func references(in text: String) -> [String: MarkdownLinkReference] {
        var result: [String: MarkdownLinkReference] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let reference = parseReferenceDefinition(line.trimmingCharacters(in: .whitespaces)) else {
                continue
            }
            result[reference.key] = reference
        }
        return result
    }

    static func normalizeReferenceLabel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private static func parseReferenceDefinition(_ line: String) -> MarkdownLinkReference? {
        guard let regex = try? NSRegularExpression(pattern: #"^\[([^\]]+)\]:\s+(.+)$"#) else {
            return nil
        }

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange) else {
            return nil
        }

        let label = nsLine.substring(with: match.range(at: 1))
        guard !label.hasPrefix("^") else {
            return nil
        }

        let parsed = parseImageBody(nsLine.substring(with: match.range(at: 2)))
        guard !parsed.source.isEmpty else {
            return nil
        }

        return MarkdownLinkReference(
            label: label,
            key: normalizeReferenceLabel(label),
            source: parsed.source,
            title: parsed.title
        )
    }

    private static func parseFootnoteDefinition(_ line: String) -> (label: String, text: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^\[\^([^\]]+)\]:\s*(.*)$"#) else {
            return nil
        }

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange) else {
            return nil
        }

        return (
            nsLine.substring(with: match.range(at: 1)),
            nsLine.substring(with: match.range(at: 2))
        )
    }

    private static func htmlAttributes(in value: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#
        ) else {
            return [:]
        }

        let nsValue = value as NSString
        let fullRange = NSRange(location: 0, length: nsValue.length)
        var attributes: [String: String] = [:]

        for match in regex.matches(in: value, range: fullRange) {
            let key = nsValue.substring(with: match.range(at: 1)).lowercased()
            if match.range(at: 2).location != NSNotFound {
                attributes[key] = nsValue.substring(with: match.range(at: 2))
            } else if match.range(at: 3).location != NSNotFound {
                attributes[key] = nsValue.substring(with: match.range(at: 3))
            }
        }

        return attributes
    }

    private static func parseCallout(_ lines: [String]) -> (title: String, text: String)? {
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespaces),
              firstLine.hasPrefix("[!"),
              let closing = firstLine.firstIndex(of: "]") else {
            return nil
        }

        let kind = firstLine[firstLine.index(firstLine.startIndex, offsetBy: 2)..<closing]
        let suffix = firstLine[firstLine.index(after: closing)...]
            .trimmingCharacters(in: .whitespaces)
        let title = suffix.isEmpty ? String(kind).capitalized : suffix
        let body = lines.dropFirst().joined(separator: "\n")
        return (title, body)
    }

    private static func parseTask(_ rawText: String) -> (text: String, checked: Bool?) {
        if rawText.hasPrefix("[ ] ") {
            return (String(rawText.dropFirst(4)), false)
        }

        if rawText.lowercased().hasPrefix("[x] ") {
            return (String(rawText.dropFirst(4)), true)
        }

        return (rawText, nil)
    }

    private static func stripQuoteMarker(_ line: String) -> String {
        let value = line.dropFirst()
        if value.first?.isWhitespace == true {
            return String(value.dropFirst())
        }
        return String(value)
    }
}
