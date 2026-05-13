import Foundation

struct CompanionSuggestion: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var comment: String
    var findText: String
    var replacementText: String
    var patchText: String?
    var createdAt: Date
    var appliedAt: Date?

    var isApplied: Bool {
        appliedAt != nil
    }

    var canApplyEdit: Bool {
        hasPatchEdit || (!findText.isEmpty && findText != replacementText)
    }

    var hasPatchEdit: Bool {
        !(patchText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var canAddComment: Bool {
        !findText.isEmpty && !comment.isEmpty
    }

    init(
        id: UUID = UUID(),
        title: String,
        comment: String,
        findText: String,
        replacementText: String,
        patchText: String? = nil,
        createdAt: Date = Date(),
        appliedAt: Date? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        self.findText = findText
        self.replacementText = replacementText
        let trimmedPatch = patchText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.patchText = trimmedPatch?.isEmpty == true ? nil : trimmedPatch
        self.createdAt = createdAt
        self.appliedAt = appliedAt
    }
}

enum CompanionSuggestionParser {
    static func parse(_ rawResponse: String, now: Date = Date()) -> [CompanionSuggestion] {
        guard let data = normalizedJSONData(from: rawResponse) else { return [] }

        let decoder = JSONDecoder()
        if let response = try? decoder.decode(CompanionSuggestionResponse.self, from: data) {
            return suggestions(from: response.suggestions, now: now)
        }

        if let suggestions = try? decoder.decode([WireSuggestion].self, from: data) {
            return CompanionSuggestionParser.suggestions(from: suggestions, now: now)
        }

        return []
    }

    static let systemPrompt = """
    You are SimpleLime Companion Mode. Watch the current document and return concise, applicable suggestions.
    Return JSON only, with this shape:
    {"suggestions":[{"title":"Short title","comment":"Why this helps","findText":"exact text from the document","replacementText":"replacement text","patchText":"optional unified diff for multi-edit changes"}]}
    Rules:
    - Keep at most 5 suggestions.
    - Prefer findText/replacementText for one localized edit.
    - Use patchText only for multi-edit changes; it must be a unified diff with enough context for every hunk.
    - findText must be an exact substring from the document unless patchText is used.
    - Use workspace context only to prioritize what matters; suggestions must still anchor to the document text.
    - replacementText may equal findText when the suggestion should be a comment only.
    - Do not include Markdown fences or prose outside JSON.
    """

    static func userPrompt(
        title: String,
        language: EditorLanguage,
        text: String,
        workspaceContext: String? = nil
    ) -> String {
        let cleanedContext = workspaceContext?.trimmingCharacters(in: .whitespacesAndNewlines)

        var prompt = """
        Current tab: \(title)
        Language: \(language.displayName)
        """

        if let cleanedContext, !cleanedContext.isEmpty {
            prompt += """


            Workspace context:
            \(cleanedContext)
            """
        }

        prompt += """


        Document:
        \(text)
        """

        return prompt
    }

    private static func suggestions(from wireSuggestions: [WireSuggestion], now: Date) -> [CompanionSuggestion] {
        wireSuggestions.compactMap { wire in
            let title = wire.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let comment = (wire.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let findText = wire.findText ?? ""
            let replacement = wire.replacementText ?? wire.findText
            let patchText = wire.patchText?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty,
                  (!findText.isEmpty || patchText?.isEmpty == false),
                  (!comment.isEmpty || replacement != findText || patchText?.isEmpty == false) else {
                return nil
            }

            return CompanionSuggestion(
                title: title,
                comment: comment,
                findText: findText,
                replacementText: replacement ?? findText,
                patchText: patchText,
                createdAt: now
            )
        }
    }

    private static func normalizedJSONData(from rawResponse: String) -> Data? {
        let trimmed = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = stripMarkdownFence(from: trimmed)
        return json.data(using: .utf8)
    }

    private static func stripMarkdownFence(from text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        var lines = text.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return text }
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CompanionSuggestionAnchorResolver {
    static func range(of anchor: String, in text: String) -> NSRange? {
        let nsText = text as NSString
        let exactRange = nsText.range(of: anchor)
        if exactRange.location != NSNotFound {
            return exactRange
        }

        if let whitespaceRange = normalizedWhitespaceRange(of: anchor, in: text) {
            return whitespaceRange
        }

        return fuzzyTokenRange(of: anchor, in: text)
    }

    private static func normalizedWhitespaceRange(of anchor: String, in text: String) -> NSRange? {
        let pieces = anchor
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard pieces.count > 1 else { return nil }

        let escaped = pieces.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = escaped.joined(separator: #"\s+"#)
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = expression.matches(in: text, range: fullRange)
        guard matches.count == 1 else { return nil }
        return matches.first?.range
    }

    private static func fuzzyTokenRange(of anchor: String, in text: String) -> NSRange? {
        let anchorTokens = tokens(in: anchor)
        guard anchorTokens.count >= 2 else { return nil }

        let textTokens = tokens(in: text)
        guard !textTokens.isEmpty else { return nil }

        let lowerAnchorTokens = anchorTokens.map(\.lowercasedText)
        let anchorText = lowerAnchorTokens.joined(separator: " ")
        let minWindow = anchorTokens.count <= 2 ? anchorTokens.count : max(1, anchorTokens.count - 1)
        let maxWindow = min(textTokens.count, anchorTokens.count + 2)
        var candidates: [(range: NSRange, score: Double)] = []

        for windowSize in minWindow...maxWindow {
            guard windowSize <= textTokens.count else { continue }
            for start in 0...(textTokens.count - windowSize) {
                let window = Array(textTokens[start..<(start + windowSize)])
                let lowerWindowTokens = window.map(\.lowercasedText)
                let candidateText = lowerWindowTokens.joined(separator: " ")
                let score = fuzzyScore(
                    anchorText: anchorText,
                    candidateText: candidateText,
                    anchorTokens: lowerAnchorTokens,
                    candidateTokens: lowerWindowTokens
                )
                guard score >= minimumFuzzyScore(forTokenCount: anchorTokens.count) else {
                    continue
                }

                let startLocation = window[0].range.location
                let endLocation = window[window.count - 1].range.location + window[window.count - 1].range.length
                candidates.append((
                    range: NSRange(location: startLocation, length: endLocation - startLocation),
                    score: score
                ))
            }
        }

        let sorted = candidates.sorted {
            if abs($0.score - $1.score) < 0.0001 {
                return $0.range.length < $1.range.length
            }
            return $0.score > $1.score
        }
        guard let best = sorted.first else { return nil }
        if let second = sorted.dropFirst().first,
           abs(best.score - second.score) < 0.04 {
            return nil
        }

        return best.range
    }

    private static func minimumFuzzyScore(forTokenCount count: Int) -> Double {
        count <= 2 ? 0.66 : 0.64
    }

    private static func fuzzyScore(
        anchorText: String,
        candidateText: String,
        anchorTokens: [String],
        candidateTokens: [String]
    ) -> Double {
        let maxCharacterCount = max(anchorText.count, candidateText.count)
        let editSimilarity: Double
        if maxCharacterCount == 0 {
            editSimilarity = 0
        } else {
            editSimilarity = 1 - Double(levenshteinDistance(anchorText, candidateText)) / Double(maxCharacterCount)
        }

        let lcs = longestCommonSubsequenceCount(anchorTokens, candidateTokens)
        let anchorCoverage = Double(lcs) / Double(max(anchorTokens.count, 1))
        let candidateCoverage = Double(lcs) / Double(max(candidateTokens.count, 1))
        let tokenCoverage = (anchorCoverage + candidateCoverage) / 2
        return max(editSimilarity, tokenCoverage)
    }

    private static func tokens(in text: String) -> [Token] {
        guard let expression = try? NSRegularExpression(pattern: #"\p{L}[\p{L}\p{N}_-]*|\p{N}+"#) else {
            return []
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return expression.matches(in: text, range: fullRange).map { match in
            Token(text: nsText.substring(with: match.range), range: match.range)
        }
    }

    private static func longestCommonSubsequenceCount(_ first: [String], _ second: [String]) -> Int {
        guard !first.isEmpty, !second.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: second.count + 1)
        var current = previous

        for firstIndex in 1...first.count {
            current[0] = 0
            for secondIndex in 1...second.count {
                if first[firstIndex - 1] == second[secondIndex - 1] {
                    current[secondIndex] = previous[secondIndex - 1] + 1
                } else {
                    current[secondIndex] = max(previous[secondIndex], current[secondIndex - 1])
                }
            }
            swap(&previous, &current)
        }

        return previous[second.count]
    }

    private static func levenshteinDistance(_ first: String, _ second: String) -> Int {
        let first = Array(first)
        let second = Array(second)
        guard !first.isEmpty else { return second.count }
        guard !second.isEmpty else { return first.count }

        var previous = Array(0...second.count)
        var current = Array(repeating: 0, count: second.count + 1)

        for firstIndex in 1...first.count {
            current[0] = firstIndex
            for secondIndex in 1...second.count {
                let cost = first[firstIndex - 1] == second[secondIndex - 1] ? 0 : 1
                current[secondIndex] = min(
                    previous[secondIndex] + 1,
                    current[secondIndex - 1] + 1,
                    previous[secondIndex - 1] + cost
                )
            }
            swap(&previous, &current)
        }

        return previous[second.count]
    }

    private struct Token {
        var text: String
        var range: NSRange

        var lowercasedText: String {
            text.lowercased()
        }
    }
}

struct CompanionPatchApplication: Equatable {
    var text: String
    var selection: TextRange
}

enum CompanionUnifiedDiffApplier {
    static func apply(_ patchText: String, to text: String) -> CompanionPatchApplication? {
        let hunks = parseHunks(from: patchText)
        guard !hunks.isEmpty else { return nil }

        var updated = text
        var firstSelection: TextRange?

        for hunk in hunks {
            let oldText = hunk.oldLines.joined(separator: "\n")
            let newText = hunk.newLines.joined(separator: "\n")
            guard !oldText.isEmpty,
                  oldText != newText,
                  let range = uniqueRange(of: oldText, in: updated) else {
                return nil
            }

            let mutable = NSMutableString(string: updated)
            mutable.replaceCharacters(in: range, with: newText)
            updated = mutable as String
            firstSelection = firstSelection ?? TextRange(
                location: range.location,
                length: newText.utf16.count
            )
        }

        guard updated != text,
              let firstSelection else {
            return nil
        }

        return CompanionPatchApplication(text: updated, selection: firstSelection)
    }

    private static func parseHunks(from patchText: String) -> [Hunk] {
        let lines = patchText.components(separatedBy: .newlines)
        var hunks: [Hunk] = []
        var oldLines: [String] = []
        var newLines: [String] = []
        var isInsideHunk = false

        func finishHunk() {
            guard isInsideHunk, (!oldLines.isEmpty || !newLines.isEmpty) else { return }
            hunks.append(Hunk(oldLines: oldLines, newLines: newLines))
            oldLines.removeAll()
            newLines.removeAll()
        }

        for line in lines {
            if line.hasPrefix("@@") {
                finishHunk()
                isInsideHunk = true
                continue
            }

            guard isInsideHunk else { continue }
            if line.hasPrefix("diff --git ") || line.hasPrefix("--- ") || line.hasPrefix("+++ ") {
                finishHunk()
                isInsideHunk = false
                continue
            }
            if line.hasPrefix("\\") {
                continue
            }

            guard let marker = line.first,
                  marker == " " || marker == "-" || marker == "+" else {
                continue
            }

            let content = String(line.dropFirst())
            switch marker {
            case " ":
                oldLines.append(content)
                newLines.append(content)
            case "-":
                oldLines.append(content)
            case "+":
                newLines.append(content)
            default:
                break
            }
        }

        finishHunk()
        return hunks
    }

    private static func uniqueRange(of needle: String, in haystack: String) -> NSRange? {
        let nsHaystack = haystack as NSString
        let fullRange = NSRange(location: 0, length: nsHaystack.length)
        var searchRange = fullRange
        var foundRanges: [NSRange] = []

        while searchRange.length > 0 {
            let range = nsHaystack.range(of: needle, options: [], range: searchRange)
            guard range.location != NSNotFound else { break }
            foundRanges.append(range)
            guard foundRanges.count <= 1 else { return nil }

            let nextLocation = range.location + max(range.length, 1)
            guard nextLocation <= fullRange.length else { break }
            searchRange = NSRange(location: nextLocation, length: fullRange.length - nextLocation)
        }

        return foundRanges.first
    }

    private struct Hunk {
        var oldLines: [String]
        var newLines: [String]
    }
}

private struct CompanionSuggestionResponse: Decodable {
    var suggestions: [WireSuggestion]
}

private struct WireSuggestion: Decodable {
    var title: String
    var comment: String?
    var findText: String?
    var replacementText: String?
    var patchText: String?
}
