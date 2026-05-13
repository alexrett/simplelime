import Foundation

struct AITaskInferenceResult: Equatable {
    var title: String
    var status: TaskBoardStatus
}

enum AITaskInference {
    static let autoInferenceDefaultsKey = "ai.tasks.autoInference"
    static let defaultAutoInferenceEnabled = false

    static let systemPrompt = """
    You extract concrete follow-up tasks from product notes, meeting notes, specs, and planning documents. Return only JSON. Do not invent work that is not implied by the text.
    """

    static func userPrompt(context: String) -> String {
        """
        Extract actionable tasks from this SimpleLime workspace context.

        Rules:
        - Return JSON as {"tasks":[{"title":"...","status":"todo"}]}.
        - status must be one of: todo, inProgress, done.
        - Prefer short imperative task titles.
        - Skip vague observations, facts, headings, and completed historical notes.
        - Return at most 12 tasks.

        Context:
        \(context)
        """
    }

    static func parse(_ response: String) -> [AITaskInferenceResult] {
        guard let object = jsonObject(from: response) else {
            return []
        }

        let rawTasks: [Any]
        if let dictionary = object as? [String: Any] {
            rawTasks = dictionary["tasks"] as? [Any] ?? []
        } else if let array = object as? [Any] {
            rawTasks = array
        } else {
            rawTasks = []
        }

        var seen = Set<String>()
        var results: [AITaskInferenceResult] = []
        for rawTask in rawTasks {
            guard let result = taskResult(from: rawTask) else { continue }
            let key = result.title.lowercased()
            guard seen.insert(key).inserted else { continue }
            results.append(result)
            if results.count >= 12 {
                break
            }
        }

        return results
    }

    private static func taskResult(from rawTask: Any) -> AITaskInferenceResult? {
        if let title = rawTask as? String {
            return normalizedTask(title: title, status: .todo)
        }

        guard let dictionary = rawTask as? [String: Any] else {
            return nil
        }

        let rawTitle = firstStringValue(in: dictionary, keys: ["title", "task", "text", "summary"])
        guard let rawTitle else { return nil }

        let status = taskStatus(from: firstStringValue(in: dictionary, keys: ["status", "state", "column"]))
        return normalizedTask(title: rawTitle, status: status)
    }

    private static func normalizedTask(title: String, status: TaskBoardStatus) -> AITaskInferenceResult? {
        let cleaned = title
            .replacingOccurrences(of: #"^\s*[-*]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*\[[xX >/-]\]\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        return AITaskInferenceResult(title: String(cleaned.prefix(180)), status: status)
    }

    private static func taskStatus(from value: String?) -> TaskBoardStatus {
        let normalized = (value ?? "")
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "done", "complete", "completed", "closed":
            return .done
        case "inprogress", "progress", "doing", "active", "started":
            return .inProgress
        default:
            return .todo
        }
    }

    private static func firstStringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func jsonObject(from response: String) -> Any? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            trimmed,
            fencedJSONBody(from: trimmed),
            bracketedJSONBody(from: trimmed, open: "{", close: "}"),
            bracketedJSONBody(from: trimmed, open: "[", close: "]")
        ].compactMap { $0 }

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            return object
        }

        return nil
    }

    private static func fencedJSONBody(from response: String) -> String? {
        guard let fenceStart = response.range(of: "```") else { return nil }
        let afterFence = response[fenceStart.upperBound...]
        let contentStart = afterFence.firstIndex(of: "\n").map { response.index(after: $0) } ?? afterFence.startIndex
        guard let fenceEnd = response[contentStart...].range(of: "```") else { return nil }
        return String(response[contentStart..<fenceEnd.lowerBound])
    }

    private static func bracketedJSONBody(from response: String, open: Character, close: Character) -> String? {
        guard let start = response.firstIndex(of: open),
              let end = response.lastIndex(of: close),
              start < end else {
            return nil
        }
        return String(response[start...end])
    }
}
