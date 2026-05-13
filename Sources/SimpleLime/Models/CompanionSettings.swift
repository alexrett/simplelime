import Foundation

enum CompanionSettings {
    static let includeSystemContextDefaultsKey = "ai.companion.includeSystemContext"
    static let includeAccessibilityContextDefaultsKey = "ai.companion.includeAccessibilityContext"
    static let includeScreenTextContextDefaultsKey = "ai.companion.includeScreenTextContext"
    static let defaultIncludesSystemContext = true
    static let defaultIncludesAccessibilityContext = false
    static let defaultIncludesScreenTextContext = false

    static func includesSystemContext(defaults: UserDefaults = .standard) -> Bool {
        guard let stored = defaults.object(forKey: includeSystemContextDefaultsKey) as? NSNumber else {
            return defaultIncludesSystemContext
        }

        return stored.boolValue
    }

    static func includesAccessibilityContext(defaults: UserDefaults = .standard) -> Bool {
        guard let stored = defaults.object(forKey: includeAccessibilityContextDefaultsKey) as? NSNumber else {
            return defaultIncludesAccessibilityContext
        }

        return stored.boolValue
    }

    static func includesScreenTextContext(defaults: UserDefaults = .standard) -> Bool {
        guard let stored = defaults.object(forKey: includeScreenTextContextDefaultsKey) as? NSNumber else {
            return defaultIncludesScreenTextContext
        }

        return stored.boolValue
    }
}
