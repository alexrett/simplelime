import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreGitTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-store-git-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try GitRepositoryService.runGit(["init", temporaryDirectory.path])
        try GitRepositoryService.runGit(["-C", temporaryDirectory.path, "config", "user.email", "simplelime-tests@example.com"])
        try GitRepositoryService.runGit(["-C", temporaryDirectory.path, "config", "user.name", "SimpleLime Tests"])
        try GitRepositoryService.runGit(["-C", temporaryDirectory.path, "config", "commit.gpgsign", "false"])
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testCommitSelectedFileSavesStagesAndCommitsCurrentBuffer() throws {
        let file = temporaryDirectory.appendingPathComponent("note.txt")
        try "old".write(to: file, atomically: true, encoding: .utf8)
        try GitRepositoryService.commit(fileURL: file, message: "Initial note")

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.filePath = file.path
        buffer.title = file.lastPathComponent
        buffer.text = "new"
        buffer.language = .plain
        buffer.isDirty = true

        let network = NetworkShareService(startNetworkServices: false)
        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            networkShare: network,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.commitSelectedFile(message: "Update note")

        let log = try GitRepositoryService.runGit(["-C", temporaryDirectory.path, "log", "--oneline", "--", "note.txt"])
        XCTAssertEqual(try String(contentsOf: file), "new")
        XCTAssertEqual(store.selectedBuffer?.isDirty, false)
        XCTAssertEqual(network.statusMessage, "Committed note.txt.")
        XCTAssertTrue(log.contains("Update note"), log)
    }

    func testCommitSelectedScratchReportsSaveFirstError() {
        let buffer = EditorBuffer.scratch(index: 1)
        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.commitSelectedFile(message: "No file")

        XCTAssertEqual(store.lastError, "Save this scratch buffer before committing it.")
    }
}
