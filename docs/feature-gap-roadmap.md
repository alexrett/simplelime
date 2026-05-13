# SimpleLime Feature Gap Roadmap

This roadmap groups the requested gaps into implementation tracks. It is meant to
stay close to the product surface, so each feature can later be split into small
repo issues or PRs without losing the original intent.

## Current foundation

- Scratch buffers, regular text files, folder catalog, tabs, search/replace,
  Markdown source/preview/WYSIWYG, syntax highlighting, comments/reminders,
  local-network sharing, collaboration, text transforms, minimap, focus and
  typewriter modes.
- Named workspaces for separating contexts such as work, personal, and hobbies,
  with each workspace restoring its own tab/window session and manual task
  board plus opened Documents folder root.
- AI panel through Agent Client Protocol with Copilot and Codex-compatible
  agents, plus HTTP providers for OpenAI-compatible chat-completions servers,
  Anthropic Messages, and Gemini generateContent.
- Finder Open With support for text files through the app bundle metadata.

## Track 1: Editor correctness and comfort

- Treat the text editor core as a first-class architecture track, not just a
  pile of UX fixes. The current STTextView bridge remains useful for the
  prototype, but it must prove low input latency, reliable cursor placement,
  selection autoscroll, bounded syntax highlighting, and safe large-document
  behavior before more features are built on top of it.
  - Editor hot-path stabilization slice shipped: regular edits no longer run
    synchronous full-document syntax highlighting. Rendering refreshes are now
    skipped unless syntax, font, language, comments/collaboration decorations,
    or focus dimming actually changed; syntax languages are highlighted through
    a short debounce, while plain text/CSV/TSV/image/PDF/hex/drawing modes avoid
    the syntax highlighter in the typing path. Shift-selection updates now
    explicitly scroll the active selection edge back into view. Ordinary clicks
    in empty editor space now place the caret at the nearest line end instead
    of falling back to the beginning of the document. Markdown/JSON/YAML fold
    gutter markers are now signature-gated and debounced after text edits
    instead of being reparsed synchronously on every SwiftUI update. Selection
    changes no longer clear/reapply focus dimming over the whole document when
    focus mode is unchanged or disabled, and text line ranges are cached between
    text mutations so visible-range, gutter, empty-area click, and column-cursor
	    paths do not repeatedly rescan the entire buffer. The cache is covered by a
	    25k-line regression, and visible-range calculation now guards invalid AppKit
	    visible rects instead of trapping. The menu and command palette can also
	    create an Editor Diagnostics scratch for the selected buffer, recording the
	    active render path, syntax/fold/minimap/focus state, loaded size, large-file
	    policy, and metadata-based risk flags before deeper Instruments work.
	  - Editor core decision record added in
	    `docs/editor-core-refactor-plan.md`: the app now has explicit acceptance
	    criteria, a comparison of STTextView hardening, CodeMirror 6 in WKWebView,
	    Scintilla, and a custom native virtual editor, plus migration gates for
	    choosing or rejecting the current editor core. A repeatable
	    `script/editor_core_benchmark.sh` smoke command now generates large
	    fixtures, runs focused editor/large-file/telemetry tests, prints the
	    `EditorPerformance` log stream command, and builds the app as the baseline
	    command for future editor-core changes. Source editor open/render/update,
	    key, text change, selection, syntax, fold gutter, minimap, and close paths
	    now emit signposts for Instruments/log-stream measurement.
  - Source-engine prototype slice shipped: Settings -> Editor now exposes an
    opt-in CodeMirror 6 WebView prototype behind the `SourceEditorAdapter`
    boundary while native STTextView remains the default. The prototype reports
    text, selection, and visible-line changes back to Swift and routes a small
    command set, giving the editor-core replacement path a real buildable
    target without claiming feature parity yet.
  - Source command fallback slice shipped: `EditorStore` now executes Markdown
    formatting, split/expand selection, move/delete/indent/outdent line
    commands, and language-aware line comments when an active source engine
    cannot perform a command itself. This keeps action macro replay and command
    palette behavior usable while the CodeMirror path is still incomplete.
  - Source decoration bridge slice shipped: the CodeMirror prototype receives
    normalized comment/collaboration payloads from `SourceEditorDecorations`
    and renders comment marks plus collaborator range/caret decorations inside
    the WebView path.
  - Source multiple-selection bridge slice shipped: the CodeMirror prototype now
    accepts multiple selection ranges from Swift, enables CodeMirror multiple
    selections, and reports the full selection range list back to `EditorStore`
    instead of collapsing everything to the first selection.
  - Raw multi-cursor macro capture slice shipped: `EditorStore` recognizes
    identical raw replacements across multiple selections from the CodeMirror
    path and records one file-agnostic `replaceSelection` action macro step.
  - Host-selection scroll bridge slice shipped: host-driven selection changes
    from find/jump/comment navigation now ask the CodeMirror path or textarea
    fallback to scroll the primary selection into view.
  - CodeMirror column-guide bridge slice shipped: the opt-in WebView prototype
    and textarea fallback render the same configured column guide as the native
    source editor.
  - CodeMirror focus/typewriter bridge slice shipped: the opt-in WebView
    prototype now receives the same focus/typewriter mode flags as the native
    source editor, dims non-focused blocks in focus mode, centers host-driven
    selection scrolling in typewriter mode, and applies matching fallback
    classes to the textarea path.
  - CodeMirror folded-range display bridge slice shipped: the opt-in WebView
    prototype now receives host-provided folded ranges and renders them as a
    read-only folded display, with textarea fallback folded text. It still does
    not claim full structured-folding parity because native fold gutter/toggle
    UI is not ported.
  - CodeMirror direct selection/line movement/comment command and read-only
    guard slice shipped: expand-line, split-selection, move-line up/down, and
    language-aware toggle-comment now execute inside the WebView bridge, while
    direct mutating commands are blocked whenever the CodeMirror state is
    read-only or showing host-provided folded ranges.
  - Remaining architecture decision: large-file source tabs are still a
    virtualized read-only full-file renderer plus editable bounded chunks, not a
    true virtual editable document model. Clicking a visible large-file line can
    now place a caret inside an inline one-line editor backed by streamed source
    rewrite, Enter/Cmd-S commits that one-line edit, Esc/Cmd-. cancels it,
    Up/Down moves the focused virtual row, Enter opens inline editing for the
    focused row, Delete routes through streamed line deletion, double-clicking a
    visible line opens that line's exact chunk for bounded editing, the status
    bar edit control opens the chunk containing the first visible virtual line
    after scrolling, `Cmd-S` save-back works for exact chunks, and streamed
    single-line virtual replace/insert/delete primitives can rewrite one source
    line by line number without loading the full file.
    Automation-driven block/range replace/insert/delete can rewrite multiple
    source lines through the same streamed byte-range path. The single-line
    primitive is exposed through inline row editing, the context menu, the menu,
    and command palette; single-line plus block/range edits are exposed through
    REST command endpoint, JSON-RPC, and newline-delimited socket frames so
    local voice/LLM controllers can use them without a modal prompt.
    Editing a full 20k-line JSON with normal cursor-level editing still needs
    either a virtual editable model or a different editor engine.
- Markdown list indentation, Shift-Tab outdent, context-aware straight quote
  auto-pairing, typographic dash highlighting, configurable column guides,
  read-only/temp modes, and the one-left/one-right-sidebar layout rule have
  shipped as focused editor-comfort slices.
- The UI now keeps one left sidebar function and one right sidebar function at
  a time so editor space remains usable.
  - Window chrome regression fixed: the app now centralizes `NSWindow`
    titlebar configuration, removes the native toolbar/title from the visible
    title area, observes later title reapplication, reapplies that configuration
    during SwiftUI updates, keeps native traffic-light buttons above full-size
    SwiftUI content, clamps the tab bar's traffic-light inset, and keeps the
    custom Chrome-style tab bar as the only visible header content next to the
    traffic-light buttons.
- Expand structured folding beyond the Markdown/JSON/YAML source-mode gutter
  controls into additional threaded formats.
- Improve autoformatters for JSON minify/pretty print and readable Markdown
  table alignment.
- Expand big-file handling beyond the bounded read-only preview into virtualized
  streaming and lazy rendering for full-file navigation.
  - Chunk navigation slice shipped: large files stay read-only/source-only, but
    the status bar can page first/previous/next/last through bounded chunks
    without loading the whole file.
  - Streaming line-jump slice shipped: large-file `:line`, deferred
    open-at-line references, and the status-bar line prompt scan newline byte
    offsets asynchronously, then open the chunk containing the target line.
  - Cached line-index slice shipped: the first line jump builds a sparse
    newline checkpoint index for the large file, and repeated jumps reuse the
    cache while invalidating it after chunk write-back or disk metadata changes.
  - Streaming search slice shipped: large-file previews can run an exact
    full-file byte search asynchronously, then jump to the chunk containing the
    match and select it without loading the full document into the editor.
  - JSON restore hardening shipped: complex text files use a smaller 16 KB
    preview chunk, the code/JSON threshold cannot be raised above the safe
    512 KB cap, and session restore skips stale persisted full text for large
    file-backed JSON/code buffers before SwiftUI can render it. Large-file
    preview tabs persist only metadata in session storage, then reload the
    bounded preview from disk on restore. Stale dirty/normal large JSON tabs are
    forced back into read-only preview mode and close without entering the
    unsaved-state confirmation flow. Heavy legacy buffers that still do need a
    close confirmation temporarily suspend the editor rendering behind the modal,
    keep quarantined heavyweight text out of SwiftUI published alert state, and
    omit the pending-close tab from session persistence until Cancel restores it,
    so the dialog remains responsive. Force Close Buffer is available from the
    File menu, command palette, and `Shift-Cmd-W` for a stuck selected tab, and
    local automation plus the installed `simplelime --force-close-path` launcher
    command can discard a stuck tab by absolute path, file name, or tab title
    without depending on the selected tab. A
    `--safe-mode`/`--simplelime-safe-mode` launch skips persisted window
    sessions entirely for recovery, then a normal persist can overwrite the bad
    restore state with a clean window. The installed `simplelime` launcher and
    local run script both pass the recovery flag through to the app. The local
    `--build-only` script warns when an old SimpleLime process is still
    running. The local `run` script now waits for the old process to exit before
    opening the fresh bundle, force-quitting only if the old app stays stuck.
  - Cancellable open slice shipped: background file-open and restored
    large-preview tasks are tracked and cancelled when their tab is closed, so a
    closed big JSON preview cannot later complete into stale UI state or surface
    a cancellation as an open-file error.
  - Editable chunk escape hatch shipped: the currently loaded large-file chunk
    can be opened as a normal scratch after stripping the preview marker, so the
    user can edit or save a bounded fragment without loading the full source
    file or risking truncated overwrite.
  - In-place chunk editing slice shipped: exact-boundary large-file chunks can
    be switched into an editable state directly in the preview tab; the marker
    is stripped, `Cmd-S` saves only that byte range back to the source file, and
    dirty in-place chunk edits block paging/close without explicit action.
  - Safe chunk write-back slice shipped: an exact-boundary editable chunk
    scratch can be saved back into the source file through a streamed temporary
    replacement, but only when the source file size still matches the file that
    produced the chunk. Other editable chunk scratches from the same source now
    keep their offsets and file-size metadata aligned after non-overlapping
    saves, while overlapping stale chunk scratches are disconnected from
    source write-back. Chunk source metadata now round-trips through both
    window-group and legacy single-session persistence paths, and dirty
    in-place chunk text is persisted as bounded session text instead of being
    mistaken for full-file content.
  - Virtual full-file render slice shipped: large file tabs now render the
    source through an AppKit `NSTableView`-backed full-file view that indexes
    newline offsets off the main thread, reads only visible lines from disk, and
    applies lightweight syntax highlighting per rendered line. The persisted
    buffer still stores bounded chunk metadata so close/session recovery stays
    cheap, while analysis can visually scan the entire file instead of only the
    current chunk.
  - Click-to-edit slice shipped: clicking a visible line in the virtual
    large-file source view jumps to that line, opens its exact bounded chunk in
    place, strips the preview marker, and keeps the existing `Cmd-S` byte-range
    save-back path for that chunk.
  - Virtual line editing slice shipped: the file-backed virtual text document
    can replace, insert, and delete one line by line number with a streamed
    temporary-file rewrite, preserve CRLF/LF endings, rebuild the sparse line
    index, and refresh the selected large-file preview around the edited line
    without loading the whole file. The same primitive is exposed through the
    File menu, command palette, REST command endpoint, JSON-RPC endpoint, and
    newline-delimited socket frames for local voice/LLM controllers.

## Track 2: File types, previews, and export

- Open all text-readable files through Finder Open With and normal open actions.
  - Open With slice shipped: the app bundle advertises broad document support
    including text/source/JSON/XML/Markdown, CSV/TSV, images, PDF, and generic
    data files; generic binary files fall back to read-only hex preview instead
    of unsafe text decoding.
- Expand binary wrappers beyond read-only image/PDF preview tabs, with images
  reusing SimpleShot-style inspection where practical.
  - Image inspection slice shipped: image preview tabs show pixel size, file
    size, color/alpha metadata, transparency checkerboard, fit-to-window, 1:1,
    zoom controls, Finder/default-app handoff, and SimpleShot handoff when
    installed while staying read-only.
- Add CSV/TSV table view as an alternate editor mode while preserving text
  editing.
  - Virtualized table slice shipped: CSV/TSV preview now uses an AppKit
    `NSTableView` bridge instead of thousands of SwiftUI cell views, with
    parser regressions covering a generated 16k-row CSV and the local buyers
    plan CSV fixture when present. Row and column caps are configurable in
    Settings.
  - Visible preview parser slice shipped: table rendering now stops after the
    rendered row/column window, reports approximate hidden rows/columns when it
    intentionally stops early, and avoids materializing every CSV cell in
    memory; regression coverage includes the local buyers plan CSV when present.
  - Large delimited virtual table slice shipped: when CSV/TSV files cross
    large-file mode, the table button renders a full-file virtual table backed
    by an off-main CSV/TSV record-offset index. The AppKit table reads visible
    rows from disk on demand, respects quoted newlines/escaped quotes/CRLF, and
    keeps configurable row/column caps without materializing every cell.
- Open unknown binary files as read-only hex previews instead of forcing them
  through text decoding.
- Export Markdown/text content to PDF, HTML, Word, and CSV-to-Excel.
  - Native Office slice shipped: Word export writes `.docx` OOXML packages
    with Markdown whiteboard widgets embedded as PNG media, and CSV/TSV Excel
    export writes `.xlsx` OOXML packages; the previous Office-compatible HTML
    generators stay available as compatibility helpers.
- Improve Save As with file type selection and smarter file or tab name
  suggestions.
  - AI naming slice shipped: the Save As accessory can ask the configured HTTP
    LLM for a concise file name, then sanitizes it and applies the selected file
    type extension.
- Add non-git file versioning as numbered copies such as `name.1`, `name.2`.
  - Backup-before-save slice shipped: File menu and command palette can create
    the next numbered backup from the current on-disk file, then save current
    edits back to the original path. This keeps the previous file state without
    enabling noisy timed snapshots.
- Reuse macOS Finder tags as document tags where file-backed buffers allow it.

## Track 3: Automation and timeline

- Expand macro recording beyond text edits, transforms, Markdown commands, and
  editor line commands if lower-level cursor/selection gestures need capture.
  - Cursor/selection slice shipped: recorded action macros capture coalesced
    selection moves before text edits, transforms, Markdown commands, or editor
    commands, then replay those selections in any buffer.
- Let recorded macros be pinned outside the macros panel as custom toolbar
  buttons.
  - First slice shipped: text and recorded action macros can be pinned from the
    Macros panel and replayed from status-bar buttons.
- Reuse macros as templates for common documents such as PRD, 1x1, and meeting
  notes.
  - Template fields slice shipped: text macros support reusable
    `{{Field:Default}}` placeholders, automatic Date/Time/DateTime values, and
    a fill-in dialog before insertion.
- Add editing statistics by day, week, month, year, unique files, scratches, and
  action types.
  - File/scratch split slice shipped: Stats separates unique documents into
    file-backed documents and scratch buffers across Today, 7 Days, 30 Days,
    and 365 Days summaries.
- Add timelog recording from app actions and macro events.
  - Timelog slice shipped: Stats stores a local Today Log with merged edit
    bursts, open/save/export entries, recorded/played macro events, macro
    counts, and per-entry durations where available. The Stats panel, command
    palette, and app menu can generate today's Markdown timelog as a scratch
    buffer for review, editing, or saving.
  - Frontmost app/window activity slice shipped: the Stats panel can start
    Activity Watch to record active app/window changes into the Today Log
    without enabling AI scans; Live Companion records the same activity while it
    watches active-app context. Activity Watch can keep writing local timelog
    entries even when Companion Window Context is disabled, and app/window
    entries are omitted from Companion prompts unless that context setting is
    enabled. These entries keep durations and stay out of unique document
    counts.
  - Final activity flush slice shipped: when Activity Watch, Live Companion, or
    system-context watching stops, the current frontmost app/window interval is
    closed into the Today Log instead of being dropped.

## Track 4: AI, voice, and companion workflows

- Add direct LLM provider integrations through HTTP APIs in addition to ACP.
  - First slice shipped: OpenAI-compatible, Anthropic Messages, and Gemini
    generateContent providers, each with separate settings.
- Expand companion mode beyond manual HTTP LLM scans into live watching of
  active work with comments, suggestions, and applicable edits in real time.
  - First live slice shipped: Live Companion can watch text edits, debounce an
    HTTP LLM companion scan, and surface applicable suggestions in the
    Companion panel.
  - Workspace context slice shipped: Companion scans now include compact context
    from open tabs, current comments, tasks, and today's local activity so
    suggestions can be prioritized by the work session without screen capture.
  - Frontmost-window context slice shipped: Companion prompts also include the
    current macOS frontmost application name, bundle identifier, and active
    window title when macOS exposes it, giving the LLM lightweight OS context
    without Accessibility permissions or screen capture. The context can be
    disabled from Settings.
  - Accessibility selected-text slice shipped: Companion can optionally include
    the active app's focused element role/title plus selected or focused text
    after the user enables the setting and grants macOS Accessibility access;
    this still avoids screen capture.
  - Active-window OCR slice shipped: Companion can optionally request macOS
    screen-recording access, capture the active app window with
    ScreenCaptureKit, run local Vision OCR on the image, and include only the
    recognized text in the HTTP LLM prompt;
    this is disabled by default and does not send screenshots to the provider.
  - Active-app watch slice shipped: Live Companion now polls a compact
    frontmost app/window/Accessibility/OCR-context fingerprint and debounces a
    scan when it changes, so external app selection or visible text changes can
    trigger suggestions without sending screen images.
  - Live editor-context slice shipped: enabling Live Companion now also
    debounces scans after tab changes, selection changes, and task/comment
    updates, and prompts include the active cursor or selected text line.
  - Suggestion application slice shipped: Companion edits/comments resolve exact
    anchors, normalized whitespace, and unique fuzzy token matches while
    rejecting ambiguous anchors.
  - Patch application slice shipped: Companion can now return bounded
    unified-diff `patchText` suggestions for multi-edit changes; patches apply
    only when every old/context block matches the current document uniquely.
- Add scribe mode for regular input/output from meeting apps, with optional voice
  control.
  - Native slice shipped: Voice Scribe right panel uses macOS Speech plus
    microphone capture, ScreenCaptureKit system-audio capture, or combined
    meeting-audio capture to append final transcript lines into Markdown
    transcript scratches, with optional wake-phrase voice commands routed
    through the local automation command handler.
  - Meeting auto-detect slice shipped: the Auto source detects known running
    meeting apps such as Zoom, Teams, FaceTime, Slack, Discord, Webex, and
    Google Meet wrappers, plus browser windows whose titles expose Google Meet,
    Teams, Zoom meeting, Webex, Slack huddle, or Discord voice context. It also
    inspects all tab URLs for every running supported scriptable browser when
    macOS Automation permission allows it, so Google Meet, Teams, Zoom, Webex,
    Slack huddle, and Discord call URLs can be detected even when the window
    title is generic or the meeting is in a non-frontmost browser. It switches to
    combined mic+system capture when detected, names the
    transcript after the app, and falls back to microphone capture when no
    meeting app is found.
  - Combined capture resilience slice shipped: meeting capture keeps the
    remaining recognizer alive if only microphone or system-audio capture fails,
    shows a degraded-capture status in the panel, and reports an error only
    when every capture source has failed.
  - Auto-start watcher slice shipped: the opt-in Auto Meeting Scribe toggle in
    the Scribe panel and Settings -> Automation opens the scribe panel, watches
    for detected meeting apps, and starts an Auto source transcript when a
    meeting appears.
  - Large-file voice-command slice shipped: wake-phrase commands can now replace,
    insert, or delete one large-file source line by spoken line number, for
    example `SimpleLime replace large file line 42 with edited row`.
- Keep the voice and scribe layer pluggable through local HTTP, RPC, or sockets
  so it can run as an external service.
  - HTTP/RPC/socket slice shipped: loopback automation bridge on
    `127.0.0.1:48777`, with REST endpoints `/v1/scribe` and `/v1/command`,
    JSON-RPC 2.0 over `/v1/rpc`, and newline-delimited raw socket JSON frames
    for transcript append/new-buffer ingestion and local voice/workflow
    commands such as toggling Companion, Tasks, Terminal, Macros, Stats, saving,
    opening a new scratch, closing or force-closing a selected stuck tab,
    showing the command palette, inserting dictated text, and replacing,
    inserting, or deleting one selected large-file source line by line number.
- Keep translation as an AI workflow unless there is a reason to build a
  dedicated translation layer.
  - First slice shipped: Translate Selection replaces selected text through the
    configured HTTP LLM provider and supports multiple selections.

## Track 5: Planning and PO mode

- Add a global tasks/Kanban surface, later extended per workspace.
  - Shipped: manual tasks can be created as Mac-wide global tasks or
    workspace-local tasks; global tasks sync across windows and follow workspace
    switches, while detected tasks still come from each workspace's open buffers.
- Allow tasks to be created manually and suggested from opened files.
  - Folder task slice shipped: the Tasks board now scans Markdown checklist
    items from the opened Documents folder asynchronously, avoids duplicating
    files already open in tabs, can open a catalog task at its source line, and
    can update the checklist marker back to disk.
  - Natural marker slice shipped: open buffers and opened Documents folders now
    detect TODO/FIXME/ACTION/FOLLOW-UP/NEXT-STEP style task lines in text/code
    files; changing their board status converts the line to a Markdown
    checklist item.
  - Plain-language inference slice shipped: the same scanner now detects
    conservative action lines such as `we need to`, `should`, `please`,
    `next step`, and Russian `нужно/надо/необходимо/следует` phrasing while
    skipping code fences, questions, and already-marked tasks.
  - HTTP LLM inference slice shipped: the Tasks panel can explicitly ask the
    configured HTTP LLM provider to extract deduplicated manual tasks from open
    text tabs, using a bounded context and JSON-only task response.
  - Auto HTTP LLM inference slice shipped: Settings can enable opt-in debounced
    task inference after opening or editing the selected text tab; automatic
    runs stay quiet and do not force-open the Tasks panel.
  - PO gap task slice shipped: PO Mode gaps and open questions can be promoted
    into deduplicated workspace To Do tasks with source file and line context.
- Add a lightweight drawing/whiteboard surface for rough planning sketches,
  later expandable toward richer Miro-style boards.
  - First slice shipped: text-backed `.sldraw` whiteboard buffers with pen
    colors, stroke width, undo, clear, normal tab persistence, and regular file
    open/save support.
  - Second slice shipped: stickers, text boxes, simple shapes, connector lines
    with optional arrows, group/ungroup containers with live bounds, zoom
    controls, SVG/PNG export, copy-as-PNG, and Markdown `sldraw` widgets that
    export as inline SVG in HTML and as embedded images in native Word/PDF.
  - Layout slice shipped: selected groups can align member objects left,
    center, right, top, middle, or bottom while keeping the group bounds synced.
  - Settings slice shipped: configurable grid visibility/density plus default
    sticky fill, connector arrows, and connector routing for new board items.
  - Routing slice shipped: visible minor/major board grid plus object-bound
    connector endpoints with straight, smart shortest orthogonal,
    horizontal-first, and vertical-first routing shared by canvas, SVG, and PNG
    export.
  - Interaction slice shipped: select-drag moves board items, selected items can
    be duplicated, stickers start blank, connectable objects expose four visible
    anchor points, connector endpoints bind to explicit anchors, crossing
    connectors render bridge jumps, and the canvas follows the editor background.
  - Multi-select slice shipped: dragging on empty canvas creates a marquee
    selection, grouped selections can be moved together, grouped explicitly, and
    duplicated while connector endpoints between duplicated objects are remapped
    to the new copies.
- Expand PO mode beyond generated document-folder briefs into an interactive
  drilldown surface with live mind maps and deeper feature-doc analysis.
  - Interactive slice shipped: PO Mode right panel with summary metrics,
    document/headings mind map, task Kanban, gaps, feature-doc table, search
    index filtering, drilldown links to file lines, and Markdown brief export.
  - AI interpretation slice shipped: PO Mode can send the generated folder
    report through the configured HTTP LLM provider and show a product reading,
    gaps, risks, and next actions alongside the offline analysis.
  - Task promotion slice shipped: PO Mode can add its gaps/open questions into
    the workspace task board so analysis results are follow-up work, not only
    report text.
- Expand named workspaces with richer per-workspace settings, task scopes, and
  document roots.
  - Document-root slice shipped: each workspace persists its opened Documents
    folder root, restores it when switching/relaunching, and propagates root
    changes across windows in the same workspace.

## Track 6: Development workflows

- Detect when a file belongs to a git repository and expose commit actions.
- Add a diff checker for two files.
  - File picker slice shipped: Diff can compare the current tab with the
    previous tab or with a chosen text file from the menu/command palette.
  - Bounded preview slice shipped: oversized text inputs now produce an
    explicitly labeled diff preview capped at the inline diff limits instead of
    blocking the workflow; large file paths are read by prefix so the app does
    not load multi-megabyte comparison files just to show a bounded preview.
  - Large-file source slice shipped: file-backed large-file preview tabs can now
    be compared against the previous tab or a chosen file by reading a bounded
    preview from each source path instead of diffing the visible chunk; only
    synthetic large previews without a source path still report an actionable
    error.
- Add terminal support as a bottom tab bar, opening new terminals in the selected
  file or folder location.
  - Interrupt slice shipped: the active terminal tab can send `Ctrl-C` into the
    PTY without closing the tab, and a real PTY regression test verifies that a
    foreground command is interrupted and the shell remains usable.
  - Recovery slice shipped: the active terminal tab can reset the local terminal
    grid and run `stty sane; reset` after a broken TUI/agent command, with real
    PTY coverage proving the shell remains usable afterward.
  - Restart slice shipped: the active terminal tab can stop the current PTY and
    start a fresh shell in the same tab and working directory, while ignoring
    late exit callbacks from the old process so a restarted terminal is not
    marked dead by the previous TUI/agent command.
  - Shell metadata slice shipped: SwiftTerm title and OSC current-directory
    callbacks update the tab title and header path instead of leaving terminal
    chrome stuck at launch-time values after `cd` or prompt updates.
  - Locale slice shipped: terminal settings now include a configurable UTF-8
    locale fallback used to normalize `LANG`, `LC_CTYPE`, and non-UTF8 `LC_ALL`
    for zsh/oh-my-zsh/TUI shells.
  - PTY size slice shipped: SwiftTerm view dimensions are synchronized to the
    child PTY on attach/update and size changes, with a real `stty size`
    regression proving the shell receives the updated rows/columns.
  - Bounded replay slice shipped: raw terminal replay data is capped and, after
    truncation, starts with a terminal reset sequence so switching tabs after a
    noisy TUI/agent command does not replay from the middle of an ANSI state.
  - Backpressure slice shipped: PTY output is delivered on a dedicated serial
    queue instead of the main queue, SwiftTerm UI feed calls are batched, and a
    real PTY regression drains 180 KB of noisy output before proving the shell
    exits cleanly.
  - Real top regression shipped: a PTY test starts `/usr/bin/top`, waits for
    output through the terminal pipeline, interrupts it, then proves the same
    shell still accepts and runs a follow-up command.
  - Agent-style TUI smoke slice shipped: a deterministic zsh-backed interactive
    TUI test enters alternate screen, hides and restores the cursor, changes the
    terminal title, clears and cursor-addresses the grid, emits UTF-8/Cyrillic
    output, waits for user input, exits back to the main screen, and proves a
    follow-up shell command still runs.
  - Real curses TUI smoke slice shipped: when `python3` is available, a real
    Python curses full-screen program enters the terminal grid, renders
    Cyrillic text, consumes key input, exits cleanly, and proves the same zsh
    PTY still runs a follow-up command.
  - Conditional htop smoke slice shipped: when `htop` is installed, a real htop
    full-screen session starts in zsh, exits on `q`, and proves the same PTY
    still runs a follow-up shell command.
  - TTY-backed diagnostic slice shipped: the in-app diagnostics command now runs
    against the real PTY stdin for `stty size`, sends the diagnostic shell
    payload in small chunks so a damaged PTY state does not corrupt the heredoc,
    and, when `python3` is available, executes a small curses full-screen smoke
    before proving the shell still accepts a follow-up command.
- Make settings flexible enough to tune editor, performance, AI, terminal, and
  workflow behavior without hunting through a long panel.
  - Search slice shipped: Settings now has a searchable section catalog for
    editor, performance, whiteboard, storage, AI Agents, terminal, and
    automation controls, with punctuation/case normalization and no-match
    feedback.

## Track 7: Security, sync, and collaboration

- Support encryption for scratches and saved files with password protection.
  - First slice shipped: `.slenc` encrypted text documents, encrypted open/save,
    encrypted numbered copies, and plaintext Save As escape hatch.
- Add Touch ID unlock where macOS APIs allow it.
  - First slice shipped: optional Keychain storage guarded by system user
    presence for Touch ID unlock.
- Use iCloud Drive or iCloud document storage for device sync where the user
  chooses a synced location.
  - First slice shipped: Settings exposes a configurable app data root with an
    iCloud Drive shortcut and merge-migrates existing SimpleLime app data;
    newer target-side files are preserved while missing and older files are
    filled from the previous root, and divergent losing-side files are kept as
    timestamped conflict copies. Sessions, workspaces, tasks, comments, macros,
    usage stats, and agent buffer mirrors now resolve through the shared storage
    root. Switching roots reloads the workspace/session state immediately
    instead of requiring an app restart.
  - External-change slice shipped: the workspace store keeps a bounded snapshot
    of the app-data root, polls for synced file changes, reloads clean sessions
    automatically, and preserves the current window when local in-memory edits
    have not yet reached the persisted session. Settings exposes the current
    sync status and a Check Now action for manual verification.
- Add a self-hosted microserver for shared links and internet collaboration.
  - First slice shipped: Devices -> Internet Relay starts an in-app
    self-hosted HTTP relay, creates `simplelime://collab?...` links, accepts
    relay links, and reuses the existing collaboration patch/selection payloads
    through the relay.
  - Standalone slice shipped: `SimpleLimeRelay` can run the same relay protocol
    outside the GUI process with configurable bind host, port, room, token, and
    public URL, then print a guest `simplelime://collab?...` link.
  - Auth hardening slice shipped: SimpleLime relay clients now send the room
    token in an `Authorization: Bearer` header instead of repeating it in HTTP
    request URLs, while both in-app and standalone relays keep legacy
    `?token=...` compatibility.
  - Parser hardening slice shipped: both in-app and standalone relay parsers
    cap header/body size, reject oversized incomplete requests, and handle
    duplicate query items without crashing.
  - Storage hardening slice shipped: both relay implementations trim retained
    events by count and encoded byte budget so large payload history cannot grow
    without bound.
  - Idle cleanup slice shipped: both in-app and standalone relay history is
    cleared after a configurable idle timeout; the standalone server exposes it
    as `--room-idle-timeout SECONDS`.
  - Public URL hardening slice shipped: standalone relay links reject non-local
    `http://` public URLs by default, allow local development HTTP hosts, and
    require an explicit `--allow-insecure-public-url` override for insecure
    external links.

## First implementation slice

- Markdown list Tab / Shift-Tab behavior.
- Context-aware quote auto-pairing.
- Visible typographic dash highlighting.
- Configurable editor column guide.
- Numbered non-git version copies for file-backed buffers.
- Diff checker between the current tab and previous tab or a chosen text file.
- JSON pretty-print and minify commands.
- Markdown table formatting command.
- Git repository detection plus commit-current-file command.
- CSV/TSV table preview while keeping text editing as the source of truth.
- Per-buffer read-only and temporary save guards.
- Mutually exclusive left and right sidebar surfaces: Documents versus Outline
  on the left, and one workflow panel at a time on the right.
- Structured source folding for Markdown sections, JSON containers, and YAML
  indentation blocks, with gutter toggles and folded source held read-only until
  expanded.
- Save As file type selection plus deterministic filename suggestions from the
  tab title or document heading, with optional AI file naming from the configured
  HTTP LLM provider.
- Read-only image, PDF, and unknown-binary hex preview tabs from regular macOS
  Open/Open With, with image metadata inspection and zoom controls for image
  tabs.
- Task board with global and workspace-local manual tasks, detected Markdown
  checklist and TODO/FIXME/ACTION-style task lines from open buffers/opened
  folders, and optional manual or opt-in automatic HTTP LLM task inference from
  open text tabs.
- PO mode for opened document folders: interactive mind-map outline, task
  Kanban, gap/open-question scan, feature-doc table, search index filtering,
  drilldown links to file lines, optional HTTP LLM interpretation, and Markdown
  brief export.
- PDF, HTML, and native Word `.docx` export for text/Markdown/table buffers,
  plus native Excel `.xlsx` export for CSV/TSV buffers.
- Local usage stats and lightweight Today Log for edits, opens, saves, exports,
  macro events, active editing time, frontmost app/window intervals, per-entry
  durations, and unique documents.
- Persistent text macros/templates with built-in PRD, 1x1, and meeting notes
  snippets, reusable template fields, automatic date/time values, and custom
  macros from selected text.
- Recorded action macros that persist and replay cursor/selection moves, text
  edits, text transforms, Markdown commands, and editor line commands in any
  file.
- Pinned macro buttons for frequently used text templates or recorded action
  macros.
- Text-backed drawing boards saved as `.sldraw`, with a native gridded canvas,
  configurable grid/default sticky/connector behavior, pen colors, stroke
  width, blank stickers, movable/duplicable items, text, simple shapes,
  explicit four-point object anchors, object-bound smart connectors/arrows with
  crossing bridge jumps, grouping/ungrouping, group member alignment with live
  bounds, zoom, undo, clear, SVG/PNG export, copy-as-PNG, and Markdown `sldraw`
  widgets that render in preview and exports.
- Finder tag display and add/clear actions for file-backed buffers.
- HTTP LLM providers for OpenAI-compatible, Anthropic Messages, and Gemini
  generateContent APIs, each with configurable base URL, API key, model, and
  temperature.
- Companion panel that scans the current buffer plus compact workspace and
  frontmost macOS app/window context through the HTTP LLM provider, can
  live-watch debounced edits, and can apply anchored suggestions as edits or
  document comments.
- Translate Selection command that uses the configured HTTP LLM provider and
  replaces one or more selected ranges in place.
- Voice Scribe panel for microphone, system-audio, or combined meeting-audio
  transcript capture into Markdown scratches, with opt-in Auto Meeting Scribe
  meeting-app watching plus wake-phrase commands routed through the local
  automation command handler.
- Loopback local automation bridge for external scribe and voice-control
  helpers, with REST, JSON-RPC, and raw socket JSON frame transports for
  transcript ingestion, editor commands, and streamed large-file
  single-line/range/block edits.
- SwiftTerm-backed bottom terminal panel with multiple tabs and configurable
  shell path/`TERM`/UTF-8 locale fallback and PTY size synchronization, opening
  shells in the selected file folder or the opened folder root; shell
	  title/current-directory callbacks update the tab and path,
	  shell output is rendered through a VT/xterm terminal grid instead of a plain
	  text log, with raw alternate-screen sequences preserved for full-screen TUIs
	  plus explicit interrupt/reset controls for long-running or broken terminal
	  states, a built-in diagnostic smoke command for UTF-8/color/title/cursor and
	  alternate-screen behavior, and real PTY coverage for interrupting `top`,
	  opening/leaving real Vim, interrupting real Claude Code, restarting after
	  real Codex CLI, real Python curses full-screen entry/input/exit, plus an
	  agent-style interactive TUI and conditional real htop coverage without
	  losing shell usability.
- Large text files open through a virtualized read-only full-file renderer with
  lazy newline indexing, off-main visible-range prefetch, and lightweight syntax
  highlighting, while the status bar still provides bounded chunk paging,
  full-file exact search that jumps to matching chunks, cached sparse line
  indexes for repeated `:line` jumps, inline single-line editing with keyboard
  row controls, double-click and visible-line chunk opening,
  editable scratch extraction for the current chunk, safe source write-back for
  exact-boundary chunks when the source file has not changed, and cross-scratch
  offset maintenance after non-overlapping chunk saves. Rendered previews,
  WYSIWYG, focus mode, and minimap stay disabled for performance. Saving stays
  blocked until an exact bounded chunk is explicitly opened for editing so
  truncated chunks cannot overwrite the original file.
- Password-protected `.slenc` encrypted documents, with encrypted open/save,
  encrypted numbered copies, and optional Touch ID-backed Keychain unlock.
- Configurable app data root for local or iCloud Drive-backed sync, covering
  sessions, workspaces, comments, task boards, macros, usage stats, and agent
  buffer mirrors, with merge migration, conflict copies, and immediate workspace
  reload after switching roots.
- Named workspaces with create, rename, switch, and persisted independent
  tab/window sessions, manual task boards, and document catalog roots.
- Self-hosted collaboration relay links backed by an in-app HTTP relay for
  internet collaboration when the host Mac and relay port are reachable, with
  bearer-token relay auth, bounded request parsing, and byte-budgeted event
  history.
- Standalone `SimpleLimeRelay` server package for hosting collaboration links
  outside the GUI app when a reachable self-hosted process is preferable, with
  `https` required for non-local public share links unless explicitly
  overridden.
- Relay HTTP requests use bearer-token authorization headers for current
  clients, with query-token fallback only for legacy compatibility.
