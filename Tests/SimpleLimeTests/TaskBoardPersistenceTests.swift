import XCTest
@testable import SimpleLime

final class TaskBoardPersistenceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-task-board-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testRoundTripsManualTasks() throws {
        let url = temporaryDirectory.appendingPathComponent("tasks.json")
        let persistence = TaskBoardPersistence(boardURL: url)
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let tasks = [
            ManualTask(id: UUID(), title: "Write PRD", status: .todo, createdAt: now, updatedAt: now),
            ManualTask(id: UUID(), title: "Review", status: .inProgress, createdAt: now, updatedAt: now, scope: .global)
        ]

        try persistence.save(tasks)

        XCTAssertEqual(persistence.load(), tasks)
    }

    func testLegacyManualTasksWithoutScopeLoadAsWorkspaceTasks() throws {
        let url = temporaryDirectory.appendingPathComponent("legacy-tasks.json")
        let taskID = UUID()
        let json = """
        {
          "manualTasks" : [
            {
              "createdAt" : "2026-05-12T00:00:00Z",
              "id" : "\(taskID.uuidString)",
              "status" : "todo",
              "title" : "Legacy task",
              "updatedAt" : "2026-05-12T00:00:00Z"
            }
          ]
        }
        """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let tasks = TaskBoardPersistence(boardURL: url).load()

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.scope, .workspace)
        XCTAssertEqual(tasks.first?.title, "Legacy task")
    }
}
