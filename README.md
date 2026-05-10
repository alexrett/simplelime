# SimpleLime

Scratch-first text editor for macOS. It keeps temporary notes alive across app restarts, opens normal text files and folders, has line numbers, Markdown preview/WYSIWYG editing, syntax highlighting, search/replace, comments, local-network sharing/collaboration, text transforms, and AI assistance through Agent Client Protocol.

![SimpleLime](screenshots/app.png)

## Why?

Sublime is still great as a place to dump temporary text, but I wanted a smaller native macOS editor focused on scratch buffers: quick notes, copied snippets, drafts, Markdown, and files that should survive a reboot even before they are saved.

SimpleLime is not trying to replace a full IDE. It is a fast working notebook with editor habits I use every day.

## Features

- Restored scratch buffers that survive app restarts
- Open and save regular text files
- Open a folder as a document catalog sidebar
- Chrome-style tabs in the window title area
- Always-on line numbers and current-line highlight
- Soft wrap by default
- Markdown-aware syntax highlighting for source mode, including fenced code blocks without bleeding Markdown styles across fences
- Syntax highlighting for Swift, JavaScript, TypeScript, JSON, HTML, CSS, Python, Ruby, Go, Rust, shell, and Markdown
- Markdown WYSIWYG editing plus source preview with table controls, block-source editing for code fences, Mermaid, math, HTML/media and image markdown, paste/drop image insertion, local/remote images, reference links/images, autolinks, safe inline HTML/media blocks, offline Mermaid and math fallbacks, math blocks, TOC, callouts, front matter, footnotes, outline navigation, heading filter, Markdown formatting commands, nested lists, list continuation, and smart bracket/quote pairs
- Find, replace, regex search, match case, whole word, find/replace in tabs and opened folders, select all matches
- Multi-cursor editing
- Sublime-style selection and line commands: add next occurrence, split selection into lines, expand selection to line, column cursors, move/delete/indent/comment lines
- Sublime-style minimap with click-to-line navigation
- Focus mode and typewriter mode for long writing sessions
- Command palette with command search, fuzzy file navigation for the opened folder, and `:line` navigation
- Text transforms: uppercase, lowercase, title case, swap case, reverse selection, duplicate line or selection, sort lines, unique lines, trim trailing whitespace, join lines
- Document comments stored outside the text file, with source/WYSIWYG highlights, a comments sidebar, context-menu insertion, resolve/delete, and reminder notifications
- Font size controls
- AI chat per tab with multiple sessions
- ACP integration for Copilot and configurable Codex-compatible agents
- Local network device sharing with trusted SimpleLime peers
- P2P collaborative editing with invited peers: each Mac keeps its own local copy, changes sync as text patches, remote cursors/selections are shown in source and WYSIWYG, and anyone can leave without closing the document
- Independent window tab groups
- Move tabs between windows or open a copy of the current tab in a new window
- Finder Open With support for text files
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
| `⌘⌥P` | Toggle Markdown preview |
| `⌘⌥O` | Toggle Markdown outline |
| `⌘⌥E` | Toggle Markdown WYSIWYG mode |
| `⌘⌥D` | Toggle documents sidebar |
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

## Markdown Visual QA

Open `docs/markdown-visual-fixture.md` in SimpleLime to visually check the Markdown surface in one document. It includes local images, image paths with spaces, raw HTML images/media, reference links/images, tables, Mermaid diagrams, math, front matter, TOC, footnotes, callouts, and inline Typora-style extensions.

## AI

SimpleLime talks to local agents through [Agent Client Protocol](https://agentclientprotocol.com/). Copilot works with the current GitHub Copilot CLI ACP server:

```bash
copilot --acp --stdio
```

Codex is configurable in Settings. The default command is `codex-acp`, so it will work when a Codex ACP adapter is available on `PATH`.

## Install

### Homebrew

```bash
brew install --cask alexrett/tap/simplelime
```

Open files from the terminal:

```bash
simplelime notes.md
```

### Download

Grab the latest `SimpleLime.dmg` from [Releases](https://github.com/alexrett/simplelime/releases).

### Build from Source

```bash
git clone https://github.com/alexrett/simplelime.git
cd simplelime
swift build -c release --arch arm64 --arch x86_64
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
