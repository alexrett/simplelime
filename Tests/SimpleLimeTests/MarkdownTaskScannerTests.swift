import XCTest
@testable import SimpleLime

final class MarkdownTaskScannerTests: XCTestCase {
    func testScansMarkdownTaskStatusesAndLineNumbers() {
        let matches = MarkdownTaskScanner.scan(
            """
            # Plan
            - [ ] Write draft
            - [>] Review
            - [x] Ship
            """
        )

        XCTAssertEqual(matches.map(\.title), ["Write draft", "Review", "Ship"])
        XCTAssertEqual(matches.map(\.status), [.todo, .inProgress, .done])
        XCTAssertEqual(matches.map(\.lineNumber), [2, 3, 4])
    }

    func testIgnoresEmptyTasksAndNonTaskBullets() {
        let matches = MarkdownTaskScanner.scan(
            """
            - normal bullet
            - [ ]
            * [ ] Real task
            """
        )

        XCTAssertEqual(matches.map(\.title), ["Real task"])
    }

    func testScansNaturalTaskMarkers() {
        let matches = MarkdownTaskScanner.scan(
            """
            TODO: Draft launch note
            // FIXME - handle empty state
            # ACTION ITEM: send recap
            IN PROGRESS: review contract
            DONE: archive notes
            """
        )

        XCTAssertEqual(
            matches.map(\.title),
            ["Draft launch note", "handle empty state", "send recap", "review contract", "archive notes"]
        )
        XCTAssertEqual(matches.map(\.status), [.todo, .todo, .todo, .inProgress, .done])
        XCTAssertEqual(matches.map(\.updateMode), Array(repeating: .lineToMarkdownChecklist, count: 5))
    }

    func testInfersTasksFromPlainLanguageLines() {
        let matches = MarkdownTaskScanner.scan(
            """
            We need to update README before launch.
            Please send the launch recap.
            Нужно проверить экспорт PDF.
            This is just context.
            """
        )

        XCTAssertEqual(
            matches.map(\.title),
            ["Update README before launch", "Send the launch recap", "Проверить экспорт PDF"]
        )
        XCTAssertEqual(matches.map(\.status), [.todo, .todo, .todo])
        XCTAssertEqual(matches.map(\.updateMode), Array(repeating: .lineToMarkdownChecklist, count: 3))
        XCTAssertEqual(matches.map(\.lineNumber), [1, 2, 3])
    }

    func testInferredTasksSkipExistingMarkersQuestionsAndCodeFences() {
        let matches = MarkdownTaskScanner.scan(
            """
            ```swift
            // We need to ignore fenced code.
            ```
            - [ ] Existing checklist
            TODO: Existing marker
            Should this be a task?
            We should update docs.
            """
        )

        XCTAssertEqual(matches.map(\.title), ["Existing checklist", "Existing marker", "Update docs"])
        XCTAssertEqual(matches.map(\.updateMode), [.markdownMarker, .lineToMarkdownChecklist, .lineToMarkdownChecklist])
        XCTAssertEqual(matches.map(\.lineNumber), [4, 5, 7])
    }
}
