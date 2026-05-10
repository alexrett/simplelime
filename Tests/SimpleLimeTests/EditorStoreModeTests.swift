import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreModeTests: XCTestCase {
    func testWysiwygModeDisablesSourceOnlySurfaces() {
        let store = makeStore()
        store.isPreviewVisible = true
        store.isMiniMapVisible = true
        store.isFocusModeEnabled = true
        store.isWysiwygModeEnabled = false

        store.toggleWysiwygMode()

        XCTAssertTrue(store.isWysiwygModeEnabled)
        XCTAssertFalse(store.isPreviewVisible)
        XCTAssertFalse(store.isMiniMapVisible)
        XCTAssertFalse(store.isFocusModeEnabled)
    }

    func testMinimapSwitchesBackToSourceModeFromWysiwyg() {
        let store = makeStore()
        store.isPreviewVisible = false
        store.isMiniMapVisible = false
        store.isWysiwygModeEnabled = true

        store.toggleMiniMap()

        XCTAssertFalse(store.isWysiwygModeEnabled)
        XCTAssertTrue(store.isMiniMapVisible)
    }

    func testPreviewSwitchesBackToSourceModeFromWysiwyg() {
        let store = makeStore()
        store.isPreviewVisible = false
        store.isMiniMapVisible = false
        store.isWysiwygModeEnabled = true

        store.toggleMarkdownPreview()

        XCTAssertFalse(store.isWysiwygModeEnabled)
        XCTAssertTrue(store.isPreviewVisible)
    }

    func testExplicitModeSelectionIsMutuallyExclusiveForRenderedModes() {
        let store = makeStore()
        store.isPreviewVisible = false
        store.isMiniMapVisible = true
        store.isFocusModeEnabled = true
        store.isWysiwygModeEnabled = false

        store.showMarkdownPreviewMode()

        XCTAssertTrue(store.isPreviewVisible)
        XCTAssertFalse(store.isWysiwygModeEnabled)
        XCTAssertTrue(store.isMiniMapVisible)
        XCTAssertTrue(store.isFocusModeEnabled)

        store.showMarkdownWysiwygMode()

        XCTAssertFalse(store.isPreviewVisible)
        XCTAssertTrue(store.isWysiwygModeEnabled)
        XCTAssertFalse(store.isMiniMapVisible)
        XCTAssertFalse(store.isFocusModeEnabled)

        store.showSourceMode()

        XCTAssertFalse(store.isPreviewVisible)
        XCTAssertFalse(store.isWysiwygModeEnabled)
        XCTAssertFalse(store.isMiniMapVisible)
        XCTAssertFalse(store.isFocusModeEnabled)
    }

    func testFocusSwitchesBackToSourceModeFromWysiwyg() {
        let store = makeStore()
        store.isFocusModeEnabled = false
        store.isMiniMapVisible = false
        store.isWysiwygModeEnabled = true

        store.toggleFocusMode()

        XCTAssertFalse(store.isWysiwygModeEnabled)
        XCTAssertTrue(store.isFocusModeEnabled)
    }

    func testExplicitSourceModeClearsRenderedModesWithoutChangingMinimap() {
        let store = makeStore()
        store.isPreviewVisible = true
        store.isMiniMapVisible = true
        store.isWysiwygModeEnabled = true

        store.showSourceMode()

        XCTAssertFalse(store.isWysiwygModeEnabled)
        XCTAssertFalse(store.isPreviewVisible)
        XCTAssertTrue(store.isMiniMapVisible)
    }

    func testLoadedWysiwygModeClearsPersistedMinimapConflict() {
        let defaults = UserDefaults.standard
        let previousWysiwyg = defaults.object(forKey: "editor.markdownWysiwyg")
        let previousMiniMap = defaults.object(forKey: "editor.miniMap")
        let previousFocus = defaults.object(forKey: "editor.focusMode")
        defer {
            restore(previousWysiwyg, forKey: "editor.markdownWysiwyg")
            restore(previousMiniMap, forKey: "editor.miniMap")
            restore(previousFocus, forKey: "editor.focusMode")
        }

        defaults.set(true, forKey: "editor.markdownWysiwyg")
        defaults.set(true, forKey: "editor.miniMap")
        defaults.set(true, forKey: "editor.focusMode")

        let store = makeStore()

        XCTAssertTrue(store.isWysiwygModeEnabled)
        XCTAssertFalse(store.isMiniMapVisible)
        XCTAssertFalse(store.isFocusModeEnabled)
        XCTAssertEqual(defaults.object(forKey: "editor.miniMap") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "editor.focusMode") as? Bool, false)
    }

    private func makeStore() -> EditorStore {
        EditorStore(
            initialBuffers: [EditorBuffer.scratch(index: 1)],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
