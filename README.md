# SimpleLime

Scratch-first text editor for macOS. It keeps temporary notes alive across app restarts, opens normal text files and folders, has line numbers, Markdown preview/WYSIWYG editing, syntax highlighting, search/replace, comments, local-network sharing/collaboration, text transforms, and AI assistance through Agent Client Protocol or HTTP LLM APIs.

![SimpleLime](screenshots/app.png)

## Why?

Sublime is still great as a place to dump temporary text, but I wanted a smaller native macOS editor focused on scratch buffers: quick notes, copied snippets, drafts, Markdown, and files that should survive a reboot even before they are saved.

SimpleLime is not trying to replace a full IDE. It is a fast working notebook with editor habits I use every day.

## Features

- Restored scratch buffers that survive app restarts
- Open and save regular text files
- Open a folder as a document catalog sidebar
- Large text files open in a virtualized full-file renderer with lazy line indexing, off-main visible-range prefetch, visible-row syntax highlighting, click-positioned inline single-line editing with `Enter`/`Cmd-S` commit and `Esc`/`Cmd-.` cancel, Up/Down/Enter/Delete keyboard row controls, and context-menu single-line replace/insert/delete actions backed by streamed byte-range rewrites, while the lightweight chunk state remains available for status-bar paging, repeated `:line`/status-bar line jumps, full-file exact search, Force Close Buffer recovery for stuck tabs, double-click chunk opening, one-click exact-boundary chunk editing with `Cmd-S` byte-range save-back, and scratch extraction for saving the current chunk elsewhere; other open chunk edits from the same file are shifted after non-overlapping saves or disconnected when their original range overlaps the saved edit, while expensive rendered previews, WYSIWYG, minimap, and focus mode stay disabled
- Open image and PDF files as read-only preview tabs, with image inspection for pixel size, file size, color/alpha, fit-to-window, 1:1, zoom, Finder/default-app handoff, and SimpleShot handoff when installed
- Unknown binary files open as read-only hex previews instead of being forced through text decoding
- Sidebars stay usable: one left surface (Documents or Outline) and one right surface (AI, Companion, Comments, Tasks, Stats, Macros, or Devices) can be open at a time
- CSV and TSV files can stay editable as text while rendering a table preview split with configurable row and column caps; normal previews stop after the rendered window, while large CSV/TSV files use a full-file virtual table index and read visible rows from disk instead of materializing the whole table
- Chrome-style tabs in the window title area
- Always-on line numbers and current-line highlight
- Soft wrap by default
- Configurable column guide for fixed-width writing and style limits
- Markdown-aware syntax highlighting for source mode, including fenced code blocks without bleeding Markdown styles across fences
- Syntax highlighting for Swift, JavaScript, TypeScript, JSON, HTML, CSS, Python, Ruby, Go, Rust, shell, and Markdown
- Visible highlighting for typographic dashes such as en dash, em dash, and minus
- Markdown WYSIWYG editing plus source preview with table controls, block-source editing for code fences, Mermaid, math, HTML/media and image markdown, paste/drop image insertion, local/remote images, reference links/images, autolinks, safe inline HTML/media blocks, offline Mermaid and math fallbacks, math blocks, TOC, callouts, front matter, footnotes, outline navigation, heading filter, Markdown formatting commands, nested lists, list continuation, Tab/Shift-Tab list indentation, and context-aware smart bracket/quote pairs
- Find, replace, regex search, match case, whole word, find/replace in tabs and opened folders, select all matches
- Multi-cursor editing
- Sublime-style selection and line commands: add next occurrence, split selection into lines, expand selection to line, column cursors, move/delete/indent/comment lines
- Sublime-style minimap with click-to-line navigation
- Structured source folding for Markdown sections, JSON containers, and YAML indentation blocks, with gutter toggles and folded buffers held read-only until expanded
- Focus mode and typewriter mode for long writing sessions
- Command palette with command search, fuzzy file navigation for the opened folder, and `:line` navigation
- Text transforms: uppercase, lowercase, title case, swap case, reverse selection, duplicate line or selection, sort lines, unique lines, trim trailing whitespace, join lines, and Markdown table formatting
- JSON pretty-print and minify transforms
- Document comments stored outside the text file, with source/WYSIWYG highlights, a comments sidebar, context-menu insertion, resolve/delete, and reminder notifications
- Task board with Mac-wide global manual tasks, workspace-local manual tasks, automatically detected Markdown checklist items, TODO/FIXME/ACTION-style task lines, plain-language "need/should/please/нужно" action lines from open buffers and opened folders, plus optional manual or opt-in automatic HTTP LLM task inference from open text tabs
- PO mode for an opened documents folder: interactive mind-map outline, task Kanban, gap/open-question scan, feature-doc table, search index, drilldown links, deduplicated gap-to-task promotion, optional HTTP LLM interpretation, and Markdown brief export
- Local usage stats and lightweight Today Log for edits, opens, saves, exports, macros, active editing time, unique documents, unique file-backed documents, scratch buffers, and optional Activity Watch or Live Companion frontmost app/window activity entries with flushed durations when watching stops; Activity Watch can record locally without enabling Companion prompts, and the app/window entries stay out of LLM context unless Companion Window Context is enabled
- Persistent text macros/templates with built-in PRD, 1x1, and meeting notes snippets, reusable `{{Field:Default}}` template prompts, automatic date/time fields, and custom macros from the current selection
- Recorded action macros that capture cursor/selection moves, text edits, text transforms, Markdown commands, and editor line commands, then replay them in any file
- Pinned macro buttons in the status bar for frequently used text templates or recorded action macros
- Text-backed drawing boards saved as `.sldraw`, with configurable interface-colored planning grid/default sticky/connector behavior, marquee multi-select, movable and duplicable stickers/shapes/text, explicit four-point connector anchors, smart connectors/arrows with bridge jumps at crossings, selected-item grouping/ungrouping, group member alignment with live bounds, zoom, SVG/PNG export, and copy-as-PNG
- Markdown whiteboard widgets through fenced `sldraw` blocks, exported as inline SVG in HTML, embedded images in Word/PDF, and regular preview widgets in the editor
- SwiftTerm-backed bottom terminal panel with tabs, configurable shell path, `TERM`, and UTF-8 locale fallback, truecolor PTY environment normalization and PTY size synchronization for zsh/oh-my-zsh/TUI tools, each tab starting in the selected file folder or opened folder root, with shell title/current-directory tracking, VT/xterm rendering for alternate-screen TUIs, real PTY regression coverage for interrupting `top`, opening and leaving real Vim, interrupting real Claude Code, restarting after real Codex CLI, an agent-style interactive TUI, real Python curses full-screen TUI entry/input/exit, conditional real `htop` coverage when installed, and a TTY-backed curses diagnostic, plus interrupt, reset, restart, and built-in diagnostics for long-running or broken terminal states
- Font size controls
- AI chat per tab with multiple sessions
- ACP integration for Copilot and configurable Codex-compatible agents
- HTTP LLM providers for OpenAI-compatible chat completions, Anthropic Messages, and Gemini generateContent APIs
- Companion panel that can manually scan or live-watch the current document, selection, tab/task/comment context, recent local activity, frontmost macOS app/window context, opt-in Accessibility selected text, and opt-in ScreenCaptureKit/Vision OCR text from the active window with the HTTP LLM provider, then turn suggestions into exact edits or anchored document comments and reflect app/window changes in the Today Log
- Translate Selection command backed by the configured HTTP LLM provider
- Voice Scribe panel for microphone, system-audio, or combined meeting-audio transcription into Markdown transcript scratches, with auto-detection for native meeting apps and browser meeting windows, an opt-in Auto Meeting Scribe watcher, and wake-phrase voice commands routed through the local command handler
- Loopback local automation bridge for external scribe, voice-control, and workflow helpers
- Local network device sharing with trusted SimpleLime peers
- P2P collaborative editing with invited peers: each Mac keeps its own local copy, changes sync as text patches, remote cursors/selections are shown in source and WYSIWYG, and anyone can leave without closing the document
- Self-hosted collaboration relay links for internet collaboration when the host Mac is reachable, with bounded request parsing, bounded event history, bearer-token relay auth, and HTTPS-required public standalone links by default
- Named workspaces for separating work, personal, hobby, or custom contexts, each with its own restored tab/window session, workspace-local manual task board, shared global task board, and document catalog root
- Configurable app data root with an iCloud Drive shortcut; switching roots merge-migrates existing app data, keeps conflict copies for divergent files, reloads workspaces immediately, periodically notices external app-data changes so clean sessions can reload synced state without an app restart, and exposes a Settings check/status for manual sync verification
- Searchable Settings surface for quickly filtering editor, performance, whiteboard, storage, AI, terminal, and automation controls, including an opt-in experimental source-engine picker for the CodeMirror 6 WebView prototype while native STTextView remains the default
- Independent window tab groups
- Move tabs between windows or open a copy of the current tab in a new window
- Per-buffer read-only and temporary save guards for editing without overwriting the source
- Password-protected `.slenc` encrypted documents, with normal saves preserving encryption and optional Touch ID-backed Keychain unlock
- Numbered non-git version copies for file-backed buffers, plus save-with-numbered-backup before overwriting
- Unified diff generation between the current tab and the previous tab, or between the current tab and a chosen text file, including bounded source-file diffs for file-backed large-file preview tabs
- Git repository detection for file-backed buffers with a commit-current-file action
- Finder tag display plus add/clear actions for file-backed buffers
- PDF, HTML, native Word `.docx` export for text, Markdown, and table documents, plus native Excel `.xlsx` export for CSV/TSV
- Finder Open With support for text, source, CSV/TSV, image, PDF, and generic data files with safe binary previews
- Save As suggests a clean file name from the tab title or document heading, can ask the configured HTTP LLM for an AI name, and lets you choose the target file type
- `simplelime` command-line launcher when installed through Homebrew

## Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘N` | New scratch buffer |
| `⌘⇧N` | New window |
| `⌘⌥N` | Move current tab to new window |
| `⌘O` | Open file |
| `⌘⇧O` | Open folder |
| `⌘S` | Save |
| `⌘W` | Close tab |
| `⌘⇧W` | Force close selected tab |
| `⌘F` | Find |
| `⌘R` | Find and replace |
| `⌘G` / `⌘⇧G` | Find next / previous |
| `⌘⇧F` | Find in files |
| `⌘⇧R` | Replace in files |
| `⌘⇧P` | Command palette: commands, folder files, and `:line` |
| `⌘D` | Add next occurrence |
| `⌘⌥G` / `⌘⌥⇧G` | Add next / previous occurrence |
| `⌘⌥L` | Select all matches |
| `⌘L` | Expand selection to line |
| `⌘⇧L` | Split selection into lines |
| `⌘⇧D` | Duplicate line or selection |
| `⌘J` | Join lines |
| `⌘]` / `⌘[` | Indent / outdent lines |
| `⌘/` | Toggle Markdown source/WYSIWYG; toggle line comment in non-Markdown files |
| `⌘⌥C` | Add comment to selected text |
| `⌘⌥↑` / `⌘⌥↓` | Move line up / down |
| `⌃Tab` | Next tab |
| `⌃⇧Tab` | Previous tab |
| `⌘+` / `⌘-` | Increase / decrease font size |
| `⌘⌥Z` | Toggle word wrap |
| `⌘⌥1` | Markdown source mode |
| `⌘⌥2` | Markdown source + preview split |
| `⌘⌥3` | Markdown WYSIWYG mode |
| `⌘⌥P` | Toggle rendered preview for Markdown, CSV, and TSV |
| `⌘⌥O` | Toggle Markdown outline |
| `⌘⌥E` | Toggle Markdown WYSIWYG mode |
| `⌘⌥D` | Toggle documents sidebar |
| `⌘⇧T` | Toggle tasks |
| `⌘⇧J` | Toggle terminal |
| `⌘⌥4` | Toggle minimap |
| `⌘⌥F` | Toggle focus mode |
| `⌘⌥T` | Toggle typewriter mode |
| `⌘⇧I` | Toggle AI panel |
| `⌘⇧K` | Show network devices |

## Comments and Reminders

Comments are stored separately from the edited document, so they can mark up a draft without changing the source text. They work in source mode and WYSIWYG mode, highlight the commented range, and appear in the comments sidebar.

Select text and use `⌘⌥C`, the editor context menu, or the comments sidebar to add a comment. Comment cards can be edited, resolved, deleted, or scheduled for a reminder. Reminder notifications reopen the app at the related comment.

## Collaboration

SimpleLime can pair with trusted peers on the local network and invite them into a collaborative editing session from the Devices panel. The invited Mac receives its own local scratch copy of the document.

While collaborating, edits are exchanged as text patches, remote selections/cursors are shown in both source and WYSIWYG editors, and the host relays updates between multiple peers. Any peer can leave the session at any time; the local copy remains open on each machine.

For internet collaboration, open Devices -> Internet Relay and choose Host. SimpleLime starts a self-hosted relay on the host Mac, creates a `simplelime://collab?...` link, and reuses the same patch protocol through HTTP. The host still owns the server: the link works when the host Mac and relay port are reachable from the guest.

For a detached relay host, run the standalone SwiftPM server:

```sh
swift run SimpleLimeRelay --host 0.0.0.0 --port 48888 --public-url https://relay.example.com --room-idle-timeout 86400
```

It prints a `simplelime://collab?...` link for guests and exposes `GET /health`, `GET /v1/rooms/{room}/events?since=...`, and `POST /v1/rooms/{room}/events` with the same opaque collaboration payload protocol. SimpleLime clients authenticate relay requests with `Authorization: Bearer <token>` so the room token is not repeated in HTTP request URLs; query-string `token=...` remains accepted only for older clients. Both relay parsers bound request headers/bodies, handle duplicate query items without crashing, trim retained event history by count and encoded byte budget, and clear idle room history after the configured timeout. Standalone `--public-url` values must use `https` unless they point at local development hosts such as `127.0.0.1`/`localhost`, or you explicitly pass `--allow-insecure-public-url`. The server is intentionally self-hosted; put TLS, firewall rules, and reachability in front of it for internet use.

## Encrypted Documents

Use File -> Save Encrypted Copy to save the current buffer as a password-protected `.slenc` file. Reopened encrypted files stay encrypted on normal save, and Save As can write a plain-text copy when needed. On Macs with Touch ID, the password prompt can remember the document password in Keychain for biometric unlock.

## Workspaces

Use Workflow -> New Workspace to create a named context, then Workflow -> Switch Workspace or the command palette to move between them. Each workspace restores its own scratch buffers, file tabs, selected tab, extra SimpleLime windows, workspace-local manual task board, and opened Documents folder root. Global manual tasks stay visible across workspaces.

## Markdown Visual QA

Open `docs/markdown-visual-fixture.md` in SimpleLime to visually check the Markdown surface in one document. It includes local images, image paths with spaces, raw HTML images/media, reference links/images, tables, Mermaid diagrams, math, front matter, TOC, footnotes, callouts, and inline Typora-style extensions.

## AI

SimpleLime talks to local agents through [Agent Client Protocol](https://agentclientprotocol.com/) and can also call HTTP LLM APIs.

Copilot works with the current GitHub Copilot CLI ACP server:

```bash
copilot --acp --stdio
```

Codex is configurable in Settings. The default command is `codex-acp`, so it will work when a Codex ACP adapter is available on `PATH`.

For hosted or local HTTP providers, choose `HTTP LLM`, `Anthropic`, or `Gemini` in the AI panel and configure the base URL, API key, model, and temperature in Settings. OpenAI-compatible servers default to `https://api.openai.com/v1`; local OpenAI-compatible servers can use a URL such as `http://localhost:11434/v1` with an empty API key. Anthropic uses the Messages API, and Gemini uses generateContent.

Tasks can use the configured HTTP LLM provider on demand from the Tasks panel, or automatically when Settings -> AI Agents -> Auto Task Inference is enabled. Automatic inference is debounced after opening or editing the selected text tab and does not force-open the Tasks panel.

The Companion panel uses the configured HTTP LLM provider to scan the current text buffer with compact workspace context from the cursor/selection, open tabs, current comments, tasks, recent local activity, and optionally the frontmost macOS app name, bundle identifier, active window title, Accessibility selected/focused text, and ScreenCaptureKit/Vision OCR text from the active window when enabled in Settings and approved by macOS. Returned suggestions can be applied as exact find/replace edits when the referenced text is still present, or added as anchored comments for review. Enable AI -> Live Companion to debounce scans after edits, selection changes, tab changes, task/comment updates, and watched active-app context changes. The Stats panel Activity Watch can record frontmost app/window changes into the Today Log without enabling AI scans; those app/window entries stay local and are omitted from Companion prompts unless Companion Window Context is enabled. These entries do not count as documents, and the current app/window interval is flushed when watching stops.

Use AI -> Translate Selection to replace selected text with a translation from the configured HTTP LLM provider. Multiple selections are translated in one request and replaced in place.

## Local Automation Bridge

SimpleLime includes a Scribe panel for microphone transcription, system audio capture, or combined meeting-audio capture. Auto mode detects native meeting apps, browser windows whose titles expose Google Meet, Teams, Zoom meeting, Webex, Slack huddle, or Discord voice context, and all tab URLs from every running supported scriptable browser when macOS Automation permission allows it, then switches to mic+system capture with microphone fallback. Supported browser tab scans cover Safari, Chrome, Edge, Brave, and Arc. The opt-in Auto Meeting Scribe toggle in the Scribe panel and Settings -> Automation can keep watching for a detected meeting app and start the transcript automatically. Combined capture keeps the remaining recognizer alive and shows a degraded-capture status if one audio source is denied or unavailable. Final speech is appended to a Markdown transcript scratch, and wake-phrase commands such as `SimpleLime save`, `SimpleLime insert follow up`, `SimpleLime force close tab`, or `SimpleLime replace large file line 42 with edited row` are routed through the same command handler used by local automation.

SimpleLime also starts a loopback-only automation bridge at `http://127.0.0.1:48777` so external tools can send meeting transcripts or voice-control commands from meeting-app capture helpers. The bridge supports REST endpoints, a JSON-RPC 2.0 endpoint at `/v1/rpc`, and newline-delimited raw socket JSON frames on the same local TCP port.

Append transcript text from a meeting helper:

```bash
curl -X POST http://127.0.0.1:48777/v1/scribe \
  -H 'Content-Type: application/json' \
  -d '{"title":"Planning","speaker":"Alex","timestamp":"09:00","text":"Decision recorded."}'
```

Run a command from a local voice/controller process:

```bash
curl -X POST http://127.0.0.1:48777/v1/command \
  -H 'Content-Type: application/json' \
  -d '{"command":"toggleCompanion"}'
```

Edit one line, a line range, or an inserted block in the selected large-file
preview without loading the whole file into the editor:

```bash
curl -X POST http://127.0.0.1:48777/v1/command \
  -H 'Content-Type: application/json' \
  -d '{"command":"replaceLargeFileLine","lineNumber":42,"text":"edited line"}'

curl -X POST http://127.0.0.1:48777/v1/command \
  -H 'Content-Type: application/json' \
  -d '{"command":"insertLargeFileLine","lineNumber":42,"text":"inserted line"}'

curl -X POST http://127.0.0.1:48777/v1/command \
  -H 'Content-Type: application/json' \
  -d '{"command":"deleteLargeFileLine","lineNumber":42}'

curl -X POST http://127.0.0.1:48777/v1/command \
  -H 'Content-Type: application/json' \
  -d '{"command":"replaceLargeFileLines","lineNumber":42,"endLineNumber":44,"text":"first\nsecond"}'

curl -X POST http://127.0.0.1:48777/v1/command \
  -H 'Content-Type: application/json' \
  -d '{"command":"insertLargeFileLines","lineNumber":42,"text":"first\nsecond"}'

curl -X POST http://127.0.0.1:48777/v1/command \
  -H 'Content-Type: application/json' \
  -d '{"command":"deleteLargeFileLines","lineNumber":42,"endLineNumber":44}'
```

Force-close a stuck tab by path, file name, or tab title without relying on the
currently selected tab:

```bash
simplelime --force-close-path /Users/me/Downloads/openapi.json
```

Run the same command through JSON-RPC:

```bash
curl -X POST http://127.0.0.1:48777/v1/rpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"cmd-1","method":"command","params":{"command":"toggleCompanion"}}'
```

Run a command over a raw socket frame:

```bash
printf '%s\n' '{"type":"command","payload":{"command":"toggleCompanion"}}' | nc 127.0.0.1 48777
```

Supported commands are `newScratch`, `save`, `close`, `forceClose`, `forceClosePath`, `toggleCompanion`, `runCompanionScan`, `toggleTasks`, `toggleTerminal`, `toggleMacros`, `toggleStats`, `toggleActivityWatch`, `toggleScribe`, `showCommandPalette`, `insertText`, `replaceLargeFileLine`, `insertLargeFileLine`, `deleteLargeFileLine`, `replaceLargeFileLines`, `insertLargeFileLines`, and `deleteLargeFileLines`.

## Install

### Homebrew

```bash
brew install --cask alexrett/tap/simplelime
```

Open files from the terminal:

```bash
simplelime notes.md
simplelime --safe-mode
```

Use `simplelime --safe-mode` when a restored session blocks startup; it opens
SimpleLime with a clean window instead of restored tabs so the next app persist
can replace the bad restore state.

### Download

Grab the latest `SimpleLime.dmg` from [Releases](https://github.com/alexrett/simplelime/releases).

### Build from Source

```bash
git clone https://github.com/alexrett/simplelime.git
cd simplelime
swift build -c release --arch arm64 --arch x86_64
```

For a local debug app bundle, use the project run script. `--build-only` stages
`dist/SimpleLime.app` without closing an already running SimpleLime process and
prints a warning when a stale window is still open; plain `run` builds, closes
the old process, waits for it to exit, force-quits only if it stays stuck, and
launches the fresh bundle. If a restored session ever blocks startup, pass
`--safe-mode` after `run` to start with a clean window instead of restored tabs;
after the app persists, that clean session replaces the bad restore state. The
installed `simplelime` launcher supports the same recovery flag.

```bash
./script/build_and_run.sh --build-only
./script/build_and_run.sh run
./script/build_and_run.sh run --safe-mode
```

Editor-core checks have two repeatable smoke scripts. The headless benchmark
generates large text/CSV fixtures, runs focused editor tests, and stages the
app. The live latency smoke launches the built GUI without screenshots, streams
`EditorPerformance` metrics, sends a local automation insert, and can drive
real key/selection input through System Events when macOS Accessibility
permission is available.

```bash
./script/editor_core_benchmark.sh
./script/editor_live_latency_smoke.sh --skip-build
./script/editor_live_latency_smoke.sh --skip-build --openapi
```

To create a signed release build locally:

```bash
./build.sh release
```

Set `IDENTITY` and `NOTARY_PROFILE` in `.env.local` if you need to override the defaults.

## Requirements

- macOS 14.0 (Sonoma) or later
- Works on Apple Silicon and Intel Macs

## License

MIT
