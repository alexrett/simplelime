import Foundation

struct StructuredFoldRange: Codable, Equatable, Hashable, Identifiable {
    var startLine: Int
    var endLine: Int
    var title: String

    var id: String {
        "\(startLine):\(endLine)"
    }

    var foldedLineCount: Int {
        max(0, endLine - startLine)
    }

    func contains(line: Int) -> Bool {
        startLine <= line && line <= endLine
    }
}

enum StructuredTextFolder {
    static func foldableRanges(in text: String, language: EditorLanguage) -> [StructuredFoldRange] {
        switch language {
        case .markdown:
            return markdownRanges(in: text)
        case .json:
            return jsonRanges(in: text)
        case .yaml:
            return yamlRanges(in: text)
        default:
            return []
        }
    }

    static func bestRange(containing line: Int, in text: String, language: EditorLanguage) -> StructuredFoldRange? {
        foldableRanges(in: text, language: language)
            .filter { $0.contains(line: line) }
            .sorted { first, second in
                let firstSize = first.endLine - first.startLine
                let secondSize = second.endLine - second.startLine
                if firstSize == secondSize {
                    return first.startLine > second.startLine
                }
                return firstSize < secondSize
            }
            .first
    }

    static func lineNumber(at utf16Location: Int, in text: String) -> Int {
        let nsText = text as NSString
        let safeLocation = min(max(0, utf16Location), nsText.length)
        var lineNumber = 1
        var location = 0

        while location < safeLocation, location < nsText.length {
            let range = nsText.lineRange(for: NSRange(location: location, length: 0))
            let nextLocation = range.location + max(range.length, 1)
            guard nextLocation > location, nextLocation <= safeLocation else { break }
            lineNumber += 1
            location = nextLocation
        }

        return lineNumber
    }

    static func displayLineNumber(forSourceLine sourceLine: Int, foldedRanges: [StructuredFoldRange]) -> Int {
        let sourceLine = max(1, sourceLine)
        var displayLine = sourceLine

        for range in normalizedFoldedRanges(foldedRanges) where range.startLine < sourceLine {
            if sourceLine <= range.endLine {
                return displayLine - max(0, sourceLine - range.startLine)
            }
            displayLine -= range.foldedLineCount
        }

        return max(1, displayLine)
    }

    static func sourceLineNumber(forDisplayLine displayLine: Int, foldedRanges: [StructuredFoldRange]) -> Int {
        let displayLine = max(1, displayLine)
        var sourceLine = displayLine

        for range in normalizedFoldedRanges(foldedRanges) {
            let foldedDisplayLine = displayLineNumber(forSourceLine: range.startLine, foldedRanges: foldedRanges)
            if displayLine == foldedDisplayLine {
                return range.startLine
            }

            if displayLine > foldedDisplayLine {
                sourceLine += range.foldedLineCount
            }
        }

        return max(1, sourceLine)
    }

    static func foldedText(for text: String, foldedRanges: [StructuredFoldRange]) -> String {
        guard !foldedRanges.isEmpty else { return text }

        let lineRanges = Self.lineRanges(in: text)
        guard !lineRanges.isEmpty else { return text }

        let validRanges = foldedRanges
            .filter { $0.startLine >= 1 && $0.endLine > $0.startLine && $0.endLine <= lineRanges.count }
            .sorted { first, second in
                if first.startLine == second.startLine {
                    return first.endLine > second.endLine
                }
                return first.startLine < second.startLine
            }
            .reduce(into: [StructuredFoldRange]()) { result, range in
                guard result.last?.endLine ?? 0 < range.startLine else { return }
                result.append(range)
            }

        guard !validRanges.isEmpty else { return text }

        let nsText = text as NSString
        let mutable = NSMutableString(string: text)
        for range in validRanges.reversed() {
            let startRange = lineRanges[range.startLine - 1]
            let endRange = lineRanges[range.endLine - 1]
            let replaceRange = NSRange(
                location: startRange.location,
                length: endRange.location + endRange.length - startRange.location
            )
            let firstLine = nsText.substring(with: contentRange(for: startRange, in: nsText))
            let suffix = range.foldedLineCount == 1 ? "line" : "lines"
            mutable.replaceCharacters(
                in: replaceRange,
                with: "\(firstLine)  ... \(range.foldedLineCount) \(suffix) folded\n"
            )
        }

        return mutable as String
    }

    private static func normalizedFoldedRanges(_ ranges: [StructuredFoldRange]) -> [StructuredFoldRange] {
        ranges
            .filter { $0.startLine >= 1 && $0.endLine > $0.startLine }
            .sorted { first, second in
                if first.startLine == second.startLine {
                    return first.endLine > second.endLine
                }
                return first.startLine < second.startLine
            }
            .reduce(into: [StructuredFoldRange]()) { result, range in
                guard result.last?.endLine ?? 0 < range.startLine else { return }
                result.append(range)
            }
    }

    private static func markdownRanges(in text: String) -> [StructuredFoldRange] {
        let lines = lineContents(in: text)
        var ranges: [StructuredFoldRange] = []
        var headingStack: [(level: Int, line: Int, title: String)] = []
        var fence: String?

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if fence == marker {
                    fence = nil
                } else if fence == nil {
                    fence = marker
                }
                continue
            }

            guard fence == nil,
                  let heading = markdownHeading(in: line) else {
                continue
            }

            while let previous = headingStack.last, previous.level >= heading.level {
                headingStack.removeLast()
                if lineNumber - 1 > previous.line {
                    ranges.append(
                        StructuredFoldRange(
                            startLine: previous.line,
                            endLine: lineNumber - 1,
                            title: previous.title
                        )
                    )
                }
            }

            headingStack.append((heading.level, lineNumber, heading.title))
        }

        let lastLine = lines.count
        for heading in headingStack.reversed() where lastLine > heading.line {
            ranges.append(
                StructuredFoldRange(
                    startLine: heading.line,
                    endLine: lastLine,
                    title: heading.title
                )
            )
        }

        return ranges.sorted { $0.startLine < $1.startLine }
    }

    private static func markdownHeading(in line: String) -> (level: Int, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }

        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count),
              trimmed.dropFirst(hashes.count).first == " " else {
            return nil
        }

        let title = trimmed
            .dropFirst(hashes.count)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
        return title.isEmpty ? nil : (hashes.count, title)
    }

    private static func jsonRanges(in text: String) -> [StructuredFoldRange] {
        var ranges: [StructuredFoldRange] = []
        var stack: [(character: Character, line: Int, title: String)] = []
        var lineNumber = 1
        var isInString = false
        var isEscaped = false
        let lines = lineContents(in: text)

        for character in text {
            if character == "\n" {
                lineNumber += 1
                continue
            }

            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                continue
            }

            if character == "\"" {
                isInString = true
            } else if character == "{" || character == "[" {
                let title = lines.indices.contains(lineNumber - 1)
                    ? lines[lineNumber - 1].trimmingCharacters(in: .whitespaces)
                    : String(character)
                stack.append((character, lineNumber, title))
            } else if character == "}" || character == "]" {
                guard let opening = stack.last else { continue }
                let matches = (opening.character == "{" && character == "}") ||
                    (opening.character == "[" && character == "]")
                guard matches else { continue }
                stack.removeLast()
                if lineNumber > opening.line {
                    ranges.append(
                        StructuredFoldRange(
                            startLine: opening.line,
                            endLine: lineNumber,
                            title: opening.title
                        )
                    )
                }
            }
        }

        return ranges.sorted { $0.startLine < $1.startLine }
    }

    private static func yamlRanges(in text: String) -> [StructuredFoldRange] {
        let lines = lineContents(in: text)
        var ranges: [StructuredFoldRange] = []

        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let indent = leadingSpaceCount(in: line)
            guard let childIndex = nextContentLine(after: index, in: lines),
                  leadingSpaceCount(in: lines[childIndex]) > indent else {
                continue
            }

            let isExplicitBlock = trimmed.hasSuffix(":") || trimmed.range(of: #"^-\s+[^:]+:\s*$"#, options: .regularExpression) != nil
            guard isExplicitBlock || leadingSpaceCount(in: lines[childIndex]) > indent else { continue }

            var endIndex = childIndex
            var scanIndex = childIndex + 1
            while scanIndex < lines.count {
                let candidate = lines[scanIndex]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty || candidateTrimmed.hasPrefix("#") {
                    scanIndex += 1
                    continue
                }

                guard leadingSpaceCount(in: candidate) > indent else { break }
                endIndex = scanIndex
                scanIndex += 1
            }

            if endIndex > index {
                ranges.append(
                    StructuredFoldRange(
                        startLine: index + 1,
                        endLine: endIndex + 1,
                        title: trimmed
                    )
                )
            }
        }

        return ranges
    }

    private static func nextContentLine(after index: Int, in lines: [String]) -> Int? {
        var nextIndex = index + 1
        while nextIndex < lines.count {
            let trimmed = lines[nextIndex].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                return nextIndex
            }
            nextIndex += 1
        }
        return nil
    }

    private static func leadingSpaceCount(in line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private static func lineContents(in text: String) -> [String] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        return lineRanges(in: text).map { range in
            nsText.substring(with: contentRange(for: range, in: nsText))
        }
    }

    private static func lineRanges(in text: String) -> [NSRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var ranges: [NSRange] = []
        var location = 0
        while location < nsText.length {
            let range = nsText.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(range)
            let nextLocation = range.location + max(range.length, 1)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return ranges
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
}
