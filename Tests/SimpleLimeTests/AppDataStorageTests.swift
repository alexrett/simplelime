import XCTest
@testable import SimpleLime

final class AppDataStorageTests: XCTestCase {
    func testCurrentRootUsesConfiguredPath() throws {
        let defaults = try makeDefaults()
        let root = try makeTemporaryDirectory().appendingPathComponent("CloudRoot", isDirectory: true)

        defaults.set("  \(root.path)  ", forKey: AppDataStorage.rootPathDefaultsKey)

        XCTAssertEqual(
            AppDataStorage.currentRootURL(defaults: defaults),
            root.standardizedFileURL
        )
    }

    func testResetCustomRootFallsBackToDefaultRoot() throws {
        let defaults = try makeDefaults()
        let root = try makeTemporaryDirectory().appendingPathComponent("CustomRoot", isDirectory: true)
        AppDataStorage.setCustomRootURL(root, defaults: defaults)

        AppDataStorage.resetCustomRoot(defaults: defaults)

        XCTAssertEqual(
            AppDataStorage.currentRootURL(defaults: defaults),
            AppDataStorage.defaultRootURL()
        )
    }

    func testCopyExistingDataReplacesOlderTargetFileAndPreservesTargetConflictCopy() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let source = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        let target = temporaryDirectory.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try write(
            "new",
            to: source.appendingPathComponent("session.json"),
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        try write(
            "old",
            to: target.appendingPathComponent("session.json"),
            modificationDate: Date(timeIntervalSince1970: 1_000)
        )

        try AppDataStorage.copyExistingData(from: source, to: target)

        let copied = try String(contentsOf: target.appendingPathComponent("session.json"), encoding: .utf8)
        XCTAssertEqual(copied, "new")

        let conflicts = try conflictFiles(in: target, matching: "session.conflict-", extension: "json")
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(try String(contentsOf: conflicts[0], encoding: .utf8), "old")
    }

    func testCopyExistingDataKeepsNewerTargetFileAndPreservesSourceConflictCopy() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let source = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        let target = temporaryDirectory.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try write(
            "local",
            to: source.appendingPathComponent("session.json"),
            modificationDate: Date(timeIntervalSince1970: 1_000)
        )
        try write(
            "cloud",
            to: target.appendingPathComponent("session.json"),
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )

        try AppDataStorage.copyExistingData(from: source, to: target)

        let copied = try String(contentsOf: target.appendingPathComponent("session.json"), encoding: .utf8)
        XCTAssertEqual(copied, "cloud")

        let conflicts = try conflictFiles(in: target, matching: "session.conflict-", extension: "json")
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(try String(contentsOf: conflicts[0], encoding: .utf8), "local")
    }

    func testCopyExistingDataSkipsConflictCopyForIdenticalFileContent() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let source = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        let target = temporaryDirectory.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try write(
            "same",
            to: source.appendingPathComponent("session.json"),
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        try write(
            "same",
            to: target.appendingPathComponent("session.json"),
            modificationDate: Date(timeIntervalSince1970: 1_000)
        )

        try AppDataStorage.copyExistingData(from: source, to: target)

        let copied = try String(contentsOf: target.appendingPathComponent("session.json"), encoding: .utf8)
        XCTAssertEqual(copied, "same")
        XCTAssertTrue(try conflictFiles(in: target, matching: "session.conflict-", extension: "json").isEmpty)
    }

    func testCopyExistingDataMergesNestedDirectoriesWithoutDeletingTargetOnlyChildren() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let source = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        let target = temporaryDirectory.appendingPathComponent("target", isDirectory: true)
        let sourceWorkspaces = source.appendingPathComponent("Workspaces", isDirectory: true)
        let targetWorkspaces = target.appendingPathComponent("Workspaces", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceWorkspaces, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetWorkspaces, withIntermediateDirectories: true)
        try write(
            "local",
            to: sourceWorkspaces.appendingPathComponent("local.json"),
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        try write(
            "cloud",
            to: targetWorkspaces.appendingPathComponent("cloud.json"),
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        try write(
            "local-stale",
            to: sourceWorkspaces.appendingPathComponent("shared.json"),
            modificationDate: Date(timeIntervalSince1970: 1_000)
        )
        try write(
            "cloud-fresh",
            to: targetWorkspaces.appendingPathComponent("shared.json"),
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )

        try AppDataStorage.copyExistingData(from: source, to: target)

        let local = try String(contentsOf: targetWorkspaces.appendingPathComponent("local.json"), encoding: .utf8)
        let cloud = try String(contentsOf: targetWorkspaces.appendingPathComponent("cloud.json"), encoding: .utf8)
        let shared = try String(contentsOf: targetWorkspaces.appendingPathComponent("shared.json"), encoding: .utf8)
        XCTAssertEqual(local, "local")
        XCTAssertEqual(cloud, "cloud")
        XCTAssertEqual(shared, "cloud-fresh")

        let conflicts = try conflictFiles(in: targetWorkspaces, matching: "shared.conflict-", extension: "json")
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(try String(contentsOf: conflicts[0], encoding: .utf8), "local-stale")
    }

    func testSidecarDefaultURLsUseConfiguredAppDataRoot() throws {
        let defaults = try makeDefaults()
        let root = try makeTemporaryDirectory().appendingPathComponent("SyncedRoot", isDirectory: true)
        AppDataStorage.setCustomRootURL(root, defaults: defaults)

        XCTAssertEqual(SessionPersistence.defaultRootURL(defaults: defaults), root.standardizedFileURL)
        XCTAssertEqual(TaskBoardPersistence.defaultBoardURL(defaults: defaults), root.appendingPathComponent("tasks.json"))
        XCTAssertEqual(UsageStatsPersistence.defaultStatsURL(defaults: defaults), root.appendingPathComponent("usage-stats.json"))
        XCTAssertEqual(TextMacroPersistence.defaultMacrosURL(defaults: defaults), root.appendingPathComponent("macros.json"))
        XCTAssertEqual(DocumentCommentPersistence.defaultCommentsURL(defaults: defaults), root.appendingPathComponent("comments.json"))
        XCTAssertEqual(AIBufferFileBridge.defaultRootURL(defaults: defaults), root.appendingPathComponent("AgentBuffers", isDirectory: true))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SimpleLimeAppDataStorageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-app-data-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ value: String, to url: URL, modificationDate: Date) throws {
        try value.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)
    }

    private func conflictFiles(in directory: URL, matching prefix: String, extension fileExtension: String) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { url in
                url.lastPathComponent.hasPrefix(prefix) && url.pathExtension == fileExtension
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
