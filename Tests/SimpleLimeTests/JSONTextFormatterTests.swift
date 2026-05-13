import XCTest
@testable import SimpleLime

final class JSONTextFormatterTests: XCTestCase {
    func testPrettyPrintsJSONWithoutEscapingSlashes() throws {
        let formatted = try JSONTextFormatter.format(
            "{\"url\":\"https:\\/\\/example.com\",\"items\":[1,true]}",
            prettyPrinted: true
        )

        XCTAssertTrue(formatted.contains("\"url\" : \"https://example.com\""), formatted)
        XCTAssertTrue(formatted.contains("\"items\" : ["), formatted)
        XCTAssertTrue(formatted.hasSuffix("\n"))
    }

    func testMinifiesJSON() throws {
        let minified = try JSONTextFormatter.format(
            """
            {
              "items": [
                1,
                true
              ]
            }
            """,
            prettyPrinted: false
        )

        XCTAssertEqual(minified, "{\"items\":[1,true]}")
    }
}
