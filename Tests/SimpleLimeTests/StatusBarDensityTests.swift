import XCTest
@testable import SimpleLime

final class StatusBarDensityTests: XCTestCase {
    func testSmallWindowsUseIconOnlyMinimalStatusBar() {
        let density = StatusBarDensity(width: 360)

        XCTAssertEqual(density, .minimal)
        XCTAssertEqual(density.languageWidth, 24)
        XCTAssertFalse(density.showsLanguageText)
        XCTAssertFalse(density.showsPath)
        XCTAssertFalse(density.showsStats)
        XCTAssertFalse(density.showsSaveText)
    }

    func testMediumWindowsKeepPathButHideStats() {
        let density = StatusBarDensity(width: 600)

        XCTAssertEqual(density, .compact)
        XCTAssertTrue(density.showsLanguageText)
        XCTAssertTrue(density.showsPath)
        XCTAssertFalse(density.showsStats)
        XCTAssertTrue(density.showsSaveText)
        XCTAssertLessThanOrEqual(density.pathMaxWidth, 150)
    }

    func testWideWindowsUseFullStatusBar() {
        let density = StatusBarDensity(width: 900)

        XCTAssertEqual(density, .regular)
        XCTAssertTrue(density.showsLanguageText)
        XCTAssertTrue(density.showsPath)
        XCTAssertTrue(density.showsStats)
        XCTAssertTrue(density.showsSaveText)
        XCTAssertGreaterThanOrEqual(density.pathMaxWidth, 340)
    }
}
