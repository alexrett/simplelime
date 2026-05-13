import Foundation

enum TextDiff {
    struct Document: Equatable {
        let title: String
        let text: String
    }

    struct PreviewDocument: Equatable {
        let title: String
        let text: String
        let originalByteCount: Int
        let originalLineCount: Int?
        let isTruncated: Bool

        var document: Document {
            Document(title: title, text: text)
        }
    }

    private enum Operation: Equatable {
        case equal(String)
        case delete(String)
        case insert(String)
    }

    static func unifiedDiff(from old: Document, to new: Document) -> String {
        guard old.text != new.text else {
            return "No differences between \(old.title) and \(new.title).\n"
        }

        let operations = diffOperations(
            oldLines: splitLines(old.text),
            newLines: splitLines(new.text)
        )

        var lines: [String] = [
            "--- \(old.title)",
            "+++ \(new.title)"
        ]

        lines.append(contentsOf: operations.map { operation in
            switch operation {
            case .equal(let line):
                return " \(line)"
            case .delete(let line):
                return "-\(line)"
            case .insert(let line):
                return "+\(line)"
            }
        })

        return lines.joined(separator: "\n") + "\n"
    }

    static func unifiedDiffPreview(
        from old: PreviewDocument,
        to new: PreviewDocument,
        limitDescription: String
    ) -> String {
        guard old.isTruncated || new.isTruncated else {
            return unifiedDiff(from: old.document, to: new.document)
        }

        let diff = unifiedDiff(from: old.document, to: new.document)
        let oldSummary = previewSummary(for: old)
        let newSummary = previewSummary(for: new)
        let body: String
        if diff.hasPrefix("No differences between ") {
            body = "No differences in the rendered preview. One or both inputs were truncated, so differences may exist outside this preview.\n"
        } else {
            body = diff
        }

        return """
        Diff preview limited to \(limitDescription).
        Old input: \(oldSummary)
        New input: \(newSummary)

        \(body)
        """
    }

    private static func previewSummary(for document: PreviewDocument) -> String {
        let shownBytes = document.text.utf8.count
        let shownLines = splitLines(document.text).count
        let lineSummary = document.originalLineCount.map { "\($0)" } ?? "unknown"
        if document.isTruncated {
            return "\(document.title) showing \(shownBytes)/\(document.originalByteCount) bytes and \(shownLines)/\(lineSummary) lines"
        }
        return "\(document.title) complete \(document.originalByteCount) bytes and \(lineSummary) lines"
    }

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var lines = text.components(separatedBy: .newlines)
        if text.last?.isNewline == true {
            lines.removeLast()
        }
        return lines
    }

    private static func diffOperations(oldLines: [String], newLines: [String]) -> [Operation] {
        let oldCount = oldLines.count
        let newCount = newLines.count
        var lengths = Array(
            repeating: Array(repeating: 0, count: newCount + 1),
            count: oldCount + 1
        )

        if oldCount > 0, newCount > 0 {
            for oldIndex in stride(from: oldCount - 1, through: 0, by: -1) {
                for newIndex in stride(from: newCount - 1, through: 0, by: -1) {
                    if oldLines[oldIndex] == newLines[newIndex] {
                        lengths[oldIndex][newIndex] = lengths[oldIndex + 1][newIndex + 1] + 1
                    } else {
                        lengths[oldIndex][newIndex] = max(
                            lengths[oldIndex + 1][newIndex],
                            lengths[oldIndex][newIndex + 1]
                        )
                    }
                }
            }
        }

        var operations: [Operation] = []
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < oldCount || newIndex < newCount {
            if oldIndex < oldCount,
               newIndex < newCount,
               oldLines[oldIndex] == newLines[newIndex] {
                operations.append(.equal(oldLines[oldIndex]))
                oldIndex += 1
                newIndex += 1
            } else if newIndex < newCount,
                      (oldIndex == oldCount || lengths[oldIndex][newIndex + 1] >= lengths[oldIndex + 1][newIndex]) {
                operations.append(.insert(newLines[newIndex]))
                newIndex += 1
            } else if oldIndex < oldCount {
                operations.append(.delete(oldLines[oldIndex]))
                oldIndex += 1
            }
        }

        return operations
    }
}
