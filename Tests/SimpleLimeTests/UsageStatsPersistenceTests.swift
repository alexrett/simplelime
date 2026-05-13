import XCTest
@testable import SimpleLime

final class UsageStatsPersistenceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-usage-stats-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testRoundTripsUsageStats() throws {
        let url = temporaryDirectory.appendingPathComponent("usage-stats.json")
        let persistence = UsageStatsPersistence(statsURL: url)
        var day = DailyUsageStats.empty(day: "2026-05-11")
        day.editCount = 3
        day.charactersAdded = 10
        day.macroCount = 1
        day.uniqueDocumentKeys = ["scratch:1", "/tmp/a.txt"]
        day.timelineEntries = [
            UsageTimelineEntry(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                timestamp: Date(timeIntervalSince1970: 1_800_000_000),
                kind: .macro,
                title: "Played macro PRD",
                documentKey: "scratch:1",
                durationSeconds: 2
            )
        ]

        try persistence.save([day])

        XCTAssertEqual(persistence.load(), [day])
    }

    func testLoadsLegacyUsageStatsWithoutTimelogFields() throws {
        let url = temporaryDirectory.appendingPathComponent("legacy-usage-stats.json")
        let persistence = UsageStatsPersistence(statsURL: url)
        let legacyJSON = """
        {
          "days": [
            {
              "day": "2026-05-10",
              "editCount": 2,
              "charactersAdded": 5,
              "charactersRemoved": 1,
              "openCount": 1,
              "saveCount": 1,
              "exportCount": 0,
              "activeEditingSeconds": 12,
              "uniqueDocumentKeys": ["scratch:legacy"]
            }
          ]
        }
        """
        try legacyJSON.write(to: url, atomically: true, encoding: .utf8)

        let day = try XCTUnwrap(persistence.load().first)
        XCTAssertEqual(day.day, "2026-05-10")
        XCTAssertEqual(day.macroCount, 0)
        XCTAssertEqual(day.timelineEntries, [])
    }
}
