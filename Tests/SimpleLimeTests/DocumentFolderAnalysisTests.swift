import XCTest
@testable import SimpleLime

final class DocumentFolderAnalysisTests: XCTestCase {
    func testMarkdownReportIncludesMindMapKanbanGapsAndSearchIndex() {
        let rootURL = URL(fileURLWithPath: "/tmp/simplelime-docs", isDirectory: true)
        let specURL = rootURL.appendingPathComponent("spec.md")
        let notesURL = rootURL.appendingPathComponent("notes/meeting.md")
        let files = [
            DocumentFolderAnalysis.InputFile(
                url: specURL,
                relativePath: "spec.md",
                language: .markdown,
                text:
                """
                # Checkout

                ## Requirements

                - [ ] Wire payment state
                - [>] Review fulfillment edge cases

                ## Open Questions

                TODO: settle refund copy
                """
            ),
            DocumentFolderAnalysis.InputFile(
                url: notesURL,
                relativePath: "notes/meeting.md",
                language: .markdown,
                text:
                """
                # Meeting

                - [x] Confirm launch checklist
                FIXME gap in reporting
                """
            )
        ]

        let report = DocumentFolderAnalysis.markdownReport(
            rootURL: rootURL,
            files: files,
            generatedAt: Date(timeIntervalSince1970: 1_777_000_000)
        )

        XCTAssertTrue(report.contains("# PO Mode: simplelime-docs"), report)
        XCTAssertTrue(report.contains("## Mind Map"), report)
        XCTAssertTrue(report.contains("- [spec.md](file:///tmp/simplelime-docs/spec.md)"), report)
        XCTAssertTrue(report.contains("### To Do"), report)
        XCTAssertTrue(report.contains("- [ ] Wire payment state ([spec.md:5](file:///tmp/simplelime-docs/spec.md))"), report)
        XCTAssertTrue(report.contains("- [ ] settle refund copy ([spec.md:10](file:///tmp/simplelime-docs/spec.md))"), report)
        XCTAssertTrue(report.contains("### In Progress"), report)
        XCTAssertTrue(report.contains("### Done"), report)
        XCTAssertTrue(report.contains("TODO: settle refund copy ([spec.md:10](file:///tmp/simplelime-docs/spec.md))"), report)
        XCTAssertTrue(report.contains("FIXME gap in reporting ([notes/meeting.md:4](file:///tmp/simplelime-docs/notes/meeting.md))"), report)
        XCTAssertTrue(report.contains("| spec.md | 3 | 3 | 2 |"), report)
        XCTAssertTrue(report.contains("`checkout`"), report)
    }

    func testAnalyzeBuildsInteractiveReportModel() {
        let rootURL = URL(fileURLWithPath: "/tmp/simplelime-docs", isDirectory: true)
        let specURL = rootURL.appendingPathComponent("spec.md")
        let files = [
            DocumentFolderAnalysis.InputFile(
                url: specURL,
                relativePath: "spec.md",
                language: .markdown,
                text:
                """
                # Checkout

                - [ ] Wire payment state
                TBD: success metric
                """
            )
        ]

        let report = DocumentFolderAnalysis.analyze(
            rootURL: rootURL,
            files: files,
            generatedAt: Date(timeIntervalSince1970: 1_777_000_000)
        )

        XCTAssertEqual(report.rootName, "simplelime-docs")
        XCTAssertEqual(report.documentCount, 1)
        XCTAssertEqual(report.headingCount, 1)
        XCTAssertEqual(report.taskCount, 1)
        XCTAssertEqual(report.gapCount, 1)
        XCTAssertEqual(report.tasks(for: .todo).map(\.title), ["Wire payment state"])
        XCTAssertEqual(report.gaps.map(\.title), ["TBD: success metric"])
        XCTAssertTrue(report.searchTerms.contains { $0.term == "checkout" })
    }
}
