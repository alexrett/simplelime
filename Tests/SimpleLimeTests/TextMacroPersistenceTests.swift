import XCTest
@testable import SimpleLime

final class TextMacroPersistenceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-text-macro-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testRoundTripsCustomMacrosOnly() throws {
        let url = temporaryDirectory.appendingPathComponent("macros.json")
        let persistence = TextMacroPersistence(macrosURL: url)
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let custom = TextMacro(
            id: "custom:test",
            title: "Snippet",
            body: "Hello",
            createdAt: now,
            updatedAt: now,
            isBuiltIn: false
        )

        try persistence.save(TextMacro.builtIns + [custom])

        XCTAssertEqual(persistence.load(), [custom])
    }

    func testRoundTripsActionMacrosAlongsideTextMacros() throws {
        let url = temporaryDirectory.appendingPathComponent("macros.json")
        let persistence = TextMacroPersistence(macrosURL: url)
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let textMacro = TextMacro(
            id: "custom:text",
            title: "Snippet",
            body: "Hello",
            createdAt: now,
            updatedAt: now,
            isBuiltIn: false
        )
        let actionMacro = ActionMacro(
            id: "action:test",
            title: "Format",
            steps: [
                .replaceSelection("# Title"),
                .transform(.uppercase),
                .markdown(.bold),
                .editor(.toggleComment)
            ],
            createdAt: now,
            updatedAt: now
        )

        try persistence.save(textMacros: TextMacro.builtIns + [textMacro], actionMacros: [actionMacro])

        XCTAssertEqual(persistence.load(), [textMacro])
        XCTAssertEqual(persistence.loadActionMacros(), [actionMacro])
    }

    func testRoundTripsValidPinnedMacrosOnly() throws {
        let url = temporaryDirectory.appendingPathComponent("macros.json")
        let persistence = TextMacroPersistence(macrosURL: url)
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let textMacro = TextMacro(
            id: "custom:text",
            title: "Snippet",
            body: "Hello",
            createdAt: now,
            updatedAt: now,
            isBuiltIn: false
        )
        let actionMacro = ActionMacro(
            id: "action:test",
            title: "Format",
            steps: [.transform(.uppercase)],
            createdAt: now,
            updatedAt: now
        )

        try persistence.save(
            textMacros: TextMacro.builtIns + [textMacro],
            actionMacros: [actionMacro],
            pinnedMacros: [
                .text("built-in:prd"),
                .text(textMacro.id),
                .action(actionMacro.id),
                .text("missing"),
                .action("missing"),
                .text(textMacro.id)
            ]
        )

        XCTAssertEqual(persistence.loadPinnedMacros(), [
            .text("built-in:prd"),
            .text(textMacro.id),
            .action(actionMacro.id)
        ])
    }
}
