import Foundation

enum EditorTypingRules {
    static func shouldAutoCloseQuote(_ replacement: String, text: NSString, range: NSRange) -> Bool {
        guard replacement == "\"" || replacement == "'" else { return true }

        let safeRange = normalized(range, textLength: text.length)
        if safeRange.length > 0 {
            return true
        }

        guard safeRange.location > 0 else { return true }

        let previous = text.substring(with: NSRange(location: safeRange.location - 1, length: 1))
        return previous.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    }

    static func containsMarkdownListLine(text: NSString, ranges: [NSRange]) -> Bool {
        let checkedRanges = ranges.isEmpty ? [NSRange(location: 0, length: 0)] : ranges

        return checkedRanges.contains { range in
            lineTexts(intersecting: normalized(range, textLength: text.length), in: text)
                .contains(where: isMarkdownListLine)
        }
    }

    static func isMarkdownListLine(_ line: String) -> Bool {
        let pattern = #"^\s*(?:[-*+]\s+\[[ xX]\](?:\s+|$)|[-*+](?:\s+|$)|\d+[.)](?:\s+|$)|>\s?)"#
        return line.range(of: pattern, options: .regularExpression) != nil
    }

    private static func normalized(_ range: NSRange, textLength: Int) -> NSRange {
        let location = min(max(0, range.location), textLength)
        let length = min(max(0, range.length), textLength - location)
        return NSRange(location: location, length: length)
    }

    private static func lineTexts(intersecting range: NSRange, in text: NSString) -> [String] {
        guard text.length > 0 else { return [""] }

        if range.length == 0 {
            return [text.substring(with: text.lineRange(for: NSRange(location: range.location, length: 0)))]
        }

        var output: [String] = []
        var location = range.location
        let end = range.location + range.length

        while location < end {
            let lineRange = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
            output.append(text.substring(with: lineRange))

            let nextLocation = lineRange.location + max(lineRange.length, 1)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return output
    }
}
