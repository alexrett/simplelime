import Foundation

struct AppDataRootSnapshot: Equatable {
    struct Entry: Equatable, Comparable {
        var relativePath: String
        var sizeBytes: Int64
        var modifiedAt: TimeInterval

        static func < (lhs: Entry, rhs: Entry) -> Bool {
            lhs.relativePath < rhs.relativePath
        }
    }

    var entries: [Entry]
    var reachedEntryLimit: Bool

    static func capture(
        rootURL: URL,
        fileManager: FileManager = .default,
        maxEntries: Int = 2_000
    ) -> AppDataRootSnapshot {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return AppDataRootSnapshot(entries: [], reachedEntryLimit: false)
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return AppDataRootSnapshot(entries: [], reachedEntryLimit: false)
        }

        let rootPath = rootURL.standardizedFileURL.path
        var entries: [Entry] = []
        var reachedEntryLimit = false

        for case let url as URL in enumerator {
            guard entries.count < maxEntries else {
                reachedEntryLimit = true
                break
            }

            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  values.isDirectory != true else {
                continue
            }

            entries.append(
                Entry(
                    relativePath: Self.relativePath(for: url, rootPath: rootPath),
                    sizeBytes: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
                )
            )
        }

        entries.sort()
        return AppDataRootSnapshot(entries: entries, reachedEntryLimit: reachedEntryLimit)
    }

    private static func relativePath(for url: URL, rootPath: String) -> String {
        let path = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        guard path.hasPrefix(prefix) else { return url.lastPathComponent }
        return String(path.dropFirst(prefix.count))
    }
}
