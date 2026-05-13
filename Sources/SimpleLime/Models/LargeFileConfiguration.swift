import Foundation

enum LargeFileConfiguration {
    static let generalThresholdDefaultsKey = "largeFile.generalThresholdBytes"
    static let complexThresholdDefaultsKey = "largeFile.complexThresholdBytes"
    static let generalPreviewByteLimitDefaultsKey = "largeFile.generalPreviewByteLimit"
    static let complexPreviewByteLimitDefaultsKey = "largeFile.complexPreviewByteLimit"

    static let defaultGeneralThresholdBytes = 5 * 1024 * 1024
    static let defaultComplexThresholdBytes = 512 * 1024
    static let defaultGeneralPreviewByteLimit = 256 * 1024
    static let defaultComplexPreviewByteLimit = 16 * 1024

    static let minimumThresholdBytes = 64 * 1024
    static let maximumThresholdBytes = 512 * 1024 * 1024
    static let maximumComplexThresholdBytes = defaultComplexThresholdBytes
    static let minimumPreviewByteLimit = 16 * 1024
    static let maximumPreviewByteLimit = 4 * 1024 * 1024

    static func thresholdBytes(
        for language: EditorLanguage,
        defaults: UserDefaults = .standard
    ) -> Int64 {
        let key = language.usesComplexTextLargeFileThreshold
            ? complexThresholdDefaultsKey
            : generalThresholdDefaultsKey
        let fallback = language.usesComplexTextLargeFileThreshold
            ? defaultComplexThresholdBytes
            : defaultGeneralThresholdBytes
        return Int64(clampedThresholdBytes(
            intValue(forKey: key, defaults: defaults, fallback: fallback),
            for: language
        ))
    }

    static func previewByteLimit(
        for language: EditorLanguage,
        defaults: UserDefaults = .standard
    ) -> Int {
        let key = language.usesComplexTextLargeFileThreshold
            ? complexPreviewByteLimitDefaultsKey
            : generalPreviewByteLimitDefaultsKey
        let fallback = language.usesComplexTextLargeFileThreshold
            ? defaultComplexPreviewByteLimit
            : defaultGeneralPreviewByteLimit
        return clampedPreviewByteLimit(intValue(forKey: key, defaults: defaults, fallback: fallback))
    }

    static func shouldUseLargeFileMode(
        fileSizeBytes: Int64?,
        language: EditorLanguage,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let fileSizeBytes else { return false }
        return fileSizeBytes >= thresholdBytes(for: language, defaults: defaults)
    }

    static func clampedThresholdBytes(_ value: Int) -> Int {
        min(max(value, minimumThresholdBytes), maximumThresholdBytes)
    }

    static func clampedThresholdBytes(_ value: Int, for language: EditorLanguage) -> Int {
        let clamped = clampedThresholdBytes(value)
        guard language.usesComplexTextLargeFileThreshold else {
            return clamped
        }

        return min(clamped, maximumComplexThresholdBytes)
    }

    static func maximumThresholdBytes(for language: EditorLanguage) -> Int {
        language.usesComplexTextLargeFileThreshold ? maximumComplexThresholdBytes : maximumThresholdBytes
    }

    static func clampedPreviewByteLimit(_ value: Int) -> Int {
        min(max(value, minimumPreviewByteLimit), maximumPreviewByteLimit)
    }

    private static func intValue(
        forKey key: String,
        defaults: UserDefaults,
        fallback: Int
    ) -> Int {
        guard let number = defaults.object(forKey: key) as? NSNumber else {
            return fallback
        }

        return number.intValue
    }
}
