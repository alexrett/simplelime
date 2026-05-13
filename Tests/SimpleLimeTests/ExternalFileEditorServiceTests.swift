import XCTest
@testable import SimpleLime

final class ExternalFileEditorServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-external-editor-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testApplicationURLFindsAppBundleInSearchRoots() throws {
        let applications = temporaryDirectory.appendingPathComponent("Applications", isDirectory: true)
        let simpleShot = applications.appendingPathComponent("SimpleShot.app", isDirectory: true)
        try FileManager.default.createDirectory(at: simpleShot, withIntermediateDirectories: true)

        XCTAssertEqual(
            ExternalFileEditorService.applicationURL(
                named: "SimpleShot",
                searchRoots: [applications]
            )?.standardizedFileURL,
            simpleShot.standardizedFileURL
        )
    }

    func testApplicationURLIgnoresPlainFilesNamedLikeApps() throws {
        let applications = temporaryDirectory.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try Data().write(to: applications.appendingPathComponent("SimpleShot.app", isDirectory: false))

        XCTAssertNil(
            ExternalFileEditorService.applicationURL(
                named: "SimpleShot.app",
                searchRoots: [applications]
            )
        )
    }

    func testDefaultApplicationSearchRootsAreDeduplicated() {
        let roots = ExternalFileEditorService.defaultApplicationSearchRoots(
            homeDirectory: URL(fileURLWithPath: "/Users/example", isDirectory: true)
        )

        XCTAssertEqual(Set(roots.map(\.standardizedFileURL.path)).count, roots.count)
        XCTAssertTrue(roots.contains(URL(fileURLWithPath: "/Applications", isDirectory: true)))
    }
}
