import Foundation

enum AppDataStorage {
    static let rootPathDefaultsKey = "appData.rootPath"

    static func currentRootURL(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> URL {
        let configuredPath = defaults.string(forKey: rootPathDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let configuredPath, !configuredPath.isEmpty else {
            return defaultRootURL(fileManager: fileManager)
        }

        return URL(fileURLWithPath: configuredPath, isDirectory: true).standardizedFileURL
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return baseURL.appendingPathComponent("SimpleLime", isDirectory: true)
    }

    static func setCustomRootURL(_ url: URL, defaults: UserDefaults = .standard) {
        defaults.set(url.standardizedFileURL.path, forKey: rootPathDefaultsKey)
    }

    static func resetCustomRoot(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: rootPathDefaultsKey)
    }

    static func suggestedICloudDriveRootURL(fileManager: FileManager = .default) -> URL? {
        if let ubiquityURL = fileManager.url(forUbiquityContainerIdentifier: nil) {
            return ubiquityURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("SimpleLime", isDirectory: true)
                .standardizedFileURL
        }

        let cloudDocsParent = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)

        guard fileManager.fileExists(atPath: cloudDocsParent.path) else {
            return nil
        }

        return cloudDocsParent
            .appendingPathComponent("SimpleLime", isDirectory: true)
            .standardizedFileURL
    }

    static func copyExistingData(
        from sourceRootURL: URL,
        to targetRootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let source = sourceRootURL.standardizedFileURL
        let target = targetRootURL.standardizedFileURL
        guard source.path != target.path, fileManager.fileExists(atPath: source.path) else {
            return
        }

        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try mergeDirectoryContents(from: source, to: target, fileManager: fileManager)
    }

    private static func mergeDirectoryContents(
        from source: URL,
        to target: URL,
        fileManager: FileManager
    ) throws {
        let children = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for child in children {
            let destination = target.appendingPathComponent(child.lastPathComponent, isDirectory: child.hasDirectoryPath)
            try mergeItem(from: child, to: destination, fileManager: fileManager)
        }
    }

    private static func mergeItem(
        from source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        var sourceIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: source.path, isDirectory: &sourceIsDirectory) else {
            return
        }

        var destinationIsDirectory = ObjCBool(false)
        let destinationExists = fileManager.fileExists(atPath: destination.path, isDirectory: &destinationIsDirectory)

        if sourceIsDirectory.boolValue {
            guard !destinationExists || destinationIsDirectory.boolValue else {
                if shouldReplaceDestination(source: source, destination: destination) {
                    try preserveConflictCopyIfNeeded(from: destination, against: source, at: destination, fileManager: fileManager)
                    try fileManager.removeItem(at: destination)
                    try fileManager.copyItem(at: source, to: destination)
                } else {
                    try preserveConflictCopyIfNeeded(from: source, against: destination, at: destination, fileManager: fileManager)
                }
                return
            }

            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try mergeDirectoryContents(from: source, to: destination, fileManager: fileManager)
            return
        }

        guard destinationExists else {
            try fileManager.copyItem(at: source, to: destination)
            return
        }

        guard !destinationIsDirectory.boolValue else {
            if shouldReplaceDestination(source: source, destination: destination) {
                try preserveConflictCopyIfNeeded(from: destination, against: source, at: destination, fileManager: fileManager)
                try fileManager.removeItem(at: destination)
                try fileManager.copyItem(at: source, to: destination)
            } else {
                try preserveConflictCopyIfNeeded(from: source, against: destination, at: destination, fileManager: fileManager)
            }
            return
        }

        guard shouldReplaceDestination(source: source, destination: destination) else {
            try preserveConflictCopyIfNeeded(from: source, against: destination, at: destination, fileManager: fileManager)
            return
        }

        try preserveConflictCopyIfNeeded(from: destination, against: source, at: destination, fileManager: fileManager)
        try fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func shouldReplaceDestination(source: URL, destination: URL) -> Bool {
        guard
            let sourceDate = try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            let destinationDate = try? destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else {
            return true
        }

        return sourceDate > destinationDate
    }

    private static func preserveConflictCopyIfNeeded(
        from losingItem: URL,
        against winningItem: URL,
        at originalDestination: URL,
        fileManager: FileManager
    ) throws {
        guard needsConflictCopy(losingItem: losingItem, winningItem: winningItem, fileManager: fileManager) else {
            return
        }

        let conflictURL = nextConflictURL(
            for: originalDestination,
            timestamp: contentModificationDate(for: losingItem) ?? Date(),
            fileManager: fileManager
        )
        try fileManager.copyItem(at: losingItem, to: conflictURL)
    }

    private static func needsConflictCopy(
        losingItem: URL,
        winningItem: URL,
        fileManager: FileManager
    ) -> Bool {
        var losingIsDirectory = ObjCBool(false)
        var winningIsDirectory = ObjCBool(false)
        guard
            fileManager.fileExists(atPath: losingItem.path, isDirectory: &losingIsDirectory),
            fileManager.fileExists(atPath: winningItem.path, isDirectory: &winningIsDirectory)
        else {
            return false
        }

        guard !losingIsDirectory.boolValue, !winningIsDirectory.boolValue else {
            return true
        }

        return !fileManager.contentsEqual(atPath: losingItem.path, andPath: winningItem.path)
    }

    private static func nextConflictURL(
        for originalURL: URL,
        timestamp: Date,
        fileManager: FileManager
    ) -> URL {
        let directory = originalURL.deletingLastPathComponent()
        let fileExtension = originalURL.pathExtension
        let baseName = fileExtension.isEmpty
            ? originalURL.lastPathComponent
            : originalURL.deletingPathExtension().lastPathComponent
        let timestampString = conflictTimestampFormatter.string(from: timestamp)

        func candidate(_ suffix: String = "") -> URL {
            let fileName = fileExtension.isEmpty
                ? "\(baseName).conflict-\(timestampString)\(suffix)"
                : "\(baseName).conflict-\(timestampString)\(suffix).\(fileExtension)"
            return directory.appendingPathComponent(fileName)
        }

        var attempt = candidate()
        var index = 2
        while fileManager.fileExists(atPath: attempt.path) {
            attempt = candidate("-\(index)")
            index += 1
        }
        return attempt
    }

    private static var conflictTimestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }

    private static func contentModificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
