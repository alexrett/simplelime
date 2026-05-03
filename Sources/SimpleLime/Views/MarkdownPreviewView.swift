import SwiftUI

struct MarkdownPreviewView: View {
    let text: String

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(text)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(blocks) { block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level, let value):
            Text(inlineMarkdown(value))
                .font(.system(size: headingSize(for: level), weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, level == 1 ? 0 : 8)

        case .paragraph(let value):
            Text(inlineMarkdown(value))
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

                        Text(inlineMarkdown(item.text))
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
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

                        Text(inlineMarkdown(item.text))
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
            }

        case .quote(let value):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 3)
                Text(inlineMarkdown(value))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)

        case .code(let value):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

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

    private func inlineMarkdown(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value)) ?? AttributedString(value)
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([MarkdownListItem])
        case orderedList([MarkdownListItem])
        case quote(String)
        case code(String)
        case rule
    }

    let id = UUID()
    let kind: Kind
}

private struct MarkdownListItem: Identifiable {
    let id = UUID()
    let text: String
    let checked: Bool?
}

private enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if isFence(trimmed) {
                let fence = String(trimmed.prefix(3))
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
                blocks.append(MarkdownBlock(kind: .code(codeLines.joined(separator: "\n"))))
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

            if let firstItem = parseUnorderedItem(trimmed) {
                var items = [firstItem]
                index += 1
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let item = parseUnorderedItem(current) else { break }
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .unorderedList(items)))
                continue
            }

            if let firstItem = parseOrderedItem(trimmed) {
                var items = [firstItem]
                index += 1
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let item = parseOrderedItem(current) else { break }
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
                blocks.append(MarkdownBlock(kind: .quote(quoteLines.joined(separator: "\n"))))
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

        return blocks
    }

    private static func isBlockStart(_ line: String) -> Bool {
        isFence(line)
            || parseHeading(line) != nil
            || isRule(line)
            || parseUnorderedItem(line) != nil
            || parseOrderedItem(line) != nil
            || line.hasPrefix(">")
    }

    private static func isFence(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
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
        let markers = ["- ", "* ", "+ "]
        guard let marker = markers.first(where: { line.hasPrefix($0) }) else {
            return nil
        }

        let rawText = String(line.dropFirst(marker.count))
        let parsed = parseTask(rawText)
        return MarkdownListItem(text: parsed.text, checked: parsed.checked)
    }

    private static func parseOrderedItem(_ line: String) -> MarkdownListItem? {
        var digitCount = 0
        for character in line {
            guard character.isNumber else { break }
            digitCount += 1
        }

        guard digitCount > 0 else { return nil }
        let suffix = line.dropFirst(digitCount)
        guard suffix.hasPrefix(". ") || suffix.hasPrefix(") ") else {
            return nil
        }

        let text = String(suffix.dropFirst(2))
        return MarkdownListItem(text: text, checked: nil)
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
