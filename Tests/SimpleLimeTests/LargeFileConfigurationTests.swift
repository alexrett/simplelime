import XCTest
@testable import SimpleLime

final class LargeFileConfigurationTests: XCTestCase {
    override func tearDownWithError() throws {
        clearStandardDefaults()
    }

    func testConfigurationUsesLanguageSpecificThresholdsAndPreviewLimits() throws {
        let defaults = try makeDefaults()
        defaults.set(2 * 1024 * 1024, forKey: LargeFileConfiguration.generalThresholdDefaultsKey)
        defaults.set(128 * 1024, forKey: LargeFileConfiguration.complexThresholdDefaultsKey)
        defaults.set(512 * 1024, forKey: LargeFileConfiguration.generalPreviewByteLimitDefaultsKey)
        defaults.set(32 * 1024, forKey: LargeFileConfiguration.complexPreviewByteLimitDefaultsKey)

        XCTAssertEqual(LargeFileConfiguration.thresholdBytes(for: .markdown, defaults: defaults), 2 * 1024 * 1024)
        XCTAssertEqual(LargeFileConfiguration.thresholdBytes(for: .json, defaults: defaults), 128 * 1024)
        XCTAssertEqual(LargeFileConfiguration.previewByteLimit(for: .markdown, defaults: defaults), 512 * 1024)
        XCTAssertEqual(LargeFileConfiguration.previewByteLimit(for: .json, defaults: defaults), 32 * 1024)
        XCTAssertTrue(LargeFileConfiguration.shouldUseLargeFileMode(fileSizeBytes: 130 * 1024, language: .json, defaults: defaults))
        XCTAssertFalse(LargeFileConfiguration.shouldUseLargeFileMode(fileSizeBytes: 130 * 1024, language: .markdown, defaults: defaults))
    }

    func testConfigurationClampsUnsafeValues() throws {
        let defaults = try makeDefaults()
        defaults.set(1, forKey: LargeFileConfiguration.generalThresholdDefaultsKey)
        defaults.set(Int.max, forKey: LargeFileConfiguration.complexThresholdDefaultsKey)
        defaults.set(1, forKey: LargeFileConfiguration.generalPreviewByteLimitDefaultsKey)
        defaults.set(Int.max, forKey: LargeFileConfiguration.complexPreviewByteLimitDefaultsKey)

        XCTAssertEqual(
            LargeFileConfiguration.thresholdBytes(for: .markdown, defaults: defaults),
            Int64(LargeFileConfiguration.minimumThresholdBytes)
        )
        XCTAssertEqual(
            LargeFileConfiguration.thresholdBytes(for: .json, defaults: defaults),
            Int64(LargeFileConfiguration.maximumComplexThresholdBytes)
        )
        XCTAssertEqual(
            LargeFileConfiguration.previewByteLimit(for: .markdown, defaults: defaults),
            LargeFileConfiguration.minimumPreviewByteLimit
        )
        XCTAssertEqual(
            LargeFileConfiguration.previewByteLimit(for: .json, defaults: defaults),
            LargeFileConfiguration.maximumPreviewByteLimit
        )
    }

    func testEditorStoreLargeFileHelpersReadConfiguredDefaults() {
        clearStandardDefaults()
        let defaults = UserDefaults.standard
        defaults.set(128 * 1024, forKey: LargeFileConfiguration.complexThresholdDefaultsKey)
        defaults.set(32 * 1024, forKey: LargeFileConfiguration.complexPreviewByteLimitDefaultsKey)
        defer { clearStandardDefaults() }

        XCTAssertTrue(EditorStore.shouldUseLargeFileMode(fileSizeBytes: 130 * 1024, language: .json))
        XCTAssertFalse(EditorStore.shouldUseLargeFileMode(fileSizeBytes: 130 * 1024, language: .markdown))
        XCTAssertEqual(EditorStore.largeFilePreviewByteLimit(for: .json), 32 * 1024)
        XCTAssertEqual(EditorStore.largeFilePreviewByteLimit(for: .markdown), EditorStore.largeFilePreviewByteLimit)
    }

    func testComplexThresholdCannotBeRaisedAboveSafetyCap() throws {
        let defaults = try makeDefaults()
        defaults.set(8 * 1024 * 1024, forKey: LargeFileConfiguration.complexThresholdDefaultsKey)

        XCTAssertEqual(
            LargeFileConfiguration.thresholdBytes(for: .json, defaults: defaults),
            Int64(LargeFileConfiguration.maximumComplexThresholdBytes)
        )
        XCTAssertTrue(
            LargeFileConfiguration.shouldUseLargeFileMode(
                fileSizeBytes: Int64(LargeFileConfiguration.maximumComplexThresholdBytes) + 1,
                language: .json,
                defaults: defaults
            )
        )
        XCTAssertEqual(
            LargeFileConfiguration.clampedThresholdBytes(8 * 1024 * 1024, for: .json),
            LargeFileConfiguration.maximumComplexThresholdBytes
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SimpleLimeLargeFileConfigurationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func clearStandardDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: LargeFileConfiguration.generalThresholdDefaultsKey)
        defaults.removeObject(forKey: LargeFileConfiguration.complexThresholdDefaultsKey)
        defaults.removeObject(forKey: LargeFileConfiguration.generalPreviewByteLimitDefaultsKey)
        defaults.removeObject(forKey: LargeFileConfiguration.complexPreviewByteLimitDefaultsKey)
    }
}
