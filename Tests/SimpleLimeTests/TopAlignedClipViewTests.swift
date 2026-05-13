import AppKit
@testable import SimpleLime
import XCTest

@MainActor
final class TopAlignedClipViewTests: XCTestCase {
    func testShortDocumentIsPinnedToTopInsteadOfCenteredVertically() {
        let clipView = TopAlignedClipView(frame: NSRect(x: 0, y: 0, width: 120, height: 200))
        clipView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))

        let constrained = clipView.constrainBoundsRect(NSRect(x: 40, y: 70, width: 120, height: 200))

        XCTAssertEqual(constrained.origin.y, 0)
        XCTAssertEqual(constrained.origin.x, 40)
    }

    func testNarrowDocumentIsPinnedToLeftInsteadOfCenteredHorizontally() {
        let clipView = TopAlignedClipView(frame: NSRect(x: 0, y: 0, width: 220, height: 120))
        clipView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 90, height: 300))

        let constrained = clipView.constrainBoundsRect(NSRect(x: 55, y: 60, width: 220, height: 120))

        XCTAssertEqual(constrained.origin.x, 0)
        XCTAssertEqual(constrained.origin.y, 60)
    }
}
