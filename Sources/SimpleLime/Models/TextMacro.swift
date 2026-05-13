import Foundation

struct TextMacroTemplateField: Identifiable, Equatable {
    var name: String
    var defaultValue: String?

    var id: String { TextMacroTemplate.normalizedKey(name) }

    func prefilledValue(now: Date = Date()) -> String {
        defaultValue ?? TextMacroTemplate.automaticValue(for: name, now: now) ?? ""
    }
}

struct TextMacro: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var isBuiltIn: Bool

    static func custom(title: String, body: String, now: Date = Date()) -> TextMacro {
        TextMacro(
            id: "custom:\(UUID().uuidString)",
            title: title,
            body: body,
            createdAt: now,
            updatedAt: now,
            isBuiltIn: false
        )
    }

    var templateFields: [TextMacroTemplateField] {
        TextMacroTemplate.fields(in: body)
    }

    var hasTemplateFields: Bool {
        !templateFields.isEmpty
    }

    func expandedBody(values: [String: String], now: Date = Date()) -> String {
        TextMacroTemplate.expand(body, values: values, now: now)
    }

    static let builtIns: [TextMacro] = {
        let date = Date(timeIntervalSince1970: 0)
        return [
            TextMacro(
                id: "built-in:prd",
                title: "PRD",
                body:
                """
                # {{Product:Product}} Requirements

                Owner: {{Owner}}
                Date: {{Date}}

                ## Problem

                ## Goals

                ## Non-Goals

                ## Users

                ## Requirements

                ## Open Questions

                ## Rollout
                """,
                createdAt: date,
                updatedAt: date,
                isBuiltIn: true
            ),
            TextMacro(
                id: "built-in:1x1",
                title: "1x1",
                body:
                """
                # 1x1: {{Person}}

                Date: {{Date}}

                ## Wins

                ## Topics

                ## Blockers

                ## Follow-ups

                - [ ]
                """,
                createdAt: date,
                updatedAt: date,
                isBuiltIn: true
            ),
            TextMacro(
                id: "built-in:meeting-notes",
                title: "Meeting Notes",
                body:
                """
                # {{Meeting:Meeting}} Notes

                Date: {{Date}}

                ## Attendees

                {{Attendees}}

                ## Agenda

                ## Notes

                ## Decisions

                ## Action Items

                - [ ]
                """,
                createdAt: date,
                updatedAt: date,
                isBuiltIn: true
            )
        ]
    }()
}

enum TextMacroTemplate {
    private static let pattern = #"\{\{\s*([A-Za-z][A-Za-z0-9 _-]{0,60})(?::([^}]*))?\s*\}\}"#

    static func fields(in body: String) -> [TextMacroTemplateField] {
        let matches = templateMatches(in: body)
        var fields: [TextMacroTemplateField] = []
        var seen = Set<String>()

        for match in matches {
            guard let name = capture(1, in: match, body: body) else { continue }
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedKey(trimmedName)
            guard !trimmedName.isEmpty, !seen.contains(key) else { continue }

            let defaultValue = capture(2, in: match, body: body)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            fields.append(
                TextMacroTemplateField(
                    name: trimmedName,
                    defaultValue: defaultValue?.isEmpty == true ? nil : defaultValue
                )
            )
            seen.insert(key)
        }

        return fields
    }

    static func expand(_ body: String, values: [String: String], now: Date = Date()) -> String {
        let matches = templateMatches(in: body)
        guard !matches.isEmpty else { return body }

        let expanded = NSMutableString(string: body)
        for match in matches.reversed() {
            guard let name = capture(1, in: match, body: body) else { continue }
            let defaultValue = capture(2, in: match, body: body)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = value(
                for: trimmedName,
                defaultValue: defaultValue,
                values: values,
                now: now
            )
            expanded.replaceCharacters(in: match.range, with: replacement)
        }

        return String(expanded)
    }

    static func automaticValue(for name: String, now: Date = Date()) -> String? {
        switch normalizedKey(name) {
        case "date":
            return formatted(now, as: "yyyy-MM-dd")
        case "time":
            return formatted(now, as: "HH:mm")
        case "datetime":
            return formatted(now, as: "yyyy-MM-dd HH:mm")
        default:
            return nil
        }
    }

    static func normalizedKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func value(
        for name: String,
        defaultValue: String?,
        values: [String: String],
        now: Date
    ) -> String {
        let key = normalizedKey(name)
        if let exact = values[name] {
            return exact
        }
        if let matched = values.first(where: { normalizedKey($0.key) == key })?.value {
            return matched
        }
        if let defaultValue, !defaultValue.isEmpty {
            return defaultValue
        }
        return automaticValue(for: name, now: now) ?? ""
    }

    private static func templateMatches(in body: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
    }

    private static func capture(_ index: Int, in match: NSTextCheckingResult, body: String) -> String? {
        guard match.numberOfRanges > index,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: body) else {
            return nil
        }
        return String(body[range])
    }

    private static func formatted(_ date: Date, as format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
