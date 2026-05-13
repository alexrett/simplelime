import Foundation

struct DocumentFolderAnalysis {
    struct InputFile: Equatable {
        var url: URL
        var relativePath: String
        var language: EditorLanguage
        var text: String
    }

    struct LineReference: Equatable, Identifiable {
        var title: String
        var relativePath: String
        var url: URL
        var lineNumber: Int
        var excerpt: String

        var id: String {
            "\(relativePath):\(lineNumber):\(title)"
        }
    }

    struct FileSummary: Equatable {
        var file: InputFile
        var headings: [LineReference]
        var tasks: [TaskBoardStatus: [LineReference]]
        var gaps: [LineReference]

        var taskCount: Int {
            tasks.values.reduce(0) { $0 + $1.count }
        }
    }

    struct SearchTerm: Equatable, Identifiable {
        var term: String
        var count: Int

        var id: String { term }
    }

    struct Report: Equatable {
        var rootURL: URL
        var rootName: String
        var files: [InputFile]
        var summaries: [FileSummary]
        var searchTerms: [SearchTerm]
        var generatedAt: Date

        var documentCount: Int { files.count }
        var headingCount: Int { summaries.reduce(0) { $0 + $1.headings.count } }
        var taskCount: Int { summaries.reduce(0) { $0 + $1.taskCount } }
        var gapCount: Int { summaries.reduce(0) { $0 + $1.gaps.count } }

        func tasks(for status: TaskBoardStatus) -> [LineReference] {
            summaries.flatMap { $0.tasks[status] ?? [] }
        }

        var gaps: [LineReference] {
            summaries.flatMap(\.gaps)
        }
    }

    static let maxAnalyzedFileBytes = 1_000_000
    static let maxAnalyzedFiles = 300

    static func loadInputFiles(rootURL: URL, fileURLs: [URL], fileManager: FileManager = .default) -> [InputFile] {
        fileURLs
            .prefix(maxAnalyzedFiles)
            .compactMap { url in
                let language = EditorLanguage.detect(fileName: url.lastPathComponent, text: "")
                guard !language.isBinaryPreview,
                      fileSize(for: url, fileManager: fileManager) <= maxAnalyzedFileBytes,
                      let text = try? String(contentsOf: url) else {
                    return nil
                }

                return InputFile(
                    url: url,
                    relativePath: relativePath(for: url, rootURL: rootURL),
                    language: EditorLanguage.detect(fileName: url.lastPathComponent, text: text),
                    text: text
                )
            }
    }

    static func analyze(rootURL: URL, files: [InputFile], generatedAt: Date = Date()) -> Report {
        let summaries = files.map(summary(for:))
        return Report(
            rootURL: rootURL,
            rootName: rootURL.lastPathComponent,
            files: files,
            summaries: summaries,
            searchTerms: searchTerms(summaries: summaries),
            generatedAt: generatedAt
        )
    }

    static func markdownReport(rootURL: URL, files: [InputFile], generatedAt: Date = Date()) -> String {
        let report = analyze(rootURL: rootURL, files: files, generatedAt: generatedAt)

        return [
            "# PO Mode: \(report.rootName)",
            "",
            "Generated \(DateFormatter.poMode.string(from: generatedAt)).",
            "",
            "## Summary",
            "",
            "- Documents: \(report.documentCount)",
            "- Headings: \(report.headingCount)",
            "- Tasks: \(report.taskCount)",
            "- Gaps and open questions: \(report.gapCount)",
            "",
            "## Mind Map",
            "",
            mindMapSection(rootName: report.rootName, summaries: report.summaries),
            "",
            "## Kanban",
            "",
            kanbanSection(summaries: report.summaries),
            "",
            "## Gaps And Open Questions",
            "",
            gapsSection(summaries: report.summaries),
            "",
            "## Feature Documents",
            "",
            featureDocumentsSection(summaries: report.summaries),
            "",
            "## Search Index",
            "",
            searchIndexSection(terms: report.searchTerms)
        ].joined(separator: "\n")
    }

    static func summary(for file: InputFile) -> FileSummary {
        let headings = headingReferences(in: file)
        let tasks = taskReferences(in: file)
        let gaps = gapReferences(in: file)
        return FileSummary(file: file, headings: headings, tasks: tasks, gaps: gaps)
    }

    private static func headingReferences(in file: InputFile) -> [LineReference] {
        lines(in: file.text).compactMap { line in
            guard let match = markdownHeading(in: line.text) else { return nil }
            return LineReference(
                title: match.title,
                relativePath: file.relativePath,
                url: file.url,
                lineNumber: line.number,
                excerpt: line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func taskReferences(in file: InputFile) -> [TaskBoardStatus: [LineReference]] {
        var output: [TaskBoardStatus: [LineReference]] = [:]
        for task in MarkdownTaskScanner.scan(file.text) {
            let reference = LineReference(
                title: task.title,
                relativePath: file.relativePath,
                url: file.url,
                lineNumber: task.lineNumber,
                excerpt: task.title
            )
            output[task.status, default: []].append(reference)
        }
        return output
    }

    private static func gapReferences(in file: InputFile) -> [LineReference] {
        lines(in: file.text).compactMap { line in
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  isGapLine(trimmed) else {
                return nil
            }

            return LineReference(
                title: gapTitle(for: trimmed),
                relativePath: file.relativePath,
                url: file.url,
                lineNumber: line.number,
                excerpt: trimmed
            )
        }
    }

    private static func mindMapSection(rootName: String, summaries: [FileSummary]) -> String {
        guard !summaries.isEmpty else { return "- \(rootName)\n  - No documents found" }

        var lines = ["- \(rootName)"]
        for summary in summaries {
            lines.append("  - \(linkText(summary.file.relativePath, url: summary.file.url))")
            let headings = summary.headings.prefix(8)
            if headings.isEmpty {
                lines.append("    - No Markdown headings")
            } else {
                for heading in headings {
                    lines.append("    - \(heading.title)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func kanbanSection(summaries: [FileSummary]) -> String {
        let allTasks = summaries.flatMap { summary in
            TaskBoardStatus.allCases.flatMap { status in
                (summary.tasks[status] ?? []).map { (status, $0) }
            }
        }
        guard !allTasks.isEmpty else { return "No Markdown checklist items found." }

        return TaskBoardStatus.allCases.map { status in
            let tasks = allTasks.filter { $0.0 == status }.map(\.1)
            let body = tasks.isEmpty
                ? "- None"
                : tasks.map { "- [\(status.markdownTaskMarker)] \($0.title) (\(referenceLink($0)))" }.joined(separator: "\n")
            return "### \(status.title)\n\n\(body)"
        }.joined(separator: "\n\n")
    }

    private static func gapsSection(summaries: [FileSummary]) -> String {
        let gaps = summaries.flatMap(\.gaps)
        guard !gaps.isEmpty else { return "No TODO, FIXME, TBD, gap, or open-question markers found." }

        return gaps
            .prefix(100)
            .map { "- \($0.excerpt) (\(referenceLink($0)))" }
            .joined(separator: "\n")
    }

    private static func featureDocumentsSection(summaries: [FileSummary]) -> String {
        guard !summaries.isEmpty else { return "No documents found." }

        let rows = summaries.map { summary in
            "| \(escapeTable(summary.file.relativePath)) | \(summary.headings.count) | \(summary.taskCount) | \(summary.gaps.count) |"
        }
        return (
            [
                "| File | Headings | Tasks | Gaps |",
                "| --- | ---: | ---: | ---: |"
            ] + rows
        ).joined(separator: "\n")
    }

    private static func searchIndexSection(terms: [SearchTerm]) -> String {
        guard !terms.isEmpty else { return "No searchable terms found." }

        return terms
            .map { "- `\($0.term)` - \($0.count)" }
            .joined(separator: "\n")
    }

    private static func searchTerms(summaries: [FileSummary]) -> [SearchTerm] {
        var counts: [String: Int] = [:]
        for summary in summaries {
            let values = [summary.file.relativePath] + summary.headings.map(\.title) + summary.gaps.map(\.title)
            for word in values.flatMap(searchWords(in:)) {
                counts[word, default: 0] += 1
            }
        }

        let ranked = counts
            .filter { $0.key.count >= 3 }
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
            }
            return $0.value > $1.value
        }
        .prefix(25)

        return ranked
            .map { SearchTerm(term: $0.key, count: $0.value) }
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }

    private static func fileSize(for url: URL, fileManager: FileManager) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private static func lines(in text: String) -> [(number: Int, text: String)] {
        text.components(separatedBy: .newlines).enumerated().map { (index, line) in
            (number: index + 1, text: line)
        }
    }

    private static func markdownHeading(in line: String) -> (level: Int, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let start = trimmed.index(trimmed.startIndex, offsetBy: level)
        guard start < trimmed.endIndex,
              trimmed[start].isWhitespace else {
            return nil
        }
        let title = trimmed[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : (level, title)
    }

    private static func isGapLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("todo") ||
            lower.contains("fixme") ||
            lower.contains("tbd") ||
            lower.contains("open question") ||
            lower.contains("open questions") ||
            lower.contains("gap") ||
            lower.contains("???")
    }

    private static func gapTitle(for line: String) -> String {
        line
            .replacingOccurrences(of: #"^[#>\-\*\s\[\]xX/]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func referenceLink(_ reference: LineReference) -> String {
        "[\(reference.relativePath):\(reference.lineNumber)](\(reference.url.absoluteString))"
    }

    private static func linkText(_ text: String, url: URL) -> String {
        "[\(text)](\(url.absoluteString))"
    }

    private static func escapeTable(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }

    private static func searchWords(in text: String) -> [String] {
        let stopWords: Set<String> = [
            "and", "for", "from", "into", "mode", "the", "this", "that", "with", "without"
        ]
        return text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }
}

private extension DateFormatter {
    static let poMode: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
