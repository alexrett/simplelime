import AppKit
import XCTest
@testable import SimpleLime

@MainActor
final class CodeEditorViewTests: XCTestCase {
    func testLargeBufferLineMetricsAreCachedAcrossSelectionHotPath() {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.text = (0..<25_000)
            .map { "line \($0) value value value" }
            .joined(separator: "\n")

        XCTAssertEqual(textView.lineMetricCacheBuildCount, 0)

        _ = textView.visibleSourceLineRange()
        XCTAssertEqual(textView.lineMetricCacheBuildCount, 1)

        let lineHeight = max(1, ceil(textView.font.ascender - textView.font.descender + textView.font.leading))
        _ = textView.emptyAreaCaretLocation(forDocumentPoint: NSPoint(x: 700, y: lineHeight * 20_000))
        textView.focusModeEnabled = true
        textView.setEditorSelectionRanges([NSRange(location: 150_000, length: 0)])
        XCTAssertTrue(textView.updateFocusModeDimming())

        XCTAssertEqual(textView.lineMetricCacheBuildCount, 1)

        textView.text = "\(textView.text ?? "")\nnew line"
        _ = textView.visibleSourceLineRange()
        XCTAssertEqual(textView.lineMetricCacheBuildCount, 2)
    }

    func testFocusModeDimmingSkipsUnchangedSelectionWork() {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.text = "alpha\n\nbeta"

        XCTAssertFalse(textView.updateFocusModeDimming())

        textView.focusModeEnabled = true
        textView.setEditorSelectionRanges([NSRange(location: 0, length: 0)])
        XCTAssertTrue(textView.updateFocusModeDimming())
        XCTAssertFalse(textView.updateFocusModeDimming())

        let betaLocation = ("alpha\n\nbeta" as NSString).range(of: "beta").location
        textView.setEditorSelectionRanges([NSRange(location: betaLocation, length: 0)])
        XCTAssertTrue(textView.updateFocusModeDimming())
        XCTAssertFalse(textView.updateFocusModeDimming())

        textView.focusModeEnabled = false
        XCTAssertTrue(textView.updateFocusModeDimming())
        XCTAssertFalse(textView.updateFocusModeDimming())
    }

    func testFocusModeDimmingDoesNotOverrideActiveLineSyntaxColors() {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.text = "{\n  \"openapi\": \"3.0.3\"\n}\n\n{\n  \"info\": { \"title\": \"WMS\" }\n}"

        SyntaxHighlighter.apply(to: textView, language: .json, fontSize: 14)

        let nsText = (textView.text ?? "") as NSString
        let openAPIRange = nsText.range(of: "\"openapi\"")
        let infoRange = nsText.range(of: "\"info\"")
        XCTAssertEqual(textStorageForegroundColor(at: openAPIRange.location, in: textView), .systemRed)
        XCTAssertEqual(textStorageForegroundColor(at: infoRange.location, in: textView), .systemRed)

        textView.focusModeEnabled = true
        textView.setEditorSelectionRanges([NSRange(location: openAPIRange.location, length: 0)])

        XCTAssertTrue(textView.updateFocusModeDimming())
        XCTAssertEqual(textStorageForegroundColor(at: openAPIRange.location, in: textView), .systemRed)
        XCTAssertEqual(textStorageForegroundColor(at: infoRange.location, in: textView), .systemRed)
        XCTAssertNil(renderingForegroundColor(at: openAPIRange.location, in: textView))
        XCTAssertNotNil(renderingForegroundColor(at: infoRange.location, in: textView))
    }

    func testEmptyAreaClickFallbackPlacesCaretAtNearestLineEnd() {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.text = "alpha\nbeta"

        let lineHeight = max(1, ceil(textView.font.ascender - textView.font.descender + textView.font.leading))

        XCTAssertEqual(
            textView.emptyAreaCaretLocation(forDocumentPoint: NSPoint(x: 700, y: lineHeight * 0.5)),
            5
        )
        XCTAssertEqual(
            textView.emptyAreaCaretLocation(forDocumentPoint: NSPoint(x: 700, y: lineHeight * 1.5)),
            10
        )
        XCTAssertEqual(
            textView.emptyAreaCaretLocation(forDocumentPoint: NSPoint(x: 700, y: lineHeight * 20)),
            10
        )
    }

    private func textStorageForegroundColor(at location: Int, in textView: EditorTextView) -> NSColor? {
        guard let storage = (textView.textContentManager as? NSTextContentStorage)?.textStorage,
              location < storage.length else {
            return nil
        }

        return storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    private func renderingForegroundColor(at location: Int, in textView: EditorTextView) -> NSColor? {
        guard let textLocation = textView.textContentManager.location(
            textView.textContentManager.documentRange.location,
            offsetBy: location
        ) else {
            return nil
        }

        var color: NSColor?
        textView.textLayoutManager.enumerateRenderingAttributes(
            from: textLocation,
            reverse: false
        ) { _, attributes, range in
            let nsRange = NSRange(range, in: textView.textContentManager)
            guard nsRange.location <= location,
                  location < nsRange.location + nsRange.length else {
                return color == nil
            }

            color = attributes[.foregroundColor] as? NSColor
            return false
        }

        return color
    }
}
