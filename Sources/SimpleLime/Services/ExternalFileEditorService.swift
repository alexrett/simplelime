import AppKit
import Foundation

enum ExternalFileEditorService {
    static let simpleShotBundleIdentifiers = [
        "com.malikov.simpleshot",
        "com.whitehappypony.SimpleShot",
        "com.whitehappypony.simpleshot"
    ]

    static func simpleShotApplicationURL(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) -> URL? {
        for bundleIdentifier in simpleShotBundleIdentifiers {
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }

        return applicationURL(named: "SimpleShot.app", fileManager: fileManager)
    }

    static func applicationURL(
        named appBundleName: String,
        searchRoots: [URL] = defaultApplicationSearchRoots(),
        fileManager: FileManager = .default
    ) -> URL? {
        let normalizedName = appBundleName.hasSuffix(".app") ? appBundleName : "\(appBundleName).app"

        for root in searchRoots {
            let candidate = root.appendingPathComponent(normalizedName, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate
            }
        }

        return nil
    }

    static func defaultApplicationSearchRoots(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let roots = fileManager.urls(for: .applicationDirectory, in: .localDomainMask) +
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask) +
            [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                homeDirectory.appendingPathComponent("Applications", isDirectory: true),
                URL(fileURLWithPath: "/System/Applications", isDirectory: true)
            ]

        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    @discardableResult
    static func openInSimpleShot(
        _ fileURL: URL,
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let appURL = simpleShotApplicationURL(workspace: workspace, fileManager: fileManager) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        workspace.open([fileURL], withApplicationAt: appURL, configuration: configuration)
        return true
    }

    @discardableResult
    static func openInDefaultApplication(
        _ fileURL: URL,
        workspace: NSWorkspace = .shared
    ) -> Bool {
        workspace.open(fileURL)
    }

    static func revealInFinder(
        _ fileURL: URL,
        workspace: NSWorkspace = .shared
    ) {
        workspace.activateFileViewerSelecting([fileURL])
    }
}
