import AppKit
import XCTest
@testable import SimpleLime

final class ImageFileInspectionTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-image-inspection-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testInspectsImagePixelMetadataWithoutOpeningAsText() throws {
        let url = temporaryDirectory.appendingPathComponent("inspect.png")
        try makePNG(width: 3, height: 2).write(to: url)

        let inspection = try XCTUnwrap(ImageFileInspection.inspect(url: url))

        XCTAssertEqual(inspection.pixelWidth, 3)
        XCTAssertEqual(inspection.pixelHeight, 2)
        XCTAssertEqual(inspection.pixelSizeText, "3 x 2 px")
        XCTAssertGreaterThan(inspection.fileSizeBytes ?? 0, 0)
        XCTAssertTrue(inspection.fileSizeText?.isEmpty == false)
        XCTAssertTrue(inspection.typeDescription?.contains("png") == true || inspection.typeDescription?.contains("PNG") == true)
        XCTAssertTrue(inspection.colorSummaryText.contains("RGB") || inspection.colorSummaryText.contains("Color"))
    }

    func testInvalidImageReturnsNilInspection() throws {
        let url = temporaryDirectory.appendingPathComponent("not-image.png")
        try Data("not an image".utf8).write(to: url)

        XCTAssertNil(ImageFileInspection.inspect(url: url))
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "ImageFileInspectionTests", code: 1)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ImageFileInspectionTests", code: 2)
        }

        return data
    }
}
