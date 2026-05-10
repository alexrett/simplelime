import Foundation

struct MarkdownHeading: Identifiable, Equatable {
    let id: String
    let level: Int
    let title: String
    let lineNumber: Int
    let location: Int
}

struct TextDocumentStats: Equatable {
    let characters: Int
    let words: Int
    let lines: Int
    let readingMinutes: Int
}

enum MarkdownDocumentInfo {
    static func headings(in text: String) -> [MarkdownHeading] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var headings: [MarkdownHeading] = []
        var location = 0
        var lineNumber = 1

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let line = nsText.substring(with: contentRange(for: lineRange, in: nsText))

            if let parsed = parseHeading(line) {
                headings.append(
                    MarkdownHeading(
                        id: "\(lineRange.location):\(parsed.level):\(parsed.title)",
                        level: parsed.level,
                        title: parsed.title,
                        lineNumber: lineNumber,
                        location: lineRange.location
                    )
                )
            }

            let nextLocation = lineRange.location + max(lineRange.length, 1)
            guard nextLocation > location else { break }
            location = nextLocation
            lineNumber += 1
        }

        return headings
    }

    static func stats(for text: String) -> TextDocumentStats {
        let nsText = text as NSString
        let characterCount = nsText.length
        let lineCount = text.isEmpty ? 1 : text.components(separatedBy: .newlines).count
        let wordCount = countWords(in: text)
        let readingMinutes = wordCount == 0 ? 0 : max(1, Int(ceil(Double(wordCount) / 225.0)))

        return TextDocumentStats(
            characters: characterCount,
            words: wordCount,
            lines: lineCount,
            readingMinutes: readingMinutes
        )
    }

    static func currentHeading(in text: String, selectionRanges: [TextRange]) -> MarkdownHeading? {
        let headings = headings(in: text)
        guard !headings.isEmpty else { return nil }

        let location = selectionRanges.last?.location ?? 0
        return headings.last { $0.location <= location } ?? headings.first
    }

    static func lineNumber(at location: Int, in text: String) -> Int {
        let nsText = text as NSString
        let location = min(max(0, location), nsText.length)
        guard location > 0 else { return 1 }

        let prefix = nsText.substring(to: location)
        return prefix.reduce(1) { count, character in
            character == "\n" ? count + 1 : count
        }
    }

    private static func parseHeading(_ rawLine: String) -> (level: Int, title: String)? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        let level = line.prefix { $0 == "#" }.count

        guard (1...6).contains(level),
              line.dropFirst(level).first?.isWhitespace == true else {
            return nil
        }

        let title = line.dropFirst(level)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)

        guard !title.isEmpty else { return nil }
        return (level, title)
    }

    private static func contentRange(for lineRange: NSRange, in text: NSString) -> NSRange {
        var length = min(lineRange.length, max(0, text.length - lineRange.location))
        while length > 0 {
            let character = text.character(at: lineRange.location + length - 1)
            guard character == 10 || character == 13 else { break }
            length -= 1
        }

        return NSRange(location: lineRange.location, length: length)
    }

    private static func countWords(in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}_]+") else {
            return 0
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.numberOfMatches(in: text, range: range)
    }
}
