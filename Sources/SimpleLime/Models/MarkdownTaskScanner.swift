import Foundation

enum MarkdownTaskScanner {
    private static let checklistPattern = #"(?m)^([ \t]*[-*+][ \t]+\[)([ xX>/\-])(\][ \t]+)([^\r\n]*)$"#
    private static let naturalTaskPattern = #"(?im)^([ \t]*(?:(?:[-*+][ \t]+)|(?://|#|--|;|<!--)[ \t]*)?)((?:TODO|FIXME|BUG|ACTION(?:[ -]?ITEM)?|FOLLOW[ -]?UP|NEXT[ -]?STEP|IN[ -]?PROGRESS|DONE|COMPLETED))\s*[:\-]\s*(.*?)\s*(?:-->)?[ \t]*$"#
    private static let inferredTaskPatterns = [
        #"(?i)^\s*(?:(?:[-*+][ \t]+)|(?://|#|--|;)[ \t]*)?(?:(?:we|i|you|they|team|the team|user|users)[ \t]+)?(?:need|needs|should|must)[ \t]+(?:to[ \t]+)?(.+)$"#,
        #"(?i)^\s*(?:(?:[-*+][ \t]+)|(?://|#|--|;)[ \t]*)?(?:(?:we|i|you|they|team|the team|user|users)[ \t]+)?(?:have|has)[ \t]+to[ \t]+(.+)$"#,
        #"(?i)^\s*(?:(?:[-*+][ \t]+)|(?://|#|--|;)[ \t]*)?(?:please|remember to|do not forget to|don't forget to)[ \t]+(.+)$"#,
        #"(?i)^\s*(?:(?:[-*+][ \t]+)|(?://|#|--|;)[ \t]*)?(?:next step|follow up)[ \t]*(?:is[ \t]+to|:|-)[ \t]*(.+)$"#,
        #"(?i)^\s*(?:(?:[-*+][ \t]+)|(?://|#|--|;)[ \t]*)?(?:нужно|надо|необходимо|следует|давай)[ \t]+(.+)$"#
    ]

    static func scan(_ text: String) -> [MarkdownTaskMatch] {
        let checklist = checklistMatches(in: text)
        let natural = naturalTaskMatches(in: text, occupiedLineRanges: Set(checklist.map(\.lineRange)))
        let inferred = inferredTaskMatches(
            in: text,
            occupiedLineRanges: Set((checklist + natural).map(\.lineRange))
        )
        return checklist + natural + inferred
    }

    private static func checklistMatches(in text: String) -> [MarkdownTaskMatch] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0,
              let regex = try? NSRegularExpression(pattern: checklistPattern) else {
            return []
        }

        return regex.matches(in: text, range: fullRange).compactMap { match in
            guard match.numberOfRanges >= 5 else { return nil }
            let titleRange = match.range(at: 4)
            let markerRange = match.range(at: 2)
            guard titleRange.location != NSNotFound,
                  markerRange.location != NSNotFound else {
                return nil
            }

            let title = nsText.substring(with: titleRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let lineRange = nsText.lineRange(for: match.range)
            let marker = nsText.substring(with: markerRange)

            return MarkdownTaskMatch(
                title: title,
                status: TaskBoardStatus.markdownStatus(for: marker),
                lineNumber: lineNumber(at: match.range.location, in: text),
                lineRange: TextRange(lineRange),
                markerRange: TextRange(markerRange),
                updateMode: .markdownMarker
            )
        }
    }

    private static func naturalTaskMatches(
        in text: String,
        occupiedLineRanges: Set<TextRange>
    ) -> [MarkdownTaskMatch] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0,
              let regex = try? NSRegularExpression(pattern: naturalTaskPattern) else {
            return []
        }

        return regex.matches(in: text, range: fullRange).compactMap { match in
            guard match.numberOfRanges >= 4 else { return nil }
            let keywordRange = match.range(at: 2)
            let titleRange = match.range(at: 3)
            guard keywordRange.location != NSNotFound,
                  titleRange.location != NSNotFound else {
                return nil
            }

            let lineRange = nsText.lineRange(for: match.range)
            let textRange = TextRange(lineRange)
            guard !occupiedLineRanges.contains(textRange) else { return nil }

            let title = nsText.substring(with: titleRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let keyword = nsText.substring(with: keywordRange)
            return MarkdownTaskMatch(
                title: title,
                status: naturalStatus(for: keyword),
                lineNumber: lineNumber(at: match.range.location, in: text),
                lineRange: textRange,
                markerRange: TextRange(keywordRange),
                updateMode: .lineToMarkdownChecklist
            )
        }
    }

    private static func inferredTaskMatches(
        in text: String,
        occupiedLineRanges: Set<TextRange>
    ) -> [MarkdownTaskMatch] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        let regexes = inferredTaskPatterns.compactMap {
            try? NSRegularExpression(pattern: $0)
        }
        guard !regexes.isEmpty else { return [] }

        var matches: [MarkdownTaskMatch] = []
        var location = 0
        var isInsideFence = false

        while location < nsText.length {
            let enclosingRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let textRange = TextRange(enclosingRange)
            let bodyRange = lineBodyRange(enclosingRange, in: nsText)
            let body = nsText.substring(with: bodyRange)
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                isInsideFence.toggle()
            } else if !isInsideFence,
                      !occupiedLineRanges.contains(textRange),
                      shouldInspectPlainLanguageLine(trimmed) {
                for regex in regexes {
                    let localRange = NSRange(location: 0, length: (body as NSString).length)
                    guard let match = regex.firstMatch(in: body, range: localRange),
                          match.numberOfRanges >= 2 else {
                        continue
                    }

                    let captureRange = match.range(at: 1)
                    guard captureRange.location != NSNotFound,
                          let title = normalizedInferredTitle((body as NSString).substring(with: captureRange)) else {
                        continue
                    }

                    matches.append(
                        MarkdownTaskMatch(
                            title: title,
                            status: .todo,
                            lineNumber: lineNumber(at: enclosingRange.location, in: text),
                            lineRange: textRange,
                            markerRange: TextRange(
                                location: bodyRange.location + captureRange.location,
                                length: captureRange.length
                            ),
                            updateMode: .lineToMarkdownChecklist
                        )
                    )
                    break
                }
            }

            let nextLocation = enclosingRange.location + max(enclosingRange.length, 1)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return matches
    }

    private static func naturalStatus(for keyword: String) -> TaskBoardStatus {
        switch keyword
            .replacingOccurrences(of: "-", with: " ")
            .lowercased() {
        case "done", "completed":
            return .done
        case "in progress":
            return .inProgress
        default:
            return .todo
        }
    }

    private static func shouldInspectPlainLanguageLine(_ line: String) -> Bool {
        guard line.count >= 8,
              line.count <= 220,
              !line.hasSuffix("?"),
              !line.hasPrefix("|"),
              !line.hasPrefix(">"),
              !line.hasPrefix("# "),
              !line.hasPrefix("## "),
              !line.hasPrefix("### "),
              !line.contains("://") else {
            return false
        }

        return true
    }

    private static func normalizedInferredTitle(_ rawTitle: String) -> String? {
        var title = rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(?i:to)[ \t]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\.;:]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard title.count >= 4,
              title.count <= 180,
              !title.hasSuffix("?"),
              !title.hasPrefix("http://"),
              !title.hasPrefix("https://") else {
            return nil
        }

        let first = title.removeFirst()
        return String(first).uppercased() + title
    }

    private static func lineBodyRange(_ lineRange: NSRange, in text: NSString) -> NSRange {
        var length = lineRange.length
        while length > 0 {
            let character = text.character(at: lineRange.location + length - 1)
            guard character == 10 || character == 13 else { break }
            length -= 1
        }
        return NSRange(location: lineRange.location, length: length)
    }

    private static func lineNumber(at location: Int, in text: String) -> Int {
        let nsText = text as NSString
        let target = min(max(0, location), nsText.length)
        var currentLine = 1
        var currentLocation = 0

        while currentLocation < target {
            let lineRange = nsText.lineRange(for: NSRange(location: currentLocation, length: 0))
            let nextLocation = lineRange.location + max(lineRange.length, 1)
            guard nextLocation > currentLocation else { break }
            currentLocation = nextLocation
            currentLine += 1
        }

        return currentLine
    }
}
