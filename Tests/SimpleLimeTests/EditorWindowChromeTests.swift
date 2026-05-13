import AppKit
@testable import SimpleLime
import XCTest

@MainActor
final class EditorWindowChromeTests: XCTestCase {
    func testConfigureRemovesSystemTitleChromeForCustomTabBar() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SimpleLime - Workspace"
        window.toolbar = NSToolbar(identifier: "test-toolbar")
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.tabbingMode = .automatic
        window.isMovableByWindowBackground = true

        EditorWindowChrome.configure(window)

        XCTAssertEqual(window.title, "")
        XCTAssertEqual(window.accessibilityLabel(), "SimpleLime - Workspace")
        XCTAssertEqual(window.identifier, EditorWindowChrome.editorWindowIdentifier)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.tabbingMode, .disallowed)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertNotNil(window.toolbar)
        assertStandardWindowButtonsVisible(in: window)
    }

    func testDetectsEditorWindowsAfterVisibleTitleIsCleared() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SimpleLime - Workspace"

        XCTAssertTrue(EditorWindowChrome.isEditorWindow(window))

        EditorWindowChrome.configure(window)

        XCTAssertTrue(EditorWindowChrome.isEditorWindow(window))
    }

    func testConfigureRecoversWhenSwiftUIReappliesVisibleWorkspaceTitle() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        EditorWindowChrome.configure(window, logicalTitle: "SimpleLime - Workspace")

        window.title = "SimpleLime - Workspace"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbar = NSToolbar(identifier: "reapplied-toolbar")

        XCTAssertTrue(EditorWindowChrome.isEditorWindow(window))

        EditorWindowChrome.configure(window)

        XCTAssertEqual(window.title, "")
        XCTAssertEqual(window.accessibilityLabel(), "SimpleLime - Workspace")
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertNotNil(window.toolbar)
        assertStandardWindowButtonsVisible(in: window)
    }

    func testConfigureRestoresTrafficLightButtonsWhenTitleChromeIsHidden() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SimpleLime - Workspace"
        [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ].forEach { buttonType in
            let button = window.standardWindowButton(buttonType)
            button?.isHidden = true
            button?.alphaValue = 0
        }

        EditorWindowChrome.configure(window)

        assertStandardWindowButtonsVisible(in: window)
    }

    func testConfigureKeepsTrafficLightButtonsAboveFullSizeContent() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SimpleLime - Workspace"

        EditorWindowChrome.configure(window)

        [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ].forEach { buttonType in
            let button = window.standardWindowButton(buttonType)
            XCTAssertTrue(button?.superview?.wantsLayer ?? false, "\(buttonType) container should be layer-backed")
            XCTAssertGreaterThanOrEqual(
                button?.superview?.layer?.zPosition ?? 0,
                EditorWindowChrome.trafficLightLayerZPosition,
                "\(buttonType) container should stay above the custom full-size content"
            )
            XCTAssertTrue(button?.wantsLayer ?? false, "\(buttonType) should be layer-backed")
            XCTAssertGreaterThan(
                button?.layer?.zPosition ?? 0,
                EditorWindowChrome.trafficLightLayerZPosition,
                "\(buttonType) should stay above the custom full-size content"
            )
        }
    }

    func testTabBarTrafficLightInsetStaysWithinAReasonableTitlebarRange() {
        XCTAssertEqual(
            TabBarControl.clampedTrafficLightInset(forButtonMaxX: 48),
            TabBarControl.minimumTrafficLightInset
        )
        XCTAssertEqual(
            TabBarControl.clampedTrafficLightInset(forButtonMaxX: 108),
            124
        )
        XCTAssertEqual(
            TabBarControl.clampedTrafficLightInset(forButtonMaxX: 240),
            TabBarControl.maximumTrafficLightInset
        )
    }

    func testTabBarKeepsTrafficLightAreaTransparentAndClickable() {
        let passthroughRect = TabBarControl.trafficLightPassthroughRect(
            forButtonFrames: [
                NSRect(x: 12, y: 13, width: 12, height: 12),
                NSRect(x: 34, y: 13, width: 12, height: 12),
                NSRect(x: 56, y: 13, width: 12, height: 12)
            ],
            bounds: NSRect(x: 0, y: 0, width: 220, height: 38),
            padding: 6
        )

        XCTAssertEqual(passthroughRect, NSRect(x: 6, y: 7, width: 68, height: 24))
    }

    func testTabBarTrafficLightPassthroughIsClippedToTheTabBarBounds() {
        let passthroughRect = TabBarControl.trafficLightPassthroughRect(
            forButtonFrames: [
                NSRect(x: 4, y: 4, width: 12, height: 12),
                NSRect(x: 28, y: 4, width: 12, height: 12)
            ],
            bounds: NSRect(x: 0, y: 0, width: 44, height: 18),
            padding: 8
        )

        XCTAssertEqual(passthroughRect, NSRect(x: 0, y: 0, width: 44, height: 18))
    }

    func testDoesNotClassifyUtilityWindowsAsEditorWindows() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"

        XCTAssertFalse(EditorWindowChrome.isEditorWindow(window))
    }

    private func assertStandardWindowButtonsVisible(in window: NSWindow, file: StaticString = #filePath, line: UInt = #line) {
        [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ].forEach { buttonType in
            guard let button = window.standardWindowButton(buttonType) else {
                XCTFail("Missing \(buttonType)", file: file, line: line)
                return
            }
            XCTAssertFalse(button.isHidden, "\(buttonType) should be visible", file: file, line: line)
            XCTAssertEqual(button.alphaValue, 1, "\(buttonType) should be opaque", file: file, line: line)
            XCTAssertFalse(button.superview?.isHidden ?? false, "\(buttonType) container should be visible", file: file, line: line)
            XCTAssertEqual(button.superview?.alphaValue ?? 1, 1, "\(buttonType) container should be opaque", file: file, line: line)
        }
    }
}
