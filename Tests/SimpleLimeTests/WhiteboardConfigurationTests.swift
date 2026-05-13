import XCTest
@testable import SimpleLime

final class WhiteboardConfigurationTests: XCTestCase {
    func testDefaultsAreUsedWhenSettingsAreMissing() throws {
        let defaults = try makeDefaults()

        XCTAssertTrue(WhiteboardConfiguration.showsGrid(defaults: defaults))
        XCTAssertEqual(WhiteboardConfiguration.gridSpacing(defaults: defaults), 24)
        XCTAssertTrue(WhiteboardConfiguration.connectorArrows(defaults: defaults))
        XCTAssertEqual(WhiteboardConfiguration.connectorRouting(defaults: defaults), .orthogonal)
        XCTAssertEqual(WhiteboardConfiguration.stickyFill(defaults: defaults), .yellow)
    }

    func testStoredWhiteboardDefaultsAreReadAndClamped() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: WhiteboardConfiguration.showsGridDefaultsKey)
        defaults.set(256, forKey: WhiteboardConfiguration.gridSpacingDefaultsKey)
        defaults.set(false, forKey: WhiteboardConfiguration.connectorArrowsDefaultsKey)
        defaults.set(WhiteboardConnectorRouting.verticalFirst.rawValue, forKey: WhiteboardConfiguration.connectorRoutingDefaultsKey)
        defaults.set(WhiteboardFill.green.rawValue, forKey: WhiteboardConfiguration.stickyFillDefaultsKey)

        XCTAssertFalse(WhiteboardConfiguration.showsGrid(defaults: defaults))
        XCTAssertEqual(WhiteboardConfiguration.gridSpacing(defaults: defaults), WhiteboardConfiguration.maximumGridSpacing)
        XCTAssertFalse(WhiteboardConfiguration.connectorArrows(defaults: defaults))
        XCTAssertEqual(WhiteboardConfiguration.connectorRouting(defaults: defaults), .verticalFirst)
        XCTAssertEqual(WhiteboardConfiguration.stickyFill(defaults: defaults), .green)
    }

    func testInvalidPickerValuesFallBackToSafeDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set("bad-routing", forKey: WhiteboardConfiguration.connectorRoutingDefaultsKey)
        defaults.set("bad-fill", forKey: WhiteboardConfiguration.stickyFillDefaultsKey)
        defaults.set(1, forKey: WhiteboardConfiguration.gridSpacingDefaultsKey)

        XCTAssertEqual(WhiteboardConfiguration.connectorRouting(defaults: defaults), .orthogonal)
        XCTAssertEqual(WhiteboardConfiguration.stickyFill(defaults: defaults), .yellow)
        XCTAssertEqual(WhiteboardConfiguration.gridSpacing(defaults: defaults), WhiteboardConfiguration.minimumGridSpacing)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SimpleLimeWhiteboardConfigurationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
