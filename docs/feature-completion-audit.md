# SimpleLime Feature Completion Audit

This audit maps the requested gap list to concrete implementation evidence.
It is intentionally stricter than the roadmap: a feature can have a useful
first slice while still being marked partial if the original request implied a
larger production surface.

Verification baseline from 2026-05-13:

- `swift test --disable-sandbox` passed: 640 tests, 1 skipped, 0 failures.
- After the editor hot-path stabilization change, the focused suite passed:
  `EditorStoreLargeFileTests`, `LargeFileVirtualTextDocumentTests`, and
  `SyntaxHighlighterTests`; after the external file-open window fix,
  `WorkspaceStoreTests` was added to the same focused run for 63 tests,
  0 failures. A follow-up editor click fallback check passed
  `CodeEditorViewTests` plus `SyntaxHighlighterTests` for 5 tests, 0 failures.
  Fold-gutter hot-path stabilization passed `CodeEditorViewTests`,
  `StructuredTextFolderTests`, `EditorStoreFoldingTests`, and
  `SyntaxHighlighterTests` for 14 tests, 0 failures. The focus-dimming and
  line-range cache follow-up passed `CodeEditorViewTests`,
  `StructuredTextFolderTests`, `EditorStoreFoldingTests`,
  `EditorStoreLargeFileTests`, `LargeFileVirtualTextDocumentTests`, and
  `SyntaxHighlighterTests` for 65 tests, 0 failures. A large-buffer
  line-metrics regression passed `CodeEditorViewTests`, `EditorStoreLargeFileTests`,
  `LargeFileVirtualTextDocumentTests`, and `SyntaxHighlighterTests` for 57 tests,
  0 failures. The editor diagnostics follow-up passed `EditorStoreModeTests` and
  `EditorLanguageTests` for 14 tests, 0 failures. The performance telemetry
  follow-up passed `CodeEditorViewTests`, `EditorStoreModeTests`, and
  `EditorPerformanceTelemetryTests` for 15 tests, 0 failures. The editor core
  compatibility diagnostics follow-up passed `SourceEditorAdapterTests` plus
  the focused normal/large-file editor diagnostics checks for 5 tests, 0
  failures; the editor-core acceptance-gate follow-up passed
  `SourceEditorAdapterTests` plus the focused normal/large-file editor
  diagnostics checks for 7 tests, 0 failures. The large-file edit capability
  follow-up passed `EditorStoreLargeFileTests` and `EditorStoreModeTests` for
  57 tests, 0 failures. `./script/editor_core_benchmark.sh
  --skip-build` then generated the large editor fixtures and reran the 30
  focused editor/large-file/telemetry/acceptance-gate smoke tests with 0
  failures. The non-GUI editor core performance probe now
  covers 25k-line virtual text indexing/visible-line reads, 16k-row/27-column
  virtual CSV indexing/visible-row reads, and 240 visible JSON line highlights
  with loose debug-build regression budgets; the latest full-suite run measured
  42.34 ms for 25k-line text indexing, 4.79 ms for visible line reads, 388.93
  ms for 16k/27-column CSV indexing, 3.19 ms for visible row reads, and 67.56
  ms for 240 visible JSON line highlights. The visible-range scratch extraction
  follow-up passed `EditorStoreLargeFileTests` for 51 tests, 0 failures. The Companion ScreenCaptureKit active-window OCR
  context follow-up passed `CompanionSettingsTests` plus the full
  `EditorStoreCompanionTests` suite for 21 tests, 0 failures. The browser
  meeting-window, browser-URL, and partial combined-capture failure scribe
  follow-up passed `VoiceScribeTests` for 16 tests, 0 failures; the large-file
  voice-command follow-up passed `VoiceScribeTests` for 17 tests, 0 failures.
  The Auto Meeting Scribe follow-up passed `VoiceScribeTests` plus
  `SettingsSearchCatalogTests` for 25 tests, 0 failures; the all-running-browser
  tab URL scan follow-up passed `VoiceScribeTests` for 22 tests, 0 failures. The searchable
  Settings follow-up passed
  `SettingsSearchCatalogTests` for 4 tests, 0 failures. The large-file
  click-to-edit follow-up passed `EditorStoreLargeFileTests` for 48 tests and
  `LargeFileVirtualTextDocumentTests` for 7 tests, both with 0 failures. The
  visible-line chunk edit follow-up passed the targeted
  `EditorStoreLargeFileTests` line-activation and visible-range edit cases. The
  virtual line replacement follow-up passed `LargeFileVirtualTextDocumentTests`
  plus the targeted `EditorStoreLargeFileTests` source/visible-chunk replacement
  case for 10 tests, 0 failures. The menu/palette line replacement follow-up
  passed the large-file virtual text/store/diagnostics focused run for 12 tests,
  0 failures. The automation/RPC/socket large-file line edit follow-up added
  streamed insert/delete alongside replacement and passed
  `LargeFileVirtualTextDocumentTests`, `LocalAutomationBridgeTests`, and
  `EditorStoreLocalAutomationTests` for 54 tests, 0 failures. The
  real Vim terminal TUI smoke follow-up now waits for the actual alternate-screen
  exit sequence before sending same-PTY shell follow-up input, passed 8 repeated
  runs of the focused Vim test, and passed `EditorStoreTerminalTests` for 38
  tests, 0 failures. The real Codex/Claude terminal recovery follow-up passed
  `EditorStoreTerminalTests` for 38 tests, 0 failures. The real Python curses
  terminal TUI follow-up passed its focused test, then passed
  `EditorStoreTerminalTests` for 39 tests, 0 failures. The window-chrome
  traffic-light regression follow-up passed `EditorWindowChromeTests` for 9
  tests, 0 failures. The top-aligned sidebar/table follow-up passed
  `TopAlignedClipViewTests`, `DelimitedTextTableTests`, and
  `DelimitedVirtualTableDocumentTests` for 23 tests, 0 failures. The virtual
  large-file row action follow-up passed `LargeFileVirtualTextDocumentTests`
  for 15 tests and `EditorStoreLargeFileTests` for 51 tests, both with 0
  failures, and same-size line rewrites invalidate the virtual renderer index
  and attributed-line cache through the buffer revision token. The virtual
  range/block edit follow-up passed `LargeFileVirtualTextDocumentTests` for 19
  tests, `LocalAutomationBridgeTests` for 29 tests,
  `EditorStoreLargeFileTests` for 52 tests, and
  `EditorStoreLocalAutomationTests` for 17 tests, all with 0 failures; the full
  suite then passed 617 tests, 0 failures. The inline large-file row edit
  follow-up passed `LargeFileVirtualTextDocumentTests` for 20 tests,
  `EditorStoreLargeFileTests` for 52 tests, and the full suite for 618 tests,
  all with 0 failures; the full-suite headless probes measured 11.33 ms for
  25k-line text indexing, 0.40 ms for visible line reads, 111.47 ms for
  16k/27-column CSV indexing, 1.22 ms for visible row reads, and 18.25 ms for
  240 visible JSON line highlights. The virtual large-file keyboard row control
  follow-up passed `LargeFileVirtualTextDocumentTests` for 21 tests, then the
  full suite passed 619 tests, all with 0 failures; the full-suite headless
  probes measured 11.34 ms for 25k-line text indexing, 0.38 ms for visible
  line reads, 110.67 ms for 16k/27-column CSV indexing, 1.52 ms for visible
  row reads, and 18.08 ms for 240 visible JSON line highlights. The
  click-positioned inline caret follow-up passed
  `LargeFileVirtualTextDocumentTests` for 22 tests, then the full suite
  passed 620 tests, all with 0 failures; the full-suite headless probes
  measured 11.18 ms for 25k-line text indexing, 0.37 ms for visible line reads,
  112.60 ms for 16k/27-column CSV indexing, 1.16 ms for visible row reads, and
  18.63 ms for 240 visible JSON line highlights. The inline large-file edit
  shortcut follow-up passed `LargeFileVirtualTextDocumentTests` for 23 tests,
  then the full suite passed 621 tests, all with 0 failures; the full-suite
  headless probes measured 11.43 ms for 25k-line text indexing, 0.40 ms for
  visible line reads, 110.28 ms for 16k/27-column CSV indexing, 1.36 ms for
  visible row reads, and 17.99 ms for 240 visible JSON line highlights. The
  real Python curses terminal TUI follow-up then passed
  `EditorStoreTerminalTests` for 39 tests and the full suite for 622 tests, all
  with 0 failures; the full-suite headless probes measured 11.12 ms for
  25k-line text indexing, 0.40 ms for visible line reads, 113.06 ms for
  16k/27-column CSV indexing, 1.21 ms for visible row reads, and 17.63 ms for
  240 visible JSON line highlights. The conditional real `htop` terminal TUI
  follow-up added a skipped-when-missing smoke for the exact `htop` class of
  full-screen app; on this machine the focused `htop` test skipped because
  `htop` is not installed, `EditorStoreTerminalTests` passed 40 tests with 1
  skipped and 0 failures, and the full suite passed 623 tests with 1 skipped
  and 0 failures; the full-suite headless probes measured 11.61 ms for
  25k-line text indexing, 0.44 ms for visible line reads, 112.98 ms for
  16k/27-column CSV indexing, 1.18 ms for visible row reads, and 18.24 ms for
  240 visible JSON line highlights. The external app-data sync follow-up then
  passed `WorkspaceStoreTests` for 16 tests, 0 failures, and the full suite for
  626 tests with 1 skipped and 0 failures; the full-suite headless probes
  measured 11.11 ms for 25k-line text indexing, 0.37 ms for visible line reads,
  111.51 ms for 16k/27-column CSV indexing, 1.20 ms for visible row reads, and
  18.15 ms for 240 visible JSON line highlights.
  The source-engine prototype follow-up passed `SourceEditorAdapterTests` for
  7 tests, `SettingsSearchCatalogTests` for 4 tests, and
  `EditorStoreModeTests` for 10 tests, all with 0 failures; the full suite then
  passed 628 tests with 1 skipped and 0 failures, and the full-suite headless
  probes measured 11.43 ms for 25k-line text indexing, 0.46 ms for visible line
  reads, 111.21 ms for 16k/27-column CSV indexing, 1.17 ms for visible row
  reads, and 18.32 ms for 240 visible JSON line highlights.
  The source command fallback follow-up passed `EditorStoreTextMacroTests` for
  22 tests, `SourceEditorAdapterTests` for 7 tests, and `EditorStoreModeTests`
  for 10 tests, all with 0 failures; the full suite then passed 631 tests with
  1 skipped and 0 failures, and the full-suite headless probes measured 11.62
  ms for 25k-line text indexing, 0.46 ms for visible line reads, 111.32 ms for
  16k/27-column CSV indexing, 1.33 ms for visible row reads, and 18.22 ms for
  240 visible JSON line highlights.
  The source decoration bridge follow-up passed `SourceEditorAdapterTests` for
  8 tests, the focused normal source diagnostics check, and the full suite for
  632 tests with 1 skipped and 0 failures; the full-suite headless probes
  measured 11.17 ms for 25k-line text indexing, 0.44 ms for visible line reads,
  112.04 ms for 16k/27-column CSV indexing, 1.26 ms for visible row reads, and
  18.03 ms for 240 visible JSON line highlights.
  The CodeMirror multiple-selection bridge follow-up passed
  `SourceEditorAdapterTests` for 9 tests, `EditorStoreTextMacroTests` for 22
  tests, embedded-JS syntax validation, and the full suite for 633 tests with
  1 skipped and 0 failures; the full-suite headless probes measured 11.69 ms
  for 25k-line text indexing, 0.46 ms for visible line reads, 112.12 ms for
  16k/27-column CSV indexing, 1.20 ms for visible row reads, and 17.82 ms for
  240 visible JSON line highlights.
  The raw multi-cursor macro capture follow-up passed
  `EditorStoreTextMacroTests` for 24 tests and the full suite for 635 tests
  with 1 skipped and 0 failures; the full-suite headless probes measured 11.39
  ms for 25k-line text indexing, 0.41 ms for visible line reads, 111.02 ms for
  16k/27-column CSV indexing, 1.20 ms for visible row reads, and 17.94 ms for
  240 visible JSON line highlights.
  The CodeMirror host-selection scroll bridge follow-up passed
  `SourceEditorAdapterTests` for 10 tests, embedded-JS syntax validation, and
  the full suite for 636 tests with 1 skipped and 0 failures; the full-suite
  headless probes measured 11.20 ms for 25k-line text indexing, 0.44 ms for
  visible line reads, 111.24 ms for 16k/27-column CSV indexing, 1.21 ms for
  visible row reads, and 17.64 ms for 240 visible JSON line highlights.
  The CodeMirror column-guide bridge follow-up passed
  `SourceEditorAdapterTests` for 11 tests, embedded-JS syntax validation, and
  the full suite for 637 tests with 1 skipped and 0 failures; the full-suite
  headless probes measured 42.34 ms for 25k-line text indexing, 4.79 ms for
  visible line reads, 388.93 ms for 16k/27-column CSV indexing, 3.19 ms for
  visible row reads, and 67.56 ms for 240 visible JSON line highlights.
  The CodeMirror focus/typewriter mode bridge follow-up passed
  `SourceEditorAdapterTests` for 12 tests, embedded-JS syntax validation, and
  the full suite for 638 tests with 1 skipped and 0 failures; the full-suite
  headless probes measured 17.42 ms for 25k-line text indexing, 0.66 ms for
  visible line reads, 173.08 ms for 16k/27-column CSV indexing, 1.83 ms for
  visible row reads, and 27.75 ms for 240 visible JSON line highlights.
  The CodeMirror folded-range display bridge follow-up passed
  `SourceEditorAdapterTests` for 13 tests, embedded-JS syntax validation, and
  the full suite for 639 tests with 1 skipped and 0 failures; the full-suite
  headless probes measured 36.82 ms for 25k-line text indexing, 1.78 ms for
  visible line reads, 368.51 ms for 16k/27-column CSV indexing, 3.46 ms for
  visible row reads, and 60.51 ms for 240 visible JSON line highlights.
  The CodeMirror direct selection/line movement/comment command and read-only guard follow-up passed
  `SourceEditorAdapterTests` for 14 tests, embedded-JS syntax validation, and
  the full suite for 640 tests with 1 skipped and 0 failures; the full-suite
  headless probes measured 37.31 ms for 25k-line text indexing, 1.52 ms for
  visible line reads, 359.77 ms for 16k/27-column CSV indexing, 3.97 ms for
  visible row reads, and 60.70 ms for 240 visible JSON line highlights.
  The CodeMirror direct text-transform follow-up passed
  `SourceEditorAdapterTests` for 14 tests, embedded-JS syntax validation, and
  the full suite for 640 tests with 1 skipped and 0 failures; the full-suite
  headless probes measured 44.95 ms for 25k-line text indexing, 1.58 ms for
  visible line reads, 379.17 ms for 16k/27-column CSV indexing, 4.06 ms for
  visible row reads, and 70.57 ms for 240 visible JSON line highlights. JSON
  minify/format and Markdown table formatting intentionally remain on the
  Swift fallback path.
  The Activity
  Watch privacy split passed
  `EditorStoreUsageStatsTests`, `EditorStoreCompanionTests`, and
  `SettingsSearchCatalogTests` for 35 tests, 0 failures.
- `script/editor_live_latency_smoke.sh` now provides the live GUI telemetry
  gate without screenshots: it launches the built app in safe mode, streams
  `EditorPerformance` metrics, uses local automation for an insert smoke, and
  optionally drives AppKit key/selection input through System Events when
  Accessibility permission is available.
- The 2026-05-13 live latency smoke passed on a small Markdown fixture in
  strict mode with `EditorKeyDown` p95 at 3.659 ms and `EditorTextChange` p95
  at 0.163 ms. The same smoke opened `/Users/malikov/Downloads/openapi.json`
  without screenshots, recorded `EditorOpenFile` at 0.368 ms,
  `EditorInitialRender` at 14.180 ms, and confirmed the local automation bridge
  still responded to `/health` while the fresh safe-mode relaunch ended on
  `Scratch 1`.
- After the source-engine prototype slice, `./script/build_and_run.sh --verify
  --safe-mode` rebuilt the app, launched `dist/SimpleLime.app` without
  screenshots, confirmed `/health` on the local automation bridge, and left a
  fresh safe-mode `SimpleLime` process running as PID 77575 on `Scratch 1`.
- After the source command fallback slice, the same safe-mode verify command
  rebuilt the app, relaunched `dist/SimpleLime.app` without screenshots,
  confirmed `/health` on the local automation bridge, and left a fresh
  safe-mode `SimpleLime` process running as PID 86188 on `Scratch 1`.
- After the source decoration bridge slice, the same safe-mode verify command
  rebuilt the app, relaunched `dist/SimpleLime.app` without screenshots,
  confirmed `/health` on the local automation bridge, and left a fresh
  safe-mode `SimpleLime` process running as PID 94133 on `Scratch 1`.
- After the CodeMirror multiple-selection bridge slice, the same safe-mode
  verify command rebuilt the app, relaunched `dist/SimpleLime.app` without
  screenshots, confirmed `/health` on the local automation bridge, and left a
  fresh safe-mode `SimpleLime` process running as PID 2373 on `Scratch 1`.
- After the raw multi-cursor macro capture slice, the same safe-mode verify
  command rebuilt the app, relaunched `dist/SimpleLime.app` without
  screenshots, confirmed `/health` on the local automation bridge, and left a
  fresh safe-mode `SimpleLime` process running as PID 9800 on `Scratch 1`.
- After the CodeMirror host-selection scroll bridge slice, the same safe-mode
  verify command rebuilt the app, relaunched `dist/SimpleLime.app` without
  screenshots, confirmed `/health` on the local automation bridge, and left a
  fresh safe-mode `SimpleLime` process running as PID 14985 on `Scratch 1`.
- After the CodeMirror column-guide bridge slice, the same safe-mode verify
  command rebuilt the app, relaunched `dist/SimpleLime.app` without
  screenshots, confirmed `/health` on the local automation bridge, and left a
  fresh safe-mode `SimpleLime` process running as PID 21889 on `Scratch 1`.
- After the CodeMirror focus/typewriter mode bridge slice, the same safe-mode
  verify command rebuilt the app, relaunched `dist/SimpleLime.app` without
  screenshots, confirmed `/health` on the local automation bridge, and left a
  fresh safe-mode `SimpleLime` process running as PID 28469 on `Scratch 1`.
- After the CodeMirror folded-range display bridge slice, the same safe-mode
  verify command rebuilt the app, relaunched `dist/SimpleLime.app` without
  screenshots, confirmed `/health` on the local automation bridge, and left a
  fresh safe-mode `SimpleLime` process running as PID 36000 on `Scratch 1`.
- After the CodeMirror direct selection/line movement/comment command and read-only guard slice, the same
  safe-mode verify command rebuilt the app, relaunched `dist/SimpleLime.app`
  without screenshots, confirmed `/health` on the local automation bridge, and
  left a fresh safe-mode `SimpleLime` process running as PID 69213 on
  `Scratch 1`.
- `./script/build_and_run.sh --build-only` passed.
- `git diff --check` passed.
- `./script/editor_core_benchmark.sh --skip-build` passed: generated 100,002-line Markdown,
  16,001-line CSV, and 25,001-line plain-text fixtures; measured the provided
  OpenAPI fixture at 739,209 bytes and 21,886 lines; reran 30 focused
  editor/large-file/telemetry/acceptance-gate tests with 0 failures; and
  skipped the app build because the live GUI smoke already used the staged app.
- `/Users/malikov/Downloads/openapi.json` measured at 739,209 bytes and 21,886
  lines; JSON now crosses the complex-text large-file threshold even if the user
  previously raised the Code Threshold above the safe cap, restores as a 16 KB
  read-only preview chunk for persistence/recovery, renders the source through
  a virtualized full-file line table with off-main visible-range prefetch and
  visible-row syntax highlighting,
  stores only metadata in session buffers, supports
  asynchronous full-file exact search and `:line`/open-at-line jumps that load
  matching chunks, cancels pending open/preview-load work when a tab is closed,
  and closes without the unsaved-state modal even from stale dirty/normal
  session records; heavy legacy close confirmations also suspend the editor
  rendering behind the modal and omit the pending-close buffer from session
  persistence so the close dialog stays responsive; `--safe-mode` can skip
  restored tabs entirely when a persisted session is already toxic.
- Live GUI verification after relaunching with `/Users/malikov/Downloads/openapi.json`
  on PID 47829 showed no `Publishing changes from within view updates` SwiftUI
  runtime warnings for that process.
- Live GUI verification after the window-chrome regression fix relaunched
  `/Users/malikov/Downloads/openapi.json` on PID 60478 and confirmed the native
  `SimpleLime - ...` window title no longer draws over the custom tab bar;
  SwiftUI runtime-warning log check for the same window-chrome path was empty.
- After the virtual range/block large-file edit follow-up,
  `./script/build_and_run.sh --verify --safe-mode` relaunched the app and
  `/health` on `http://127.0.0.1:48777` returned ok for `Scratch 1`; no
  screenshots were taken.
- After the inline/keyboard virtual large-file edit follow-up,
  `./script/build_and_run.sh --verify --safe-mode` built and relaunched the app
  again; `/health` on `http://127.0.0.1:48777` returned ok for `Scratch 1` from
  PID 31901, and no screenshots were taken.
- After the click-positioned inline caret follow-up,
  `./script/build_and_run.sh --verify --safe-mode` built and relaunched the app
  again; `/health` on `http://127.0.0.1:48777` returned ok for `Scratch 1` from
  PID 38246, and no screenshots were taken.
- After the inline large-file edit shortcut follow-up,
  `./script/build_and_run.sh --verify --safe-mode` built and relaunched the app
  again; `/health` on `http://127.0.0.1:48777` returned ok for `Scratch 1` from
  PID 44480, and no screenshots were taken.
- After the real Python curses terminal TUI follow-up,
  `./script/build_and_run.sh --verify --safe-mode` built and relaunched the app
  again; `/health` on `http://127.0.0.1:48777` returned ok for `Scratch 1` from
  PID 46534, and no screenshots were taken.
- After the external app-data sync follow-up,
  `./script/build_and_run.sh --verify --safe-mode` built and relaunched the app
  again; `/health` on `http://127.0.0.1:48777` returned ok for `Scratch 1` from
  PID 56234, and no screenshots were taken.
- After the Settings sync status/check follow-up,
  `./script/build_and_run.sh --verify --safe-mode` built and relaunched the app
  again; `/health` on `http://127.0.0.1:48777` returned ok for `Scratch 1` from
  PID 58775, and no screenshots were taken.
- After the app-data clean-selection sync refinement,
  `./script/build_and_run.sh --verify --safe-mode` built and relaunched the app
  again; `/health` on `http://127.0.0.1:48777` returned ok for `Scratch 1` from
  PID 64089, and no screenshots were taken.

## Prompt-to-Artifact Checklist

| Requested capability | Status | Evidence | Remaining gap |
| --- | --- | --- | --- |
| Scribe conversations automatically from meeting app input/output | Shipped first slice | `Sources/SimpleLime/Models/VoiceScribe.swift`, `Sources/SimpleLime/Views/VoiceScribePanelView.swift`, `Sources/SimpleLime/Services/VoiceScribeRecognizer.swift`, `Tests/SimpleLimeTests/VoiceScribeTests.swift` | Auto source detects known native meeting apps plus browser windows whose titles expose Google Meet, Teams, Zoom meeting, Webex, Slack huddle, or Discord voice context, and inspects all tab URLs for every running supported scriptable browser when macOS Automation permission allows it; then it switches to mic+system capture with microphone fallback. Supported browser tab scans cover Safari, Chrome, Edge, Brave, and Arc, so a meeting URL no longer has to be in the frontmost browser. The opt-in Auto Meeting Scribe toggle in the Scribe panel and Settings -> Automation watches for detected meeting apps and starts the Auto source transcript automatically. Combined meeting capture now keeps running when only one source fails and reports the degraded-capture status in the panel, so a denied/missing system-audio or microphone path does not kill the other working recognizer. Browser URL detection is still limited by macOS Automation permission and by those scriptable browser integrations; non-scriptable browsers still rely on visible window-title matching. |
| Voice control while scribing | Shipped | `Sources/SimpleLime/Models/VoiceScribe.swift`, `Sources/SimpleLime/Stores/EditorStore.swift`, `Tests/SimpleLimeTests/VoiceScribeTests.swift` | Command set is intentionally local/editor scoped, including save, insert, panel toggles, close/force-close recovery for stuck tabs, and large-file line replace/insert/delete commands by spoken line number. |
| External scribe/voice plugin over HTTP/RPC/socket | Shipped | `Sources/SimpleLime/Services/LocalAutomationBridge.swift`, `Sources/SimpleLime/Models/LocalAutomationBridgeRequest.swift`, `Tests/SimpleLimeTests/LocalAutomationBridgeTests.swift`, README Local Automation Bridge section | REST, JSON-RPC 2.0, and newline-delimited raw socket JSON frames are available over the loopback bridge, including `close`, selected-tab `forceClose`, targeted `forceClosePath` for stuck-tab recovery, single-line `replaceLargeFileLine`/`insertLargeFileLine`/`deleteLargeFileLine`, and block/range `replaceLargeFileLines`/`insertLargeFileLines`/`deleteLargeFileLines` for local voice/LLM controllers to edit selected large-file sources without loading the whole source. |
| Record and replay macros file-agnostically | Shipped editor slice | `Sources/SimpleLime/Models/ActionMacro.swift`, `Sources/SimpleLime/Stores/EditorStore.swift`, `Tests/SimpleLimeTests/EditorStoreTextMacroTests.swift` | Captures editor actions, selection moves, transforms, Markdown and line commands; command replay now has a store-level fallback for Markdown formatting, line move/delete/indent/outdent, split/expand selection, and language-aware line comments when a source view implementation cannot execute the command itself. It is not arbitrary OS-level mouse/menu gesture recording. |
| Custom button to call macros | Shipped | `Sources/SimpleLime/Models/PinnedMacroReference.swift`, `Sources/SimpleLime/Views/TextMacroPanelView.swift`, status bar integration in `Sources/SimpleLime/Views/EditorWorkspaceView.swift`, `Tests/SimpleLimeTests/EditorStoreTextMacroTests.swift` | Buttons live in status bar, not a fully customizable toolbar editor. |
| Companion mode watching work in real time | Partial | `Sources/SimpleLime/Views/CompanionPanelView.swift`, `Sources/SimpleLime/Models/CompanionSuggestion.swift`, `Sources/SimpleLime/Models/CompanionSettings.swift`, `Sources/SimpleLime/Stores/EditorStore.swift`, `Sources/SimpleLime/Views/SettingsView.swift`, `Tests/SimpleLimeTests/EditorStoreCompanionTests.swift`, `Tests/SimpleLimeTests/CompanionSettingsTests.swift` | Live watch is debounced editor-context scanning through HTTP LLM from text edits, selection/tab changes, current comments, tasks, today's local activity, and active-app context changes from optional frontmost macOS app/window metadata plus opt-in Accessibility selected/focused text when macOS grants access and opt-in ScreenCaptureKit active-window OCR text after macOS screen-recording permission; screenshots stay local and only recognized text enters the prompt. This is still not a full OS session recorder. |
| Apply companion suggestions/comments | Shipped | `Sources/SimpleLime/Stores/EditorStore.swift`, `Sources/SimpleLime/Models/CompanionSuggestion.swift`, `Sources/SimpleLime/Views/CompanionPanelView.swift`, `Tests/SimpleLimeTests/EditorStoreCompanionTests.swift`, `Tests/SimpleLimeTests/CompanionSuggestionParserTests.swift` | Supports exact, normalized-whitespace, and unique fuzzy token anchors for single edits plus bounded unified-diff `patchText` suggestions for multi-edit changes; patches apply only when every old/context block matches uniquely, so stale or ambiguous patches are rejected. |
| Kanban/tasks | Shipped | `Sources/SimpleLime/Models/TaskBoard.swift`, `Sources/SimpleLime/Views/TaskBoardPanelView.swift`, `Sources/SimpleLime/Services/TaskBoardPersistence.swift`, `Tests/SimpleLimeTests/EditorStoreTaskBoardTests.swift`, `Tests/SimpleLimeTests/TaskBoardPersistenceTests.swift`, `Tests/SimpleLimeTests/WorkspaceStoreTests.swift` | Manual tasks support both Mac-wide global scope and workspace-local scope; PO Mode gaps can be added as workspace tasks; detected tasks still come from the active workspace's open buffers and opened Documents folder. |
| Tasks automatically created from opened files | Shipped | `Sources/SimpleLime/Models/MarkdownTaskScanner.swift`, `Sources/SimpleLime/Models/AITaskInference.swift`, `Sources/SimpleLime/Stores/EditorStore.swift`, `Sources/SimpleLime/Views/SettingsView.swift`, `Tests/SimpleLimeTests/MarkdownTaskScannerTests.swift`, `Tests/SimpleLimeTests/EditorStoreTaskBoardTests.swift` | Detects Markdown checklist items, TODO/FIXME/ACTION/FOLLOW-UP/NEXT-STEP style lines, and plain-language action lines such as `need/should/please/нужно` in open buffers and opened Documents folders; optional HTTP LLM task inference can add deduplicated manual tasks from open text tabs manually or through an opt-in debounced background setting after opening/editing a text tab. |
| PO mode for document folder, mind map, Kanban, feature docs, search, gaps, drilldown | Shipped first slice | `Sources/SimpleLime/Models/DocumentFolderAnalysis.swift`, `Sources/SimpleLime/Views/POModePanelView.swift`, `Sources/SimpleLime/Stores/EditorStore.swift`, `Tests/SimpleLimeTests/DocumentFolderAnalysisTests.swift`, `Tests/SimpleLimeTests/EditorStorePOModeTests.swift` | Local/heuristic analysis remains the offline baseline; optional HTTP LLM interpretation now reads the generated PO report and returns product reading, gaps, risks, and next actions, and detected gaps/open questions can be promoted into deduplicated workspace To Do tasks. |
| Git detection and commit changes | Shipped | `Sources/SimpleLime/Services/GitRepositoryService.swift`, `Tests/SimpleLimeTests/GitRepositoryServiceTests.swift`, `Tests/SimpleLimeTests/EditorStoreGitTests.swift` | Commit flow is current-file focused, not a full git client. |
| Diff checker for two files | Shipped | `Sources/SimpleLime/Models/TextDiff.swift`, `Sources/SimpleLime/Stores/EditorStore.swift`, `Sources/SimpleLime/App/SimpleLimeCommands.swift`, `Tests/SimpleLimeTests/TextDiffTests.swift`, `Tests/SimpleLimeTests/EditorStoreDiffTests.swift` | Supports current tab versus previous tab and current tab versus a chosen text file; oversized text inputs create an explicitly marked bounded diff preview instead of blocking the workflow, and file-backed large-file preview tabs now diff bounded previews read from their source files instead of the visible chunk. Only synthetic large previews without a source path are rejected. |
| Versioning without git as `name.1`, `name.2` | Shipped | `Sources/SimpleLime/Stores/EditorStore.swift`, `Sources/SimpleLime/App/SimpleLimeCommands.swift`, `Sources/SimpleLime/Views/ContentView.swift`, `Tests/SimpleLimeTests/EditorStoreFileVersionTests.swift` | Supports explicit numbered copies of the current buffer plus a save-with-numbered-backup workflow that snapshots the on-disk file to the next `name.N.ext` before overwriting it with current edits; no timed background snapshot history. |
| Templates via macros: PRD, 1x1, meeting notes | Shipped | `Sources/SimpleLime/Models/TextMacro.swift`, `Tests/SimpleLimeTests/EditorStoreTextMacroTests.swift` | Built-ins and custom macros support reusable `{{Field:Default}}` prompts plus automatic Date/Time/DateTime fields; no conditional or repeating template sections. |
| Open text-readable data with Open/Open With | Shipped | App document types in `script/build_and_run.sh`, `Sources/SimpleLime/Models/EditorLanguage.swift`, `Tests/SimpleLimeTests/EditorStoreBinaryFileTests.swift` | Depends on macOS Launch Services registration after app bundle install. |
| Binary images/PDF wrappers | Shipped first slice | `Sources/SimpleLime/Views/BinaryFilePreviewView.swift`, `Sources/SimpleLime/Models/ImageFileInspection.swift`, `Sources/SimpleLime/Services/ExternalFileEditorService.swift`, `Tests/SimpleLimeTests/ImageFileInspectionTests.swift`, `Tests/SimpleLimeTests/ExternalFileEditorServiceTests.swift` | Image tools now include inspection/zoom plus Finder/default-app handoff and SimpleShot handoff when installed; editing still happens in the external image tool. |
| Hex preview | Shipped | `Sources/SimpleLime/Models/HexDump.swift`, `Tests/SimpleLimeTests/HexDumpTests.swift` | Read-only preview only. |
| CSV as table while editable as text | Shipped | `Sources/SimpleLime/Views/DelimitedTablePreviewView.swift`, `Sources/SimpleLime/Views/DelimitedVirtualTablePreviewView.swift`, `Sources/SimpleLime/Models/DelimitedTextTable.swift`, `Sources/SimpleLime/Models/DelimitedVirtualTableDocument.swift`, `Tests/SimpleLimeTests/DelimitedTextTableTests.swift`, `Tests/SimpleLimeTests/DelimitedVirtualTableDocumentTests.swift`, `Tests/SimpleLimeTests/EditorStoreLargeFileTests.swift` | Table view is preview-only through AppKit `NSTableView`; cell editing remains through source text. Normal buffers use bounded in-memory preview parsing, while large CSV/TSV buffers use a full-file virtual table index and read visible rows from disk on demand. |
| CSV large file no crash / 16k rows | Shipped regression | `Tests/SimpleLimeTests/DelimitedTextTableTests.swift`, `Tests/SimpleLimeTests/DelimitedVirtualTableDocumentTests.swift`, `Tests/SimpleLimeTests/EditorStoreLargeFileTests.swift`, `Sources/SimpleLime/Models/DelimitedTextTable.swift`, `Sources/SimpleLime/Models/DelimitedVirtualTableDocument.swift`, `Sources/SimpleLime/Models/DelimitedTablePreviewConfiguration.swift`, `Sources/SimpleLime/Views/DelimitedTablePreviewView.swift`, `Sources/SimpleLime/Views/DelimitedVirtualTablePreviewView.swift`, `Sources/SimpleLime/Views/EditorWorkspaceView.swift` | Rendering uses virtualized `NSTableView` rows and user-configurable row/column caps; normal preview parsing stops after the rendered row/column window, and large CSV/TSV mode now builds an off-main quote-aware record-offset index for the full file, then reads visible records by byte range. Regression coverage includes generated 16k-row CSV, quoted newlines/escaped quotes, TSV, trailing-newline handling, and the local buyers-plan CSV fixture when present. It is not a fully editable spreadsheet. |
| Statistics and analysis over day/week/month/year | Shipped first slice | `Sources/SimpleLime/Models/UsageStats.swift`, `Sources/SimpleLime/Views/UsageStatsPanelView.swift`, `Tests/SimpleLimeTests/EditorStoreUsageStatsTests.swift`, `Tests/SimpleLimeTests/EditorStoreCompanionTests.swift` | Shows Today/7/30/365 day aggregates for edits, added/removed characters, unique documents, unique file-backed documents, unique scratch buffers, opens, saves, exports, macros, active editing time, and optional Activity Watch or Live Companion frontmost app/window timeline entries that do not pollute document counts; Activity Watch now records local app/window timeline entries even when Companion Window Context is disabled, while those entries stay out of Companion prompts unless the context setting is enabled; the current app/window interval is flushed when Activity Watch, Live Companion, or system context watching stops; metrics are still not full screen/session recording. |
| Timelog of what happened today and durations | Shipped first slice | `Sources/SimpleLime/Models/UsageStats.swift`, `Sources/SimpleLime/Views/UsageStatsPanelView.swift`, `Sources/SimpleLime/Views/ContentView.swift`, `Sources/SimpleLime/App/SimpleLimeCommands.swift`, `Tests/SimpleLimeTests/EditorStoreUsageStatsTests.swift`, `Tests/SimpleLimeTests/EditorStoreCompanionTests.swift` | Stats can create a Markdown timelog scratch for today's summary and activity entries; durations are inferred from editor events, macro runtime, optional Activity Watch app/window changes, and Live Companion app/window changes including the final watched interval when monitoring stops, not continuous screen recording. |
| Translation via LLM | Shipped | `Sources/SimpleLime/Models/AITranslationRequest.swift`, `Tests/SimpleLimeTests/EditorStoreTranslationTests.swift`, `Tests/SimpleLimeTests/AITranslationResponseParserTests.swift` | Uses configured HTTP LLM; no dedicated translation provider UI. |
| Direct LLM API providers beyond ACP | Shipped | `Sources/SimpleLime/Services/HTTPAIClient.swift`, `Sources/SimpleLime/Models/HTTPAIConfiguration.swift`, `Tests/SimpleLimeTests/HTTPAIClientTests.swift` | Supports OpenAI-compatible, Anthropic, Gemini; provider-specific advanced options are limited. |
| Local LLM through OpenAI-compatible API | Shipped | README AI section, `Sources/SimpleLime/Models/HTTPAIConfiguration.swift` | User must configure local endpoint. |
| Cloud sync via iCloud | Shipped first slice | `Sources/SimpleLime/Services/AppDataStorage.swift`, `Sources/SimpleLime/Services/AppDataRootSnapshot.swift`, `Sources/SimpleLime/Stores/WorkspaceStore.swift`, `Sources/SimpleLime/Views/SettingsView.swift`, `Tests/SimpleLimeTests/AppDataStorageTests.swift`, `Tests/SimpleLimeTests/WorkspaceStoreTests.swift`, README Features | App data root can be placed in iCloud Drive, existing app data is merge-migrated, divergent losing-side files are kept as timestamped conflict copies, workspaces reload immediately, and the running workspace periodically detects external app-data changes so a clean session can reload synced state without restart. Settings shows sync status and has a Check Now action for manual verification. Pending local in-memory edits keep the current window instead of being overwritten. There is still no CloudKit conflict resolution or multi-device merge UI. |
| List Tab/Shift-Tab from any cursor position | Shipped | `Sources/SimpleLime/Models/EditorTypingRules.swift`, `Tests/SimpleLimeTests/EditorTypingRulesTests.swift`, WYSIWYG tests | Source and WYSIWYG paths covered by tests. |
| Context-aware quote auto-close | Shipped | `Sources/SimpleLime/Models/EditorTypingRules.swift`, `Tests/SimpleLimeTests/EditorTypingRulesTests.swift` | Straight quotes covered; smart quote substitutions are disabled. |
| Typographic dashes visibly distinct | Shipped | `Sources/SimpleLime/Services/SyntaxHighlighter.swift`, `Tests/SimpleLimeTests/SyntaxHighlighterTests.swift` | Visual distinction is syntax-highlighting based. |
| PDF, HTML, Word, Excel export | Shipped | `Sources/SimpleLime/Services/DocumentExportService.swift`, `Tests/SimpleLimeTests/DocumentExportServiceTests.swift` | Word now writes native `.docx` OOXML packages and Excel writes native `.xlsx` OOXML packages; legacy Word/Excel-compatible HTML generators remain for compatibility tests. |
| Fix PDF export text orientation/order | Shipped regression | `Tests/SimpleLimeTests/DocumentExportServiceTests.swift` | Covered by Cyrillic extraction/order and top-of-page tests. |
| Save As file type and AI file-name suggestion | Shipped | `Sources/SimpleLime/Support/SaveFileTypeAccessoryController.swift`, `Sources/SimpleLime/Models/SaveFileType.swift`, `Tests/SimpleLimeTests/EditorStoreSaveAsTests.swift` | AI naming requires configured HTTP provider. |
| More flexible settings | Shipped first slice | `Sources/SimpleLime/Views/SettingsView.swift`, `Sources/SimpleLime/Models/SettingsSearchCatalog.swift`, `Sources/SimpleLime/Models/SourceEditorAdapter.swift`, `Sources/SimpleLime/Models/HTTPAIConfiguration.swift`, `Sources/SimpleLime/Models/TerminalConfiguration.swift`, `Sources/SimpleLime/Models/DelimitedTablePreviewConfiguration.swift`, `Sources/SimpleLime/Models/LargeFileConfiguration.swift`, `Sources/SimpleLime/Models/WhiteboardConfiguration.swift`, `Sources/SimpleLime/Models/CompanionSettings.swift`, `Sources/SimpleLime/Models/AITaskInference.swift`, `Tests/SimpleLimeTests/SettingsSearchCatalogTests.swift` | Settings now cover editor basics including the opt-in source-engine picker for the CodeMirror 6 WebView prototype, HTTP LLM providers, opt-in automatic task inference, opt-in Auto Meeting Scribe watching, Companion frontmost-window context, opt-in Accessibility selected-text context, opt-in active-window OCR text context, app data root plus sync status/manual check, table preview caps, large-file thresholds/chunk sizes, whiteboard grid/default sticky/connector behavior, and terminal shell/`TERM`/UTF-8 locale fallback; a searchable section catalog filters editor, performance, whiteboard, storage, AI, terminal, and automation controls. The code/JSON threshold is capped for safety, and future capabilities can still add more settings. |
| Word-wrap limits / PEP8 vertical guide | Shipped | `Sources/SimpleLime/Views/CodeEditorView.swift`, `Sources/SimpleLime/Views/CodeMirrorSourceEditorView.swift`, `Tests/SimpleLimeTests/EditorStoreModeTests.swift`, `Tests/SimpleLimeTests/SourceEditorAdapterTests.swift` | Single guide value; no per-language profiles. The CodeMirror prototype and textarea fallback now render the same configured guide. |
| Terminal bottom panel with tabs and file-folder cwd | Shipped | `Sources/SimpleLime/Views/TerminalPanelView.swift`, `Sources/SimpleLime/Services/LocalTerminalProcess.swift`, `Sources/SimpleLime/Models/TerminalConfiguration.swift`, `Tests/SimpleLimeTests/EditorStoreTerminalTests.swift` | Uses SwiftTerm grid; shell path, `TERM`, and UTF-8 locale fallback are configurable; tabs track shell-provided title/current-directory callbacks, and active tabs expose interrupt and reset controls for long-running commands and broken terminal states. |
| Terminal handles zsh/oh-my-zsh/ANSI/TUI better | Shipped first slice | `Package.swift` SwiftTerm dependency, `Sources/SimpleLime/Views/TerminalPanelView.swift`, `Sources/SimpleLime/Services/LocalTerminalProcess.swift`, `Tests/SimpleLimeTests/EditorStoreTerminalTests.swift`, `Tests/SimpleLimeTests/TerminalConfigurationTests.swift` | PTY tests now cover real `/bin/zsh`, configurable UTF-8/truecolor locale environment normalization, initial and changed terminal size synchronization, alternate screen, cursor positioning, bounded raw-byte replay into SwiftTerm with clean-state reset after truncation, shell title/current-directory updates, off-main PTY output delivery, 180 KB noisy-output draining, UI-side SwiftTerm feed batching, `Ctrl-C` interrupt of a foreground PTY command, interrupted `/usr/bin/top` recovery with the same shell remaining usable afterward, real `/usr/bin/vim` alternate-screen entry/exit with UTF-8 Cyrillic rendering and a follow-up shell command in the same PTY, real Claude Code `--bare` TUI interrupt recovery with a follow-up shell command, real Codex CLI TUI startup followed by same-tab terminal restart recovery and a follow-up shell command, deterministic agent-style interactive TUI recovery through zsh with alternate screen, cursor hide/show, title sequence, clear screen, cursor addressing, Cyrillic output and follow-up shell command, real Python curses full-screen TUI entry/input/exit with UTF-8 output and same-PTY shell follow-up, a conditional real `htop` full-screen smoke that runs automatically when `htop` is installed, `stty sane; reset` recovery, same-tab PTY restart that ignores late exits from the old process, and a user-facing Run Terminal Diagnostics command that sends its shell payload in small PTY-safe chunks, verifies `/dev/tty`-backed `stty size`, UTF-8/color/title/alternate-screen/cursor-addressing, and an optional Python curses full-screen smoke before proving the shell still accepts a follow-up command; `htop` was not installed on this verification machine, so the `htop` case is present but skipped locally. |
| Encryption for scratches/files with password | Shipped | `Sources/SimpleLime/Services/EncryptedDocumentService.swift`, `Tests/SimpleLimeTests/EditorStoreEncryptionTests.swift`, `Tests/SimpleLimeTests/EncryptedDocumentServiceTests.swift` | Scratch encryption is through saving encrypted copy; unsaved scratch-at-rest encryption is not separate. |
| Touch ID support | Shipped first slice | `Sources/SimpleLime/Services/EncryptedDocumentPasswordStore.swift`, `Sources/SimpleLime/Support/EncryptedDocumentPasswordPrompt.swift` | Uses Keychain user-presence access control; exact biometric behavior depends on system policy. |
| Collapse JSON/YAML threads | Shipped | `Sources/SimpleLime/Models/StructuredFoldRange.swift`, `Sources/SimpleLime/Views/CodeMirrorSourceEditorView.swift`, `Tests/SimpleLimeTests/StructuredTextFolderTests.swift`, `Tests/SimpleLimeTests/EditorStoreFoldingTests.swift`, `Tests/SimpleLimeTests/SourceEditorAdapterTests.swift` | Folding is source-mode only and read-only while folded. Native STTextView owns full fold-gutter behavior; the opt-in CodeMirror prototype now receives folded ranges and renders them as read-only replacement widgets with textarea fallback folded text, but it still does not claim full structured-folding feature parity. |
| Self-hosted microserver shared links | Shipped standalone slice | `Sources/SimpleLime/Services/CollaborationRelayServer.swift`, `Sources/SimpleLime/Services/CollaborationRelayClient.swift`, `Sources/SimpleLimeRelay/main.swift`, `Sources/SimpleLimeRelayCore/StandaloneCollaborationRelayServer.swift`, `Sources/SimpleLimeRelayCore/StandaloneRelayConfiguration.swift`, `Tests/SimpleLimeTests/CollaborationRelayTests.swift`, `Tests/SimpleLimeTests/StandaloneRelayTests.swift` | Host/server must be reachable; current clients authenticate relay requests with `Authorization: Bearer` instead of putting tokens in HTTP request URLs, relay parsers bound headers/bodies, event histories are trimmed by count and encoded byte budget, duplicate query items do not crash parsing, standalone non-local `--public-url` values require `https` unless explicitly overridden, and legacy query-token compatibility remains; no NAT traversal, TLS termination automation, or deployment platform. |
| JSON minify/format | Shipped | `Sources/SimpleLime/Models/JSONTextFormatter.swift`, `Tests/SimpleLimeTests/JSONTextFormatterTests.swift` | Selection/full-buffer transform only. |
| Markdown table autoformat | Shipped | `Sources/SimpleLime/Models/MarkdownTableFormatter.swift`, `Tests/SimpleLimeTests/MarkdownTableFormatterTests.swift` | Source transform only. |
| Big files opening | Partial | `Sources/SimpleLime/Stores/EditorStore.swift`, `Sources/SimpleLime/Services/SessionPersistence.swift`, `Sources/SimpleLime/Models/LargeFileConfiguration.swift`, `Sources/SimpleLime/Models/LargeFileLineIndex.swift`, `Sources/SimpleLime/Models/LargeFileVirtualTextDocument.swift`, `Sources/SimpleLime/Models/DelimitedVirtualTableDocument.swift`, `Sources/SimpleLime/Views/LargeFileVirtualTextView.swift`, `Sources/SimpleLime/Views/DelimitedVirtualTablePreviewView.swift`, `Sources/SimpleLime/Views/EditorWorkspaceView.swift`, `Sources/SimpleLime/Views/DelimitedTablePreviewView.swift`, `Tests/SimpleLimeTests/EditorStoreLargeFileTests.swift`, `Tests/SimpleLimeTests/LargeFileConfigurationTests.swift`, `Tests/SimpleLimeTests/LargeFileVirtualTextDocumentTests.swift`, `Tests/SimpleLimeTests/DelimitedVirtualTableDocumentTests.swift` | Large files now render as a virtualized full-file source view backed by off-main newline indexing, off-main visible-range line prefetch, and lightweight syntax highlighting for visible lines without doing disk reads from table-cell rendering, while large CSV/TSV previews render as virtual full-file tables backed by off-main record-offset indexing and visible-row disk reads. The persisted buffer remains a safe bounded chunk. Existing chunk controls still provide paging, repeated `:line` jumps/open-at-line references, click-positioned inline one-line editing from a visible virtual row with Enter/Cmd-S commit and Esc/Cmd-. cancel, keyboard Up/Down/Enter/Delete row controls, double-click chunk opening from the virtual source view, visible-row context-menu replace/insert/delete line actions, status-bar visible-line edit opening for the first visible virtual line, status-bar visible-line scratch extraction for the first visible virtual line, asynchronous full-file exact search that jumps to matching chunks, direct in-place editing for exact-boundary chunks with `Cmd-S` byte-range save-back, editable scratch extraction for the current loaded chunk, safe source write-back when the source file size still matches, single-line virtual replace/insert/delete by line number through streamed byte-range rewrite, and block/range virtual replace/insert/delete through the REST command endpoint, JSON-RPC endpoint, and newline-delimited socket frames. These streamed edits preserve source line endings, refresh sparse indexes, jump the preview back to the changed byte range, and keep single-line modal/menu behavior backward-compatible. Line-edit prompts default to the first visible virtual line rather than an old preview chunk offset; same-source chunk metadata shifts for non-overlapping edits and invalidates overlapping stale chunk scratches. Dirty in-place chunk session persistence, lightweight session restore, configurable text thresholds/chunk sizes, and a non-raisable safety cap for code/JSON thresholds are covered. A shared `LargeFileEditingCapability` keeps read-only virtual previews, editable preview chunks, extracted chunk scratches, and save-back availability distinct in commands, status text, and diagnostics; editable chunks keep source-editor syntax highlighting enabled. There is still no cursor-level full virtualized editable file model. |
| Large restored JSON can close/open without hang | Shipped regression | `Sources/SimpleLime/Services/SessionPersistence.swift`, `Sources/SimpleLime/Stores/EditorStore.swift`, `Sources/SimpleLime/App/SimpleLimeLaunchOptions.swift`, `Sources/SimpleLime/Views/ContentView.swift`, `Sources/SimpleLime/Views/CodeEditorView.swift`, `Sources/SimpleLime/App/SimpleLimeCommands.swift`, `Resources/simplelime`, `script/build_and_run.sh`, `Tests/SimpleLimeTests/EditorStoreLargeFileTests.swift`, `Tests/SimpleLimeTests/LargeFileConfigurationTests.swift`, `Tests/SimpleLimeTests/WorkspaceStoreTests.swift`, `Tests/SimpleLimeTests/EditorStoreLocalAutomationTests.swift`, `Tests/SimpleLimeTests/LocalAutomationBridgeTests.swift`, `Tests/SimpleLimeTests/VoiceScribeTests.swift` | Stale dirty/normal large JSON buffers are migrated/closed as read-only previews instead of entering `Close Tab?`; large-file previews reject edits so they cannot become dirty again, OpenAPI-sized JSON cannot be forced back into normal editing by an oversized Code Threshold setting, complex text previews default to 16 KB, pending open/preview-load tasks are cancelled when their tab closes instead of surfacing stale errors, heavyweight pending-close text is kept out of SwiftUI `@Published` alert state and the pending-close buffer is omitted from session persistence until Cancel restores it, Force Close Buffer can discard the selected stuck tab with `Shift-Cmd-W`, the command palette, local automation `forceClose`, or the `SimpleLime force close tab` voice command; local automation and the installed `simplelime` launcher also support targeted `forceClosePath`/`--force-close-path` by absolute path, file name, or tab title so recovery does not depend on the selected tab; `--safe-mode`/`--simplelime-safe-mode` can skip persisted tabs and replace a toxic restore with a clean session from both the installed `simplelime` launcher and local run script, `--build-only` warns with running PIDs when an old SimpleLime process is still running, and `run` now waits for the old process to exit before launching the fresh bundle, force-quitting only if the old app stays stuck. Existing running old app still needs relaunch to receive the fix. |
| Drawing board with stickers, connections, shapes, grouping, zoom, text | Shipped first slice | `Sources/SimpleLime/Views/WhiteboardView.swift`, `Sources/SimpleLime/Models/WhiteboardDocument.swift`, `Sources/SimpleLime/Models/WhiteboardConfiguration.swift`, `Tests/SimpleLimeTests/WhiteboardDocumentTests.swift`, `Tests/SimpleLimeTests/WhiteboardConfigurationTests.swift` | Supports configurable grid/default sticky/connector behavior, marquee multi-select, selected-item grouping, multi-item move/duplicate with connector endpoint remapping, grouping/ungrouping, group member alignment, and synced group bounds when members move; still basic compared with Miro, with no multiplayer whiteboard. |
| Whiteboard save as source, SVG, PNG | Shipped | `Sources/SimpleLime/Services/WhiteboardExportService.swift`, `Sources/SimpleLime/Stores/EditorStore.swift`, `Tests/SimpleLimeTests/WhiteboardDocumentTests.swift`, `Tests/SimpleLimeTests/EditorStoreDrawingTests.swift` | Supports `.sldraw` source, SVG/PNG file export, and copy-as-PNG to the macOS clipboard. |
| Whiteboard widgets in Markdown and export as image | Shipped | `Sources/SimpleLime/Views/MarkdownPreviewView.swift`, `Sources/SimpleLime/Services/DocumentExportService.swift`, `Tests/SimpleLimeTests/DocumentExportServiceTests.swift` | Widgets render in preview, export as inline SVG in HTML/legacy Word HTML, embed as PNG in native `.docx` and PDF, and are edited by opening the `.sldraw` source/tab. |
| Whiteboard Miro-like grid, anchor points, smart routes, bridge jumps, movable/duplicable blank stickers | Shipped regression | `Tests/SimpleLimeTests/WhiteboardDocumentTests.swift`, `Sources/SimpleLime/Views/WhiteboardView.swift` | Manual QA should still compare detailed connector feel against Miro. |
| Workspaces | Shipped | `Sources/SimpleLime/Stores/WorkspaceStore.swift`, `Sources/SimpleLime/Models/WorkspaceProfile.swift`, `Tests/SimpleLimeTests/WorkspaceStoreTests.swift` | Workspace-specific settings beyond sessions/tasks/document root are limited. |
| Read-only and temporary modes | Shipped | `Sources/SimpleLime/Models/EditorBuffer.swift`, `Tests/SimpleLimeTests/EditorStoreSavePolicyTests.swift` | Blocks saving; does not sandbox clipboard or external file access. |
| Reuse macOS Finder tags | Shipped | `Sources/SimpleLime/Services/FinderTagService.swift`, `Tests/SimpleLimeTests/FinderTagServiceTests.swift`, `Tests/SimpleLimeTests/EditorStoreFinderTagTests.swift` | Only add/display/clear in current file workflow. |
| Avoid more than one function per sidebar | Shipped | `Sources/SimpleLime/Stores/EditorStore.swift`, `Tests/SimpleLimeTests/EditorStorePanelLayoutTests.swift` | Terminal intentionally remains a bottom panel. |
| Custom tab bar not overlapped by native window title | Shipped regression | `Sources/SimpleLime/App/EditorWindowChrome.swift`, `Sources/SimpleLime/Views/WindowChromeReader.swift`, `Sources/SimpleLime/Views/ContentView.swift`, `Sources/SimpleLime/Views/TabBarView.swift`, `Tests/SimpleLimeTests/EditorWindowChromeTests.swift` | The app keeps a meaningful logical window name through accessibility label plus a stable editor-window identifier, clears the visible native `NSWindow.title`, keeps native traffic-light buttons visible above full-size SwiftUI content, clamps the tab bar's traffic-light inset so tabs cannot start halfway across the window, observes later title reapplication, and reapplies the configuration during SwiftUI updates so Chrome-style tabs remain the only visible header content next to the traffic-light buttons. |
| Keep minimap/CSV/tasks/Kanban content top aligned | Shipped | `Sources/SimpleLime/Views/EditorWorkspaceView.swift`, `Sources/SimpleLime/Views/DelimitedTablePreviewView.swift`, `Sources/SimpleLime/Views/DelimitedVirtualTablePreviewView.swift`, `Sources/SimpleLime/Views/TaskBoardPanelView.swift`, `Sources/SimpleLime/Support/TopAlignedClipView.swift`, `Tests/SimpleLimeTests/EditorMiniMapLayoutTests.swift`, `Tests/SimpleLimeTests/TopAlignedClipViewTests.swift` | Minimap layout is top-origin, task board scroll anchor is top-leading, and table preview NSScrollViews use a top-aligned AppKit clip view so short rendered tables do not center vertically or horizontally. Visual QA still recommended after app relaunch. |
| Text editor input latency, empty-area clicks, and selection autoscroll | Shipped stabilization slice | `Sources/SimpleLime/Views/CodeEditorView.swift`, `Sources/SimpleLime/Views/CodeMirrorSourceEditorView.swift`, `Sources/SimpleLime/Models/SourceEditorAdapter.swift`, `Sources/SimpleLime/Views/SourceEditorView.swift`, `Sources/SimpleLime/Views/LargeFileVirtualTextView.swift`, `Sources/SimpleLime/Views/WindowChromeReader.swift`, `Sources/SimpleLime/Models/EditorLanguage.swift`, `Sources/SimpleLime/Stores/EditorStore.swift`, `Sources/SimpleLime/Stores/WorkspaceStore.swift`, `Sources/SimpleLime/Support/EditorPerformanceTelemetry.swift`, `Sources/SimpleLime/Views/ContentView.swift`, `Sources/SimpleLime/App/SimpleLimeCommands.swift`, `Tests/SimpleLimeTests/CodeEditorViewTests.swift`, `Tests/SimpleLimeTests/SourceEditorAdapterTests.swift`, `Tests/SimpleLimeTests/EditorStoreModeTests.swift`, `Tests/SimpleLimeTests/EditorLanguageTests.swift`, `Tests/SimpleLimeTests/EditorPerformanceTelemetryTests.swift`, `Tests/SimpleLimeTests/SyntaxHighlighterTests.swift`, `Tests/SimpleLimeTests/StructuredTextFolderTests.swift`, `Tests/SimpleLimeTests/EditorStoreFoldingTests.swift`, `Tests/SimpleLimeTests/EditorStoreLargeFileTests.swift`, `Tests/SimpleLimeTests/LargeFileVirtualTextDocumentTests.swift`, `Tests/SimpleLimeTests/WorkspaceStoreTests.swift`, `Tests/SimpleLimeTests/EditorCorePerformanceProbeTests.swift`, `Tests/SimpleLimeTests/EditorStoreFinderTagTests.swift`, `Tests/SimpleLimeTests/EncryptedDocumentServiceTests.swift`, `Tests/SimpleLimeTests/EditorStoreLocalAutomationTests.swift`, `docs/editor-core-refactor-plan.md`, `script/editor_core_benchmark.sh`, `script/editor_live_latency_smoke.sh` | Regular typing no longer performs synchronous full-document syntax highlighting, rendering decorations refresh only when needed, syntax languages are highlighted through a short debounce, structured fold gutter refreshes are signature-gated and debounced after text edits, focus dimming is idempotent instead of clearing foreground rendering over the full document on every selection change and no longer overlays the active JSON/source line with plain label foreground that hides syntax colors, large-file virtual text cells no longer accept NSTextField text selection/focus that can repaint clicked JSON rows with system selected-text colors, text line ranges are cached between mutations for visible-range/gutter/click/column-cursor paths and covered by a 25k-line regression, visible-range math guards invalid AppKit visible rects instead of trapping, shift-selection explicitly scrolls the active selection edge into view, ordinary clicks in empty editor space fall back to the nearest line end instead of the beginning of the document, large-file visible-range publication and window activation/fullscreen publication are deferred out of SwiftUI view updates, external command-line file opens are delayed until after the launch view pass, encrypted-document prefix probing is extension-gated to `.slenc` instead of opening arbitrary JSON/CSV files on the main actor, large-file virtual view load keys no longer stat the source file during SwiftUI layout, and the status bar does not synchronously read Finder tags for large-file previews. The menu/command palette can create an Editor Diagnostics Markdown scratch that records the active render path, syntax/fold/minimap/focus state, size metadata, large-file policy, Large-File Editing Capability, an Editor Core Compatibility table, Editor Core Acceptance Gates with Pass/Warning/Manual/Fail rows, and risk flags for the selected buffer. The source editor now emits `EditorPerformance` OSLog/signpost intervals plus parseable duration metrics for open, first render/update, key events, text/selection changes, syntax, fold gutter, minimap, and close paths. `SourceEditorView` is now the contract boundary around the current native STTextView implementation and exposes an opt-in CodeMirror 6 WebView prototype through Settings -> Editor -> Source Engine; the prototype reports text, multiple selections, and visible-line changes back to Swift, accepts multiple selection ranges from Swift, receives normalized comment/collaboration decoration payloads for comment marks plus collaborator range/caret rendering, routes a small direct WebView command set including WebView-native expand-line, split-selection, move-line, language-aware toggle-comment, and common text-transform commands, guards mutating direct commands behind the same editability/read-only/folded-range check as the view state, scrolls host-driven selection updates into view, renders the configured column guide, receives focus/typewriter flags, dims non-focused blocks in focus mode, centers/scroll-pads selection movement in typewriter mode with textarea fallback classes, and renders host-provided folded ranges as read-only replacement widgets with textarea fallback folded text. It still relies on store-level fallbacks for JSON minify/format, Markdown table formatting, Markdown commands, and any source command the WebView path cannot perform, and still does not claim full folding/minimap parity. The store can also recognize identical raw replacements across multiple selections from the WebView path and record one file-agnostic action macro step. It is not feature-parity yet. The editor core refactor plan records success criteria, external implementation notes, options, gates, migration plan, compatibility/acceptance-gate diagnostics, headless performance probes, and the repeatable `script/editor_core_benchmark.sh` plus `script/editor_live_latency_smoke.sh` smoke entrypoints; this is still not proof that the current editor core is the right long-term engine. |

## Current Residual Risks

1. The current editor core is still an STTextView/TextKit bridge with SwiftUI
   state around it. The most obvious hot-path bug has been removed, the new
   Editor Diagnostics scratch exposes the selected buffer's render path,
   compatibility matrix, acceptance gates, and risk flags, `EditorPerformance`
   signposts expose the live hot path, the live latency smoke script now
   collected no-screenshot GUI p95 metrics for a real built app, and the
   headless editor probe gives repeatable timing coverage for virtual text,
   virtual CSV, and visible syntax operations, but the long-term decision
   remains open: either prove this stack with measured real-app input latency
   and cursor/selection QA on large files, or move to a purpose-built virtual
   editable editor engine. The concrete spike gates and replacement options are
   tracked in `docs/editor-core-refactor-plan.md`.
2. Big files are safe and usable as a virtualized full-file read-only source
   view with off-main visible-range prefetch and visible-line syntax
   highlighting, plus searchable/navigable chunks, click-positioned inline one-line editing from
   visible virtual rows with Enter/Cmd-S commit and Esc/Cmd-. cancel, keyboard row movement/edit/delete, double-click opening
   into an editable exact chunk, cached sparse line indexes for repeated line
   jumps, visible-range scratch extraction, full-file virtual CSV/TSV table
   previews backed by quote-aware record-offset indexes, direct in-place editing
   for the current exact-boundary chunk, editable scratch extraction for the
   current chunk, safe write-back when the source file has not changed, and
   offset maintenance for multiple open chunk edits from the same source. There
   are now streamed single-line virtual replace/insert/delete primitives plus
   automation-driven block/range replace/insert/delete primitives for
   file-backed large text, visible-row context-menu actions, same-size rewrite
   cache invalidation, and prompts that default to the current visible virtual
   line, but this is still not a cursor-level virtualized editable full-file
   editor.
3. Companion mode watches editor actions, compact editor context, optional
   frontmost macOS app/window metadata, opt-in Accessibility selected text, and
   opt-in ScreenCaptureKit active-window OCR text from the active app. Stats
   Activity Watch can record frontmost app/window changes into the Today Log
   without enabling AI scans and without requiring Companion Window Context to
   be enabled; those app/window entries do not count as documents, are omitted
   from Companion prompts unless the context setting is enabled, and the last
   watched interval is flushed when watching stops.
   Screenshots remain local for OCR and are not sent to the HTTP provider, but
   this is still not a full OS session recording.
4. Task discovery covers Markdown checklist syntax, common TODO/FIXME/action
   markers, conservative plain-language action lines in open buffers and opened
   Documents folders, plus HTTP LLM inference for open text tabs. The LLM path
   can be run manually or enabled as an opt-in debounced background scan after
   opening/editing a text tab; it is still bounded to text context rather than a
   full OS activity watcher.
5. Terminal correctness is now based on SwiftTerm plus real PTY/zsh/TUI byte
   pipeline tests, bounded clean-state raw replay, foreground command interrupt
   coverage, off-main/noisy-output backpressure coverage, interrupted
   `/usr/bin/top` recovery, real `/usr/bin/vim` alternate-screen entry/exit with
   UTF-8 rendering and same-PTY follow-up shell command, real Claude Code
   interrupt recovery, real Codex CLI same-tab restart recovery, deterministic
   agent-style interactive TUI recovery, real Python curses full-screen
   entry/input/exit with UTF-8 output and same-PTY follow-up, a conditional real
   `htop` full-screen smoke that skipped locally because `htop` is not
   installed, reset recovery, real PTY resize verification via `stty size`, and
   a `/dev/tty`-backed in-app diagnostic smoke command with optional Python
   curses coverage. When `htop` is installed, the suite will exercise it
   automatically; a manual app QA pass is still useful for feel, but the
   automated suite now covers both the curses full-screen class and an explicit
   `htop` path.
6. The self-hosted relay now has in-app and standalone server modes,
   bearer-token relay requests that avoid leaking the room token through HTTP
   request URLs, bounded request parsing, byte-budgeted event history,
   configurable idle room cleanup, duplicate-query crash protection, and a
   standalone public URL guard that requires `https` for non-local share links
   unless explicitly overridden. It is still a reachable-host relay rather than
   a hardened internet service with built-in TLS termination automation, NAT
   traversal, or deployment platform.
7. Cloud sync is implemented as movable app data storage with an iCloud Drive
   shortcut, merge migration, timestamped conflict copies, immediate workspace
   reload, and bounded external app-data change polling for clean sessions, not
   as a CloudKit synchronization engine with conflict/merge UI.
