import XCTest
@testable import SimpleLime

final class SettingsSearchCatalogTests: XCTestCase {
    func testEmptySearchShowsAllSectionsInDisplayOrder() {
        XCTAssertEqual(
            SettingsSearchCatalog.visibleSections(matching: ""),
            SettingsSearchSection.allCases
        )
    }

    func testSearchMatchesSettingsSectionTerms() {
        XCTAssertEqual(
            SettingsSearchCatalog.visibleSections(matching: "zsh"),
            [.terminal]
        )
        XCTAssertEqual(
            SettingsSearchCatalog.visibleSections(matching: "csv rows"),
            [.performance]
        )
        XCTAssertEqual(
            SettingsSearchCatalog.visibleSections(matching: "companion screen"),
            [.aiAgents]
        )
        XCTAssertEqual(
            SettingsSearchCatalog.visibleSections(matching: "meeting scribe"),
            [.automation]
        )
        XCTAssertEqual(
            SettingsSearchCatalog.visibleSections(matching: "codemirror engine"),
            [.editor]
        )
    }

    func testSearchNormalizesCaseWhitespaceAndPunctuation() {
        XCTAssertEqual(
            SettingsSearchCatalog.visibleSections(matching: "  OpenAI/API  "),
            [.aiAgents]
        )
        XCTAssertEqual(
            SettingsSearchCatalog.visibleSections(matching: "iCloud sync"),
            [.storage]
        )
    }

    func testUnknownSearchReturnsNoSections() {
        XCTAssertEqual(
            SettingsSearchCatalog.visibleSections(matching: "definitely-not-a-setting"),
            []
        )
    }
}
