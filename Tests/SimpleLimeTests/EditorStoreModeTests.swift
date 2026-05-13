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

        store.toggleRenderedPreview()

        XCTAssertFalse(store.isWysiwygModeEnabled)
        XCTAssertTrue(store.isPreviewVisible)
    }

    func testDelimitedTablePreviewUsesRenderedPreviewMode() {
        let store = makeStore()
        store.isPreviewVisible = false
        store.isWysiwygModeEnabled = true

        store.showDelimitedTablePreviewMode()

        XCTAssertTrue(store.isPreviewVisible)
        XCTAssertFalse(store.isWysiwygModeEnabled)
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

    func testEditorDiagnosticsScratchReportsNormalSourceEditorPath() throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "config.json"
        buffer.kind = .file
        buffer.filePath = "/tmp/config.json"
        buffer.language = .json
        buffer.text = #"{"enabled":true}"# + "\n"
        buffer.selectionRanges = [TextRange(location: 0, length: 3)]
        let store = makeStore(buffer: buffer)
        store.isMiniMapVisible = true
        store.wrapsLines = false

        store.createEditorDiagnosticsScratch(now: Date(timeIntervalSince1970: 1_700_000_000))

        let diagnostics = try XCTUnwrap(store.selectedBuffer)
        XCTAssertTrue(diagnostics.title.hasPrefix("Editor Diagnostics "))
        XCTAssertEqual(diagnostics.language, .markdown)
        XCTAssertTrue(diagnostics.isDirty)
        XCTAssertTrue(diagnostics.text.contains("- Title: config.json"))
        XCTAssertTrue(diagnostics.text.contains("- Language: JSON"))
        XCTAssertTrue(diagnostics.text.contains("- Active editor path: STTextView source editor"))
        XCTAssertTrue(diagnostics.text.contains("- Syntax highlighting: Debounced"))
        XCTAssertTrue(diagnostics.text.contains("- Selection ranges: 1"))
        XCTAssertTrue(diagnostics.text.contains("- Minimap: Yes"))
        XCTAssertTrue(diagnostics.text.contains("- Word wrap: No"))
        XCTAssertTrue(diagnostics.text.contains("## Large-File Editing Capability"))
        XCTAssertTrue(diagnostics.text.contains("- Status: Normal editable buffer"))
        XCTAssertTrue(diagnostics.text.contains("- Can edit loaded text: Yes"))
        XCTAssertTrue(diagnostics.text.contains("- Can save chunk back: No"))
        XCTAssertTrue(diagnostics.text.contains("## Editor Core Compatibility"))
        XCTAssertTrue(diagnostics.text.contains("| Source text editing | Yes | Provided by Native STTextView. |"))
        XCTAssertTrue(diagnostics.text.contains("| Column selection | Yes | Column selections are routed through the active source engine. |"))
        XCTAssertTrue(diagnostics.text.contains("| Macros/templates | Yes | Macros and templates apply through source text commands. |"))
        XCTAssertTrue(diagnostics.text.contains("| Large-file search/jump | N/A | Normal buffers use regular find and direct line navigation. |"))
        XCTAssertTrue(diagnostics.text.contains("| Large-file full editing | No | The active source engine does not expose full-file virtual editing; large files use read-only virtual browsing plus chunks. |"))
        XCTAssertTrue(diagnostics.text.contains("## Editor Core Acceptance Gates"))
        XCTAssertTrue(diagnostics.text.contains("| Typing latency under 32 ms p95 | Manual | Headless tests cover model/index/highlight work, and the live smoke script can collect p95 key/text/selection telemetry from a built app. | Run script/editor_live_latency_smoke.sh and inspect EditorPerformance p95 metrics. |"))
        XCTAssertTrue(diagnostics.text.contains("| Full-file virtual editing | Manual | This buffer does not exercise the large-file editable model requirement. | Evaluate this gate with a large JSON/text fixture. |"))
    }

    func testEditorDiagnosticsScratchReportsLargeFileRestrictions() throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "openapi.json"
        buffer.kind = .file
        buffer.filePath = "/tmp/openapi.json"
        buffer.language = .json
        buffer.text = #"{"openapi":"3.0.0"}"#
        buffer.savePolicy = .readOnly
        buffer.isLargeFileMode = true
        buffer.fileSizeBytes = 1_048_576
        buffer.largeFilePreviewStartOffsetBytes = 16_384
        buffer.largeFilePreviewByteCount = 16_384
        buffer.largeFileSourcePath = "/tmp/openapi.json"
        buffer.largeFileSourceStartOffsetBytes = 16_384
        buffer.largeFileSourceByteCount = 16_384
        buffer.largeFileSourceFileSizeBytes = 1_048_576
        let store = makeStore(buffer: buffer)

        store.createEditorDiagnosticsScratch(now: Date(timeIntervalSince1970: 1_700_000_000))

        let diagnostics = try XCTUnwrap(store.selectedBuffer)
        XCTAssertTrue(diagnostics.text.contains("- Large-file mode: Yes"))
        XCTAssertTrue(diagnostics.text.contains("- Active editor path: Large-file editable chunk"))
        XCTAssertTrue(diagnostics.text.contains("- Chunk can be saved back: Yes"))
        XCTAssertTrue(diagnostics.text.contains("## Large-File Editing Capability"))
        XCTAssertTrue(diagnostics.text.contains("- Status: Editable preview chunk"))
        XCTAssertTrue(diagnostics.text.contains("- Can edit loaded text: Yes"))
        XCTAssertTrue(diagnostics.text.contains("- Can enable in-place chunk editing: No"))
        XCTAssertTrue(diagnostics.text.contains("- Can save chunk back: Yes"))
        XCTAssertTrue(diagnostics.text.contains("- Full-file editable model: Not available"))
        XCTAssertTrue(diagnostics.text.contains("- Source path: /tmp/openapi.json"))
        XCTAssertTrue(diagnostics.text.contains("## Editor Core Compatibility"))
        XCTAssertTrue(diagnostics.text.contains("| Source text editing | Chunk-only | The virtual full-file preview is read-only; edit exact chunks or extract a scratch. |"))
        XCTAssertTrue(diagnostics.text.contains("| Column selection | Chunk-only | Use an editable chunk for column selections. |"))
        XCTAssertTrue(diagnostics.text.contains("| Find/replace bridge | Line replace | Full-file exact search, line jumps, and single-line virtual replacement are available; broad replace still requires editable chunks. |"))
        XCTAssertTrue(diagnostics.text.contains("| Large-file search/jump | Yes | Full-file exact search and line jumps load matching virtual chunks. |"))
        XCTAssertTrue(diagnostics.text.contains("| Large-file full editing | No | Requires a replacement editor core with a true virtual editable document model. |"))
        XCTAssertTrue(diagnostics.text.contains("## Editor Core Acceptance Gates"))
        XCTAssertTrue(diagnostics.text.contains("| Open large files without UI blocking | Pass | Large-file mode keeps the loaded buffer bounded and defers full-file work to virtual indexes. | Verify visible pause in the real app with telemetry when GUI testing is allowed. |"))
        XCTAssertTrue(diagnostics.text.contains("| Feature contract preservation | Warning | Large-file preview preserves navigation/search/chunk editing and a single-line virtual replace primitive, but comments and collaboration selections remain chunk-only. | Use the compatibility matrix to choose which integrations a replacement core must support. |"))
        XCTAssertTrue(diagnostics.text.contains("| Full-file virtual editing | Fail | The current implementation does not provide a true editable full-file virtual document model. | Prototype CodeMirror or Scintilla behind SourceEditorView, or build a custom virtual editor only if those fail. |"))
    }

    private func makeStore(buffer: EditorBuffer = EditorBuffer.scratch(index: 1)) -> EditorStore {
        EditorStore(
            initialBuffers: [buffer],
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
