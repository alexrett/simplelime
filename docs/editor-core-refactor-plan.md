# SimpleLime Editor Core Refactor Plan

This document is the decision record for the text editor risk. The current
editor is a good prototype surface, but it should not keep accumulating editor
features until the core path is either proven with measurements or replaced.

## Problem Statement

Recent manual QA exposed issues that are typical of a text stack that renders
too much work through a regular rich text view:

- Large JSON could open but was effectively non-editable in the large-file path.
- Switching the same file to plain text made selection and editing feel slow.
- Shift-selection did not reliably autoscroll once the caret moved outside the
  visible viewport.
- Empty-area clicks could place the caret at the beginning of the file.
- Syntax highlighting added visible input latency.

Several hot-path bugs have been fixed: syntax highlighting is debounced,
focus dimming is idempotent, line metrics are cached, active selections are
scrolled into view, empty-area clicks choose the nearest line end, and focus
mode no longer paints the active JSON/source line with a temporary foreground
that hides syntax colors. The large-file virtual renderer also keeps its
read-only text cells non-selectable so AppKit selection drawing cannot repaint
clicked JSON rows with selected-text colors. Those fixes make the prototype
safer, but they do not prove the architecture.

## Success Criteria

The editor core is acceptable only if all of these are true on real app builds,
not just unit tests:

- Open `/Users/malikov/Downloads/openapi.json` without blocking the app for more
  than one visible pause.
- Navigate, search, select, and close that file without modal or UI hangs.
- Show the whole file through source navigation, not only the first preview
  chunk.
- Keep normal typing latency below a perceptible threshold on common files:
  target p95 under 32 ms per key event and no visible quarter-second stalls.
- Keep shift-selection autoscroll stable across viewport boundaries.
- Keep syntax/folding/minimap/comment decorations bounded to visible or changed
  ranges, never full-document work on each edit.
- Preserve current editor contracts: Markdown source/WYSIWYG switch, comments,
  collaboration anchors, macros, find/replace, tasks, folding, minimap, command
  palette actions, and export inputs.
- Support a clear large-file policy: either true virtual editing or explicitly
  read-only virtual browsing with bounded editable chunks.

## Current Architecture

Source mode uses an `STTextView`/TextKit-backed `NSViewRepresentable` wrapped in
SwiftUI state. Large-file handling currently avoids loading huge text into the
normal source editor by using read-only virtual views and bounded chunks.

Current strengths:

- Native macOS selection, IME, clipboard, accessibility, and input behavior.
- Existing integration with comments, collaboration, macros, folding, and
  Markdown commands.
- Small and medium files can keep using the existing surface after the hot-path
  fixes.

Current hard limits:

- A normal editable buffer is still an in-memory text view.
- Syntax and decoration features must be carefully gated to avoid touching the
  whole document.
- The large-file source view is virtual and full-file navigable, with
  visible-line inline single-line editing, keyboard row movement/edit/delete,
  double-click opening for exact bounded chunks, visible-range scratch
  extraction, context-menu single-line replace/insert/delete actions, and
  streamed single-line virtual replace/insert/delete by line number, but not a
  true full-file editable model.
- Performance confidence is based on targeted tests and manual feel, not a
  repeatable latency profile.

## External Implementation Notes

CodeMirror 6 is built around a functional editor state and a viewport-rendered
view. Its guide explicitly states that it does not render an entire big document
and instead renders the visible viewport plus a margin. It also keeps document
data in a line-indexed tree, which makes line lookup cheap.

Scintilla is a mature native editor component. Its API exposes document
allocation, line indexing allocation, large-document options beyond 2 GB, and
styling controls that can disable style allocation or use idle styling for very
large documents.

STTextView is a native TextKit 2 replacement around AppKit/UIKit text systems.
It is valuable for macOS integration, but it keeps SimpleLime on the same class
of text-layout risk that the current implementation is already fighting.

## Options

### Option A: Keep Hardening STTextView

Use this only as the short-term path.

Pros:

- Lowest migration cost.
- Preserves current native behavior.
- Keeps existing source editor integrations mostly untouched.

Cons:

- Does not solve true full-file virtual editing.
- Requires continuous defensive gating around syntax, folding, minimap, focus,
  comments, and selection metrics.
- Risk remains concentrated in TextKit/AppKit layout behavior.

Gate:

- Keep only if measured input latency and selection latency stay under the
  success criteria on representative files.

### Option B: CodeMirror 6 in WKWebView for Source Mode

Prototype source-mode editing in a WebView while keeping the rest of the app
native.

Pros:

- Viewport rendering and line-indexed document model are first-class concepts.
- Mature commands, selections, decorations, syntax extensions, folding, and
  collaborative-change primitives.
- Faster path to a proven editor model than writing a full native renderer.

Cons:

- WebView bridge must handle file I/O, native commands, menus, keybindings,
  pasteboard, find, diagnostics, and theme sync.
- Needs careful IME/accessibility/manual QA on macOS.
- Markdown WYSIWYG integration may remain separate.

Gate:

- Build a source-mode prototype that opens `openapi.json`, supports edit/search,
  reports selections to Swift, accepts Swift commands, and stays responsive under
  the success criteria.

### Option C: Scintilla Native Wrapper

Wrap Scintilla for source editing.

Pros:

- Mature native code editor component with large-document and styling controls.
- Avoids WebView bridge cost.
- Strong fit for code/source mode, line numbers, folding, markers, and commands.

Cons:

- C/C++/Cocoa integration and packaging cost.
- Styling/theme/plugin surface must be bridged manually.
- Markdown WYSIWYG remains a separate editor.

Gate:

- Build a thin macOS wrapper that loads large JSON/CSV/text files, supports
  selection, edits, syntax off/on, line jumps, and native command routing.

### Option D: Custom Native Virtual Editor

Write SimpleLime's own source renderer.

Pros:

- Full control over file-backed virtual editing, rendering, annotations, and
  markdown/source-specific widgets.
- Can align perfectly with SimpleLime workflows.

Cons:

- Highest risk and longest timeline.
- Requires implementing document model, layout, selection, mouse handling,
  keyboard handling, IME, accessibility, undo, decorations, and scrolling.
- Easy to spend weeks rebuilding table stakes.

Gate:

- Only start after CodeMirror and Scintilla prototypes fail the product needs.

## Recommendation

Do not build more large editor features on the current source editor core until
the spike is complete.

Recommended order:

1. Instrument and benchmark the current STTextView path.
2. Prototype CodeMirror 6 source mode in WKWebView.
3. Prototype Scintilla only if the WebView cost or UX is unacceptable.
4. Choose native custom virtual editing only if both mature editor cores fail.

The likely target architecture is hybrid:

- Small and medium native-rich Markdown editing can stay on the existing
  STTextView/WYSIWYG path while it remains responsive.
- Source mode for code/JSON/YAML/large text should move to a viewport-native
  editor core.
- Large CSV/TSV table previews should stay virtualized and preview-only unless a
  separate spreadsheet editing model is built.

## Spike Deliverables

The next spike should produce these concrete artifacts:

- `script/editor_core_benchmark.sh`, a repeatable smoke command that generates
  large Markdown/CSV/plain-text fixtures, reports the OpenAPI fixture size when
  present, runs focused editor/large-file tests plus a headless
  `EditorCorePerformanceProbeTests` timing probe for virtual text indexing,
  visible-line reads, virtual CSV indexing/visible-row reads, and visible JSON
  syntax highlighting, builds the app, and can optionally relaunch the app with
  the OpenAPI fixture via `--launch-openapi`.
- `script/editor_live_latency_smoke.sh`, a no-screenshot GUI smoke command that
  launches the built app in safe mode, captures `EditorPerformance` info
  metrics from Unified Logging, sends a local automation insert, optionally
  drives AppKit key/selection input through System Events, and prints count,
  average, p95, and max durations for open/render/key/text/selection/syntax
  paths. Strict mode can fail when key/text p95 exceeds the 32 ms target.
- App-side signposts or logs for open, first render, key event, selection move,
  syntax pass, fold refresh, minimap refresh, and close. This is now wired
  through the `EditorPerformance` OSLog category, including
  `metric=<name> duration_ms=<value>` lines for smoke-script parsing.
- A fixture set covering:
  - `/Users/malikov/Downloads/openapi.json`
  - generated 16k-row CSV
  - 25k-line Markdown/plain text
  - a normal small Markdown document with comments and macros
- A compatibility matrix for every editor feature:
  - source editing
  - multi-selection
  - column selection
  - find/replace
  - comments
  - collaboration
  - macros/templates
  - folding
  - minimap
  - syntax highlighting
  - formatting commands
  - large-file search/jump, inline visible-line editing, keyboard row controls, and double-click chunk opening
  - single-line virtual replace/insert/delete for file-backed large text
  - read-only/temp mode
  - Current status: Create Editor Diagnostics now includes an Editor Core
    Compatibility table that maps the active buffer against the source editor
    feature contract, including the explicit blocker for full-file virtual
    editing in the large-file path.
  - Current status: large-file edit/save commands now share a
    `LargeFileEditingCapability` guard, and diagnostics include a dedicated
    Large-File Editing Capability section. That keeps read-only virtual
    browsing, editable exact chunks, extracted chunk scratches, and save-back
    metadata visibly distinct.
  - Current status: `LargeFileVirtualTextDocument` can replace, insert, and
    delete a single source line by line number through streamed byte-range
    rewrite, preserving LF/CRLF endings and rebuilding the sparse index. The
    virtual source view exposes single-line replacement as click-positioned
    inline row editing with Enter/Cmd-S commit and Esc/Cmd-. cancel, supports
    Up/Down/Enter/Delete row controls, exposes the line actions from the
    visible-row context menu, keeps double-click available for opening an exact
    bounded chunk, and the status-bar scratch action can now open a chunk around
    the first visible virtual line instead of the old loaded preview chunk.
    These are bridge primitives for a future virtual editor, not a complete
    editable full-file model.
  - Current status: `EditorCorePerformanceProbeTests` adds non-GUI timing
    evidence for the file-backed virtual render path and visible syntax path.
    It uses intentionally loose debug-build budgets so it catches obvious
    regressions without pretending to replace Instruments or manual cursor QA.
    The 2026-05-13 full-suite run measured roughly 42.34 ms for 25k-line text
    indexing, 4.79 ms for visible line reads, 388.93 ms for 16k/27-column CSV
    indexing, 3.19 ms for visible row reads, and 67.56 ms for 240 visible JSON
    line highlights.
  - Current status: the live latency smoke script provides the missing
    repeatable GUI-side collection path. It still depends on macOS
    Accessibility permission when the `EditorKeyDown` path is driven through
    System Events; without that permission it can still collect launch/open,
    render, syntax, and local automation store-update metrics.
    The 2026-05-13 run passed `--strict` on a small Markdown fixture with
    `EditorKeyDown` p95 at 2.926 ms and `EditorTextChange` p95 at 0.122 ms.
    The OpenAPI run opened `/Users/malikov/Downloads/openapi.json` with
    `EditorOpenFile` at 0.356 ms and `EditorInitialRender` at 15.252 ms, and
    the loopback automation bridge still answered `/health` after relaunching
    back to a clean safe-mode `Scratch 1`.
  - Current status: the live OpenAPI smoke found and fixed three non-obvious
    main-thread probes: encrypted-document detection no longer opens arbitrary
    non-`.slenc` files, the large-file virtual view no longer stats the source
    path while SwiftUI is laying out, and the status bar no longer reads Finder
    tags synchronously for large-file previews.
- Acceptance-gate diagnostics:
  - Current status: `SourceEditorAcceptanceGate` evaluates each selected buffer
    against concrete gates for large-file open policy, whole-file navigation,
    p95 typing latency, selection/autoscroll, bounded decorations, feature
    contract preservation, clear large-file policy, and full-file virtual
    editing. The report uses Pass/Warning/Manual/Fail rows so the current
    STTextView path cannot be mistaken for a proven long-term editor core.
- A decision with measured numbers and screenshots/video notes from the real app.

## Migration Plan

1. Add measurement first.
   - Keep the existing source editor.
   - Add signposts around update, highlight, fold, selection, visible range, and
     close paths.
   - Run the same test file before and after every editor-core change.
   - Capture live timing with:
     Instruments Points of Interest or
     `/usr/bin/log stream --style compact --level debug --type trace --predicate 'subsystem == "com.whitehappypony.SimpleLime" && category == "EditorPerformance"'`.

2. Isolate the source editor contract.
   - Define a single `SourceEditorAdapter` boundary for text, selection, commands,
     decorations, scroll-to-range, find hits, and diagnostics.
   - Move STTextView-specific behavior behind that boundary.
  - Current status: the first boundary is in place through
     `SourceEditorEngine`, `SourceEditorFeature`, `SourceEditorConfiguration`,
     `SourceEditorDecorations`, and `SourceEditorView`. The default active
     engine is still `.nativeSTTextView`, but `EditorWorkspaceView` now routes
     source editor configuration/decorations/callbacks through this contract
     instead of constructing `CodeEditorView` directly. An opt-in
     `.codeMirrorWebViewPrototype` engine now exists behind Settings -> Editor
     -> Source Engine; it loads CodeMirror 6 in a WebView with textarea
     fallback, reports text/multiple-selection/visible-line changes back to Swift,
     accepts multiple selection ranges from Swift, routes a small first set of
     WebView-native editor commands, receives
     normalized comment/collaboration decoration payloads for comment marks and
     collaborator range/caret rendering, and now has a store-level fallback for
     Markdown formatting plus common line/selection commands when an engine
     cannot perform the command itself. `EditorStore` can also recognize
     identical raw replacements across multiple selections from the WebView
     path and record one file-agnostic action macro step. Host-driven selection
     changes now ask CodeMirror or its textarea fallback to scroll the primary
     selection into view, which keeps find/jump/comment navigation from landing
     off-screen. The prototype also renders the configured column guide in both
     the CodeMirror view and textarea fallback. Focus/typewriter mode flags now
     reach the WebView path too: focus mode dims non-focused blocks, typewriter
     mode adds vertical scroll padding and centers host-driven selection
     scrolling, and the textarea fallback receives matching mode classes.
     Host-provided folded ranges now render as read-only replacement widgets in
     CodeMirror and as folded text in the textarea fallback, while the engine
     still does not claim full structured-folding parity because the native fold
     gutter/toggle UI has not been ported. Direct expand-line,
     split-selection, move-line, language-aware toggle-comment, and common text
     transform commands now run inside the CodeMirror view instead of falling
     back to the store. JSON minify/format and Markdown table formatting remain
     on the Swift fallback path because they share existing structured parsers.
     Mutating direct commands are rejected when the bridge is read-only because
     of buffer policy or folded display state.
     It is deliberately marked as a
     limited prototype until remaining macro parity, folding/minimap, and
     large-file virtual editing are proven.

3. Prototype the replacement behind a feature flag.
   - Start with plain/code source mode only.
   - Keep Markdown WYSIWYG and table previews unchanged.
   - Route command palette/menu commands through the adapter.
  - Current status: the CodeMirror 6 WebView prototype is selectable through
     the Source Engine setting while native STTextView remains the default, and
     `EditorStore` can execute Markdown/line command fallbacks for engines that
     do not implement every native editor command yet. The prototype also now
     receives source editor comment/collaboration decorations, renders them
     through CodeMirror marks/widgets, round-trips multiple selection ranges
     through the WebView bridge, and supports raw multi-cursor/multi-selection
     text edits being recorded as one file-agnostic action macro replacement
     when every selection receives the same replacement. It also scrolls
     host-driven selection updates into view for the CodeMirror and textarea
     fallback paths, renders the configured column guide, and bridges
     focus/typewriter mode state into CodeMirror theme/decorations plus textarea
     fallback classes. It also renders folded-range state from Swift as a
     read-only folded display without advertising full structured-folding
     feature support. Direct selection, move-line, language-aware
     toggle-comment, common text transform commands, and common Markdown
     formatting/snippet commands are now handled in WebView, and direct
     mutating commands respect the same read-only/folded guard as the editor
     state. This has only been covered by headless Swift contract tests,
     embedded-JS syntax validation, and safe-mode app launch verification so
     far.

4. Move integrations one by one.
   - Selection reporting.
   - Find/replace.
   - Comments/collaboration decorations.
   - Macros and text transforms.
   - Folding/minimap.
   - Large-file search/jump.

5. Retire the old path only when the feature matrix and latency gates pass.

## Stop Conditions

Stop hardening the current STTextView path if any of these remain true after the
instrumentation pass:

- p95 input latency stays above 32 ms on normal files.
- Any syntax language causes visible stalls on ordinary typing.
- Selection autoscroll or empty-area placement depends on AppKit quirks that
  cannot be made deterministic.
- Large-file source editing requires keeping full document text in a normal
  `STTextView`.

## References

- CodeMirror 6 System Guide, especially the data model and viewport sections:
  https://codemirror.net/docs/guide/
- Scintilla documentation, especially text retrieval/insertion, allocation,
  large-document, and styling options:
  https://scintilla.org/ScintillaDoc.html
- STTextView README:
  https://github.com/krzyzanowskim/STTextView
