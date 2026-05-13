import XCTest
@testable import SimpleLime

final class TerminalConfigurationTests: XCTestCase {
    func testCurrentShellPathUsesConfiguredSetting() throws {
        let defaults = try makeDefaults()
        defaults.set("  /opt/homebrew/bin/zsh  ", forKey: TerminalConfiguration.shellPathDefaultsKey)

        XCTAssertEqual(
            TerminalConfiguration.currentShellPath(defaults: defaults, environment: ["SHELL": "/bin/bash"]),
            "/opt/homebrew/bin/zsh"
        )
    }

    func testCurrentShellPathFallsBackToEnvironmentShell() throws {
        let defaults = try makeDefaults()

        XCTAssertEqual(
            TerminalConfiguration.currentShellPath(defaults: defaults, environment: ["SHELL": "/bin/bash"]),
            "/bin/bash"
        )
    }

    func testCurrentShellPathFallsBackToZshWhenSettingAndEnvironmentAreEmpty() throws {
        let defaults = try makeDefaults()
        defaults.set(" ", forKey: TerminalConfiguration.shellPathDefaultsKey)

        XCTAssertEqual(
            TerminalConfiguration.currentShellPath(defaults: defaults, environment: [:]),
            "/bin/zsh"
        )
    }

    func testCurrentTerminalTypeUsesConfiguredSettingAndSanitizesUnsafeCharacters() throws {
        let defaults = try makeDefaults()
        defaults.set("  xterm-256color;bad=value  ", forKey: TerminalConfiguration.terminalTypeDefaultsKey)

        XCTAssertEqual(TerminalConfiguration.currentTerminalType(defaults: defaults), "xterm-256colorbadvalue")
    }

    func testCurrentTerminalTypeFallsBackToDefaultWhenEmpty() throws {
        let defaults = try makeDefaults()
        defaults.set(" = ", forKey: TerminalConfiguration.terminalTypeDefaultsKey)

        XCTAssertEqual(TerminalConfiguration.currentTerminalType(defaults: defaults), "xterm-256color")
    }

    func testCurrentLocaleUsesConfiguredUTF8Setting() throws {
        let defaults = try makeDefaults()
        defaults.set("  de_DE.UTF-8  ", forKey: TerminalConfiguration.localeDefaultsKey)

        XCTAssertEqual(TerminalConfiguration.currentLocale(defaults: defaults), "de_DE.UTF-8")
    }

    func testCurrentLocaleFallsBackToDefaultWhenLocaleIsNotUTF8() throws {
        let defaults = try makeDefaults()
        defaults.set("C", forKey: TerminalConfiguration.localeDefaultsKey)

        XCTAssertEqual(TerminalConfiguration.currentLocale(defaults: defaults), "en_US.UTF-8")
    }

    func testSanitizedLocaleFiltersUnsafeCharacters() {
        XCTAssertEqual(
            TerminalConfiguration.sanitizedLocale(" ru_RU.UTF-8;bad=value "),
            "ru_RU.UTF-8badvalue"
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SimpleLimeTerminalConfigurationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
