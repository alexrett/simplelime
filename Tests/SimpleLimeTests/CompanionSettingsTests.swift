import XCTest
@testable import SimpleLime

final class CompanionSettingsTests: XCTestCase {
    func testAccessibilityContextIsOptIn() {
        let suiteName = "simplelime-companion-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(CompanionSettings.includesSystemContext(defaults: defaults))
        XCTAssertFalse(CompanionSettings.includesAccessibilityContext(defaults: defaults))
        XCTAssertFalse(CompanionSettings.includesScreenTextContext(defaults: defaults))

        defaults.set(true, forKey: CompanionSettings.includeAccessibilityContextDefaultsKey)
        defaults.set(true, forKey: CompanionSettings.includeScreenTextContextDefaultsKey)
        XCTAssertTrue(CompanionSettings.includesAccessibilityContext(defaults: defaults))
        XCTAssertTrue(CompanionSettings.includesScreenTextContext(defaults: defaults))
    }
}
