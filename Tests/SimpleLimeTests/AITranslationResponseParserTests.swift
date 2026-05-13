import XCTest
@testable import SimpleLime

final class AITranslationResponseParserTests: XCTestCase {
    func testParsesJSONArrayFromFencedResponse() throws {
        let translations = try AITranslationResponseParser.translations(
            from: """
            ```json
            ["Hallo", "Welt"]
            ```
            """,
            expectedCount: 2
        )

        XCTAssertEqual(translations, ["Hallo", "Welt"])
    }

    func testFallsBackToRawTextForSingleSelection() throws {
        let translations = try AITranslationResponseParser.translations(
            from: "Bonjour",
            expectedCount: 1
        )

        XCTAssertEqual(translations, ["Bonjour"])
    }

    func testRejectsWrongSegmentCount() {
        XCTAssertThrowsError(
            try AITranslationResponseParser.translations(from: "[\"Hallo\"]", expectedCount: 2)
        )
    }
}
