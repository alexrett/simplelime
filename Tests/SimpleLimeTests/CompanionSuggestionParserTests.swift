import XCTest
@testable import SimpleLime

final class CompanionSuggestionParserTests: XCTestCase {
    func testParsesSuggestionsFromJSONObject() {
        let response =
        """
        {"suggestions":[{"title":"Tighten copy","comment":"Shorter wording reads better.","findText":"very very fast","replacementText":"fast"}]}
        """

        let suggestions = CompanionSuggestionParser.parse(response, now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.title, "Tighten copy")
        XCTAssertEqual(suggestions.first?.comment, "Shorter wording reads better.")
        XCTAssertEqual(suggestions.first?.findText, "very very fast")
        XCTAssertEqual(suggestions.first?.replacementText, "fast")
        XCTAssertEqual(suggestions.first?.createdAt, Date(timeIntervalSince1970: 1))
    }

    func testParsesSuggestionsFromFencedJSONArray() {
        let response =
        """
        ```json
        [{"title":"Check scope","comment":"This needs a decision.","findText":"TBD","replacementText":"TBD"}]
        ```
        """

        let suggestions = CompanionSuggestionParser.parse(response)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.title, "Check scope")
        XCTAssertEqual(suggestions.first?.findText, "TBD")
        XCTAssertEqual(suggestions.first?.replacementText, "TBD")
        XCTAssertEqual(suggestions.first?.canApplyEdit, false)
        XCTAssertEqual(suggestions.first?.canAddComment, true)
    }

    func testDropsSuggestionsWithoutAnchors() {
        let response =
        """
        {"suggestions":[{"title":"No anchor","comment":"Missing find text.","findText":"","replacementText":"x"}]}
        """

        XCTAssertEqual(CompanionSuggestionParser.parse(response), [])
    }

    func testParsesReplacementSuggestionWithoutComment() {
        let response =
        """
        {"suggestions":[{"title":"Use direct wording","findText":"could possibly","replacementText":"can"}]}
        """

        let suggestions = CompanionSuggestionParser.parse(response)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.comment, "")
        XCTAssertEqual(suggestions.first?.findText, "could possibly")
        XCTAssertEqual(suggestions.first?.replacementText, "can")
        XCTAssertEqual(suggestions.first?.canApplyEdit, true)
        XCTAssertEqual(suggestions.first?.canAddComment, false)
    }

    func testParsesPatchSuggestionWithoutFindText() {
        let response =
        """
        {"suggestions":[{"title":"Patch status","comment":"Keeps the fields consistent.","patchText":"@@\\n-Status: draft\\n+Status: ready"}]}
        """

        let suggestions = CompanionSuggestionParser.parse(response)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.findText, "")
        XCTAssertEqual(suggestions.first?.replacementText, "")
        XCTAssertEqual(suggestions.first?.patchText, "@@\n-Status: draft\n+Status: ready")
        XCTAssertEqual(suggestions.first?.canApplyEdit, true)
        XCTAssertEqual(suggestions.first?.canAddComment, false)
    }

    func testUnifiedDiffApplierAppliesMultipleContextualHunks() {
        let text = """
        Title: Alpha
        Status: draft
        Owner: TBD
        """
        let patch = """
        --- a/doc.md
        +++ b/doc.md
        @@
         Title: Alpha
        -Status: draft
        +Status: ready
         Owner: TBD
        @@
        -Owner: TBD
        +Owner: Malik
        """

        let application = CompanionUnifiedDiffApplier.apply(patch, to: text)

        XCTAssertEqual(
            application?.text,
            """
            Title: Alpha
            Status: ready
            Owner: Malik
            """
        )
        XCTAssertEqual(application?.selection.location, 0)
    }

    func testUnifiedDiffApplierRejectsAmbiguousContext() {
        let text = """
        Status: draft
        Status: draft
        """
        let patch = """
        @@
        -Status: draft
        +Status: ready
        """

        XCTAssertNil(CompanionUnifiedDiffApplier.apply(patch, to: text))
    }

    func testAnchorResolverMatchesNormalizedWhitespace() {
        let text = "The draft is very  very\nfast."
        let range = CompanionSuggestionAnchorResolver.range(of: "very very fast", in: text)

        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "very  very\nfast")
    }

    func testAnchorResolverFindsUniqueFuzzyTokenMatch() {
        let text = "The draft is very fast."
        let range = CompanionSuggestionAnchorResolver.range(of: "very very fast", in: text)

        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "very fast")
    }

    func testAnchorResolverRejectsAmbiguousFuzzyMatch() {
        let text = "The draft is very fast. The fallback is very fast."

        XCTAssertNil(CompanionSuggestionAnchorResolver.range(of: "very very fast", in: text))
    }
}
