import Foundation

enum AITranslationRequest {
    static let systemPrompt = """
    You are a precise translation engine inside a text editor.
    Translate only the supplied text segments into the requested target language.
    Preserve Markdown, code spans, links, placeholders, numbers, and line breaks where practical.
    Return only a JSON array of translated strings, in the same order as the input segments.
    Do not add explanations, comments, or Markdown fences.
    """

    static func userPrompt(targetLanguage: String, segments: [String]) -> String {
        let encodedSegments = (try? JSONEncoder().encode(segments))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
        Target language: \(targetLanguage)

        Translate these text segments and return a JSON array with exactly \(segments.count) item\(segments.count == 1 ? "" : "s"):
        \(encodedSegments)
        """
    }
}

enum AITranslationResponseError: LocalizedError, Equatable {
    case invalidResponse(expectedCount: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let expectedCount):
            "Translation returned an invalid response. Expected \(expectedCount) translated segment\(expectedCount == 1 ? "" : "s")."
        }
    }
}

enum AITranslationResponseParser {
    static func translations(from response: String, expectedCount: Int) throws -> [String] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectedCount > 0, !trimmed.isEmpty else {
            throw AITranslationResponseError.invalidResponse(expectedCount: expectedCount)
        }

        if let array = parseJSONArray(from: trimmed), array.count == expectedCount {
            return array
        }

        if expectedCount == 1 {
            return [stripCodeFence(from: trimmed)]
        }

        throw AITranslationResponseError.invalidResponse(expectedCount: expectedCount)
    }

    private static func parseJSONArray(from response: String) -> [String]? {
        let candidate = jsonArrayCandidate(from: stripCodeFence(from: response))
        guard let data = candidate.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    private static func jsonArrayCandidate(from response: String) -> String {
        guard let start = response.firstIndex(of: "["),
              let end = response.lastIndex(of: "]"),
              start <= end else {
            return response
        }

        return String(response[start...end])
    }

    private static func stripCodeFence(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        var lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return trimmed }
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
