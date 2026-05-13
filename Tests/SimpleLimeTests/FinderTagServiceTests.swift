import XCTest
@testable import SimpleLime

final class FinderTagServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-finder-tag-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testAddsNormalizesAndClearsFinderTags() throws {
        let url = temporaryDirectory.appendingPathComponent("note.md")
        try "hello".write(to: url, atomically: true, encoding: .utf8)

        try FinderTagService.setTags([" Work ", "work", "Draft"], for: url)
        XCTAssertEqual(FinderTagService.tags(for: url), ["Work", "Draft"])

        try FinderTagService.addTag("Review", to: url)
        XCTAssertEqual(FinderTagService.tags(for: url), ["Work", "Draft", "Review"])

        try FinderTagService.setTags([], for: url)
        XCTAssertEqual(FinderTagService.tags(for: url), [])
    }
}
