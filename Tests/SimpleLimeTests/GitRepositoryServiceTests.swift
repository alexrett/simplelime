import XCTest
@testable import SimpleLime

final class GitRepositoryServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-git-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testRepositoryDetectionUsesGitRoot() throws {
        try initializeRepository()
        let nested = temporaryDirectory.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("note.txt")
        try "note".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            GitRepositoryService.repository(containingFileAt: file)?.rootURL.standardizedFileURL,
            temporaryDirectory.standardizedFileURL
        )
    }

    func testCommitStagesOnlyTargetFile() throws {
        try initializeRepository()
        let committed = temporaryDirectory.appendingPathComponent("committed.txt")
        let uncommitted = temporaryDirectory.appendingPathComponent("uncommitted.txt")
        try "committed".write(to: committed, atomically: true, encoding: .utf8)
        try "uncommitted".write(to: uncommitted, atomically: true, encoding: .utf8)

        try GitRepositoryService.commit(fileURL: committed, message: "Add committed file")

        let log = try GitRepositoryService.runGit(["-C", temporaryDirectory.path, "log", "--oneline", "--", "committed.txt"])
        let status = try GitRepositoryService.runGit(["-C", temporaryDirectory.path, "status", "--short"])

        XCTAssertTrue(log.contains("Add committed file"), log)
        let statusLines = status.split(separator: "\n").map(String.init)
        XCTAssertTrue(statusLines.contains("?? uncommitted.txt"), status)
        XCTAssertFalse(statusLines.contains("?? committed.txt"), status)
        XCTAssertFalse(statusLines.contains("A  committed.txt"), status)
        XCTAssertFalse(statusLines.contains(" M committed.txt"), status)
    }

    private func initializeRepository() throws {
        try GitRepositoryService.runGit(["init", temporaryDirectory.path])
        try GitRepositoryService.runGit(["-C", temporaryDirectory.path, "config", "user.email", "simplelime-tests@example.com"])
        try GitRepositoryService.runGit(["-C", temporaryDirectory.path, "config", "user.name", "SimpleLime Tests"])
        try GitRepositoryService.runGit(["-C", temporaryDirectory.path, "config", "commit.gpgsign", "false"])
    }
}
