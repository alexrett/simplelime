import Foundation

enum MarkdownTableFormatter {
    static func format(_ text: String) -> String {
        let hasTrailingNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if hasTrailingNewline {
            lines.removeLast()
        }

        var formatted: [String] = []
        var index = 0

        while index < lines.count {
            if let block = tableBlock(startingAt: index, in: lines) {
                formatted.append(contentsOf: format(block))
                index = block.endIndex
            } else {
                formatted.append(lines[index])
                index += 1
            }
        }

        let joined = formatted.joined(separator: "\n")
        return hasTrailingNewline ? "\(joined)\n" : joined
    }

    private struct Row {
        var indent: String
        var cells: [String]
    }

    private enum Alignment {
        case plain
        case left
        case center
        case right
    }

    private struct Block {
        var rows: [Row]
        var alignments: [Alignment]
        var endIndex: Int
    }

    private static func tableBlock(startingAt start: Int, in lines: [String]) -> Block? {
        guard start + 1 < lines.count,
              let header = parseRow(lines[start]),
              let alignments = parseSeparator(lines[start + 1]) else {
            return nil
        }

        var rows = [header]
        var index = start + 2

        while index < lines.count, let row = parseRow(lines[index]) {
            rows.append(row)
            index += 1
        }

        return Block(rows: rows, alignments: alignments, endIndex: index)
    }

    private static func parseRow(_ line: String) -> Row? {
        guard line.contains("|") else { return nil }

        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") {
            content.removeFirst()
        }
        if content.hasSuffix("|") {
            content.removeLast()
        }

        let cells = content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard cells.count > 1 else { return nil }
        return Row(indent: indent, cells: cells)
    }

    private static func parseSeparator(_ line: String) -> [Alignment]? {
        guard let row = parseRow(line) else { return nil }
        var alignments: [Alignment] = []

        for cell in row.cells {
            let marker = cell.replacingOccurrences(of: " ", with: "")
            let hyphenCount = marker.filter { $0 == "-" }.count
            guard hyphenCount >= 3,
                  marker.allSatisfy({ $0 == "-" || $0 == ":" }) else {
                return nil
            }

            let starts = marker.hasPrefix(":")
            let ends = marker.hasSuffix(":")
            switch (starts, ends) {
            case (true, true):
                alignments.append(.center)
            case (true, false):
                alignments.append(.left)
            case (false, true):
                alignments.append(.right)
            case (false, false):
                alignments.append(.plain)
            }
        }

        return alignments
    }

    private static func format(_ block: Block) -> [String] {
        let columnCount = max(
            block.alignments.count,
            block.rows.map(\.cells.count).max() ?? 0
        )
        let alignments = (0..<columnCount).map { index in
            block.alignments.indices.contains(index) ? block.alignments[index] : .plain
        }
        let widths = (0..<columnCount).map { column in
            max(
                3,
                block.rows.map { row in
                    row.cells.indices.contains(column) ? row.cells[column].count : 0
                }.max() ?? 0
            )
        }
        let indent = block.rows.first?.indent ?? ""
        var lines: [String] = []

        if let header = block.rows.first {
            lines.append(format(row: header, widths: widths, alignments: alignments, indent: indent))
        }

        lines.append(formatSeparator(widths: widths, alignments: alignments, indent: indent))

        for row in block.rows.dropFirst() {
            lines.append(format(row: row, widths: widths, alignments: alignments, indent: indent))
        }

        return lines
    }

    private static func format(row: Row, widths: [Int], alignments: [Alignment], indent: String) -> String {
        let cells = widths.indices.map { index -> String in
            let value = row.cells.indices.contains(index) ? row.cells[index] : ""
            return pad(value, width: widths[index], alignment: alignments[index])
        }
        return "\(indent)| \(cells.joined(separator: " | ")) |"
    }

    private static func formatSeparator(widths: [Int], alignments: [Alignment], indent: String) -> String {
        let cells = zip(widths, alignments).map { width, alignment in
            switch alignment {
            case .plain:
                return String(repeating: "-", count: width)
            case .left:
                return ":" + String(repeating: "-", count: max(2, width - 1))
            case .right:
                return String(repeating: "-", count: max(2, width - 1)) + ":"
            case .center:
                return ":" + String(repeating: "-", count: max(1, width - 2)) + ":"
            }
        }
        return "\(indent)| \(cells.joined(separator: " | ")) |"
    }

    private static func pad(_ value: String, width: Int, alignment: Alignment) -> String {
        let deficit = max(0, width - value.count)
        switch alignment {
        case .right:
            return String(repeating: " ", count: deficit) + value
        case .center:
            let leading = deficit / 2
            let trailing = deficit - leading
            return String(repeating: " ", count: leading) + value + String(repeating: " ", count: trailing)
        case .plain, .left:
            return value + String(repeating: " ", count: deficit)
        }
    }
}
