import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: EditorStore
    @ObservedObject private var network: NetworkShareService
    @StateObject private var chromeState = WindowChromeState()
    @State private var keyMonitor: Any?
    private weak var workspace: WorkspaceStore?
    private let onActivate: () -> Void

    init(store: EditorStore, workspace: WorkspaceStore? = nil, onActivate: @escaping () -> Void = {}) {
        self.store = store
        self.workspace = workspace
        self.onActivate = onActivate
        _network = ObservedObject(wrappedValue: store.networkShare)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                TabBarView(store: store, isFullScreen: chromeState.isFullScreen)
                    .frame(height: 38)
                    .zIndex(20)

                if store.findPanelMode != .hidden {
                    SearchPanelView(store: store)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }

                if let buffer = store.selectedBuffer {
                    if store.shouldSuspendEditorRenderingForPendingClose(buffer) {
                        PendingCloseBackdrop()
                            .zIndex(0)
                    } else {
                        workspace(buffer: buffer)
                            .zIndex(0)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Buffer")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(0)
                }
            }

            if store.isCommandPaletteVisible {
                CommandPaletteOverlay(store: store, workspace: workspace)
                    .zIndex(100)
            }
        }
        .onAppear {
            onActivate()
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .background(WindowChromeReader(state: chromeState, onBecomeMain: onActivate).frame(width: 0, height: 0))
        .ignoresSafeArea(.container, edges: ignoredSafeAreaEdges)
        .alert(
            "SimpleLime",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { isPresented in
                    if !isPresented {
                        store.lastError = nil
                    }
                }
            )
        ) {
            Button("OK") {
                store.lastError = nil
            }
        } message: {
            Text(store.lastError ?? "")
        }
        .alert(
            "Close Tab?",
            isPresented: Binding(
                get: { store.pendingCloseBuffer != nil },
                set: { isPresented in
                    if !isPresented {
                        store.cancelPendingClose()
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                store.cancelPendingClose()
            }
            Button("Close", role: .destructive) {
                store.confirmPendingClose()
            }
        } message: {
            Text("“\(store.pendingCloseBuffer?.displayTitle ?? "Untitled")” has unsaved editor state. Closing it removes this tab from the restored session.")
        }
        .alert(
            "Trust Device?",
            isPresented: Binding(
                get: { network.pendingPairRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        network.rejectPendingPair()
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                network.rejectPendingPair()
            }
            Button("Trust") {
                network.acceptPendingPair()
                store.showNetworkPanel()
            }
        } message: {
            Text("Allow \(network.pendingPairRequest?.name ?? "this Mac") to exchange SimpleLime notes with this device.")
        }
    }

    private var ignoredSafeAreaEdges: Edge.Set {
        chromeState.isFullScreen ? [] : .top
    }

    @ViewBuilder
    private func workspace(buffer: EditorBuffer) -> some View {
        if hasLeftSidebar(for: buffer) || hasRightSidebar {
            HSplitView {
                if hasLeftSidebar(for: buffer) {
                    leftSidebar(buffer: buffer)
                }

                EditorWorkspaceView(store: store, buffer: buffer)
                    .id(buffer.id)
                    .clipped()
                    .frame(minWidth: 260)

                if hasRightSidebar {
                    rightSidebar(buffer: buffer)
                }
            }
            .clipped()
        } else {
            EditorWorkspaceView(store: store, buffer: buffer)
                .id(buffer.id)
                .clipped()
        }
    }

    private func hasLeftSidebar(for buffer: EditorBuffer) -> Bool {
        store.isDocumentCatalogVisible || (store.isOutlineVisible && buffer.language.isMarkdown)
    }

    private var hasRightSidebar: Bool {
        store.isAIPanelVisible ||
            store.isNetworkPanelVisible ||
            store.isCommentsPanelVisible ||
            store.isCompanionPanelVisible ||
            store.isTasksPanelVisible ||
            store.isPOModePanelVisible ||
            store.isScribePanelVisible ||
            store.isStatsPanelVisible ||
            store.isMacrosPanelVisible
    }

    @ViewBuilder
    private func leftSidebar(buffer: EditorBuffer) -> some View {
        if store.isDocumentCatalogVisible {
            DocumentCatalogView(store: store)
                .frame(minWidth: 190, idealWidth: 250, maxWidth: 360)
        } else if store.isOutlineVisible, buffer.language.isMarkdown {
            MarkdownOutlineView(
                text: buffer.text,
                selectionRanges: buffer.selectionRanges,
                onSelect: { heading in
                    store.jumpToHeading(heading)
                }
            )
            .frame(minWidth: 170, idealWidth: 220, maxWidth: 320)
        }
    }

    @ViewBuilder
    private func rightSidebar(buffer: EditorBuffer) -> some View {
        if store.isAIPanelVisible {
            AIChatPanelView(store: store, buffer: buffer)
        } else if store.isCompanionPanelVisible {
            CompanionPanelView(store: store, buffer: buffer)
        } else if store.isNetworkPanelVisible {
            NetworkSharePanelView(store: store)
        } else if store.isCommentsPanelVisible {
            CommentsPanelView(store: store, buffer: buffer)
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
        } else if store.isTasksPanelVisible {
            TaskBoardPanelView(store: store)
        } else if store.isPOModePanelVisible {
            POModePanelView(store: store)
        } else if store.isScribePanelVisible {
            VoiceScribePanelView(store: store)
        } else if store.isStatsPanelVisible {
            UsageStatsPanelView(store: store)
        } else if store.isMacrosPanelVisible {
            TextMacroPanelView(store: store)
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event: event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handle(event: NSEvent) -> NSEvent? {
        if store.isCommandPaletteVisible, event.keyCode == 53 {
            store.hideCommandPalette()
            return nil
        }

        if event.keyCode == 53, store.findPanelMode != .hidden {
            store.hideFindPanel()
            return nil
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 48, flags.contains(.control), !flags.contains(.command), !flags.contains(.option) {
            if flags.contains(.shift) {
                store.selectPreviousTab()
            } else {
                store.selectNextTab()
            }
            return nil
        }

        guard flags.contains(.command),
              !flags.contains(.control) else {
            return event
        }

        switch event.keyCode {
        case 44 where !flags.contains(.option) && !flags.contains(.shift):
            if store.selectedBuffer?.language.isMarkdown == true {
                store.toggleWysiwygMode()
                return nil
            }
            return event
        case 18 where flags.contains(.option):
            store.showSourceMode()
            return nil
        case 19 where flags.contains(.option):
            store.showMarkdownPreviewMode()
            return nil
        case 20 where flags.contains(.option):
            store.showMarkdownWysiwygMode()
            return nil
        case 21 where flags.contains(.option):
            store.toggleMiniMap()
            return nil
        case 35 where flags.contains(.shift):
            store.showCommandPalette()
            return nil
        case 31 where flags.contains(.shift):
            store.openFolder()
            return nil
        case 35 where flags.contains(.option):
            store.toggleMarkdownPreview()
            return nil
        case 31 where flags.contains(.option):
            store.toggleMarkdownOutline()
            return nil
        case 14 where flags.contains(.option):
            store.toggleWysiwygMode()
            return nil
        case 3 where flags.contains(.option):
            store.toggleFocusMode()
            return nil
        case 17 where flags.contains(.option) && !flags.contains(.shift):
            store.toggleTypewriterMode()
            return nil
        case 17 where flags.contains(.shift) && !flags.contains(.option):
            store.toggleTasksPanel()
            return nil
        case 38 where flags.contains(.shift):
            store.toggleTerminalPanel()
            return nil
        case 34 where flags.contains(.shift):
            store.toggleAIPanel()
            return nil
        case 40 where flags.contains(.shift):
            store.showNetworkPanel()
            return nil
        case 3 where flags.contains(.shift):
            store.showGlobalFind()
            return nil
        case 3:
            store.showFind()
            return nil
        case 15:
            store.showReplace()
            return nil
        case 2 where flags.contains(.option):
            store.toggleDocumentCatalog()
            return nil
        case 8 where flags.contains(.option):
            if store.isWysiwygModeEnabled {
                return event
            }
            store.addCommentToSelection()
            return nil
        case 2 where flags.contains(.shift):
            store.performTextTransform(.duplicateLine)
            return nil
        case 2:
            store.addNextOccurrence()
            return nil
        case 11:
            store.performMarkdownCommand(.bold)
            return nil
        case 34:
            store.performMarkdownCommand(.italic)
            return nil
        case 37 where flags.contains(.shift):
            store.performEditorCommand(.splitSelectionIntoLines)
            return nil
        case 37 where flags.contains(.option):
            store.selectAllMatches()
            return nil
        case 37:
            store.performEditorCommand(.expandSelectionToLine)
            return nil
        case 5 where flags.contains(.option):
            if flags.contains(.shift) {
                store.addPreviousOccurrence()
            } else {
                store.addNextOccurrence()
            }
            return nil
        case 5 where flags.contains(.shift):
            store.findPrevious()
            return nil
        case 5:
            store.findNext()
            return nil
        case 6 where flags.contains(.option):
            store.toggleWrapLines()
            return nil
        case 30:
            store.performEditorCommand(.indentLines)
            return nil
        case 33:
            store.performEditorCommand(.outdentLines)
            return nil
        case 44:
            store.performEditorCommand(.toggleComment)
            return nil
        case 32 where flags.contains(.option) && flags.contains(.shift):
            store.performTextTransform(.uniqueLines)
            return nil
        case 32 where flags.contains(.shift):
            store.performTextTransform(.uppercase)
            return nil
        case 32 where flags.contains(.option):
            store.performTextTransform(.lowercase)
            return nil
        case 17 where flags.contains(.option) && flags.contains(.shift):
            store.performTextTransform(.titlecase)
            return nil
        case 1 where flags.contains(.option):
            store.performTextTransform(.sortLines)
            return nil
        case 13 where flags.contains(.option):
            store.performTextTransform(.trimTrailingWhitespace)
            return nil
        case 38:
            store.performTextTransform(.joinLines)
            return nil
        case 24, 69:
            store.increaseFontSize()
            return nil
        case 27, 78:
            store.decreaseFontSize()
            return nil
        default:
            return event
        }
    }
}

private struct PendingCloseBackdrop: View {
    var body: some View {
        Color(nsColor: .textBackgroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CommandPaletteOverlay: View {
    @ObservedObject var store: EditorStore
    weak var workspace: WorkspaceStore?
    @StateObject private var query = CommandPaletteQuery()
    @State private var selectedIndex = 0

    private var filteredCommands: [PaletteCommand] {
        if let lineNumber = lineJumpQuery {
            return [
                PaletteCommand("Go to Line \(lineNumber)", shortcut: "↩", keywords: "goto line") {
                    store.jumpToLine(lineNumber)
                }
            ]
        }

        let commands = paletteCommands
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileCommands = documentCatalogCommands(matching: trimmed)
        guard !trimmed.isEmpty else { return commands }

        let commandMatches = commands.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
                $0.keywords.localizedCaseInsensitiveContains(trimmed)
        }

        return fileCommands + commandMatches
    }

    private var lineJumpQuery: Int? {
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(":") else { return nil }

        let rawNumber = trimmed.dropFirst()
        guard !rawNumber.isEmpty,
              rawNumber.allSatisfy(\.isNumber),
              let lineNumber = Int(rawNumber) else {
            return nil
        }

        return lineNumber
    }

    private var paletteCommands: [PaletteCommand] {
        var commands: [PaletteCommand] = [
            PaletteCommand("New Scratch Buffer", shortcut: "⌘N", keywords: "file tab scratch") { store.newScratch() },
            PaletteCommand("New Drawing Board", shortcut: nil, keywords: "drawing whiteboard canvas sketch miro") { store.newDrawingBoard() },
            PaletteCommand("Open File", shortcut: "⌘O", keywords: "file") { store.openFiles() },
            PaletteCommand("Open Encrypted File", shortcut: nil, keywords: "file encrypted secure password touch id") { store.openEncryptedFileWithPrompt() },
            PaletteCommand("Open Folder", shortcut: "⇧⌘O", keywords: "folder project catalog documents sidebar sublime") { store.openFolder() },
            PaletteCommand("Save", shortcut: "⌘S", keywords: "file") { store.saveSelected() },
            PaletteCommand("Save Chunk Back to Source", shortcut: nil, keywords: "large file chunk save back source") {
                store.saveSelectedLargeFileChunkBackToSource()
            },
            PaletteCommand("Edit Large-File Chunk", shortcut: nil, keywords: "large file chunk edit in place") {
                store.enableSelectedLargeFileChunkEditing()
            },
            PaletteCommand("Replace Large-File Line", shortcut: nil, keywords: "large file virtual line replace rewrite source") {
                store.replaceSelectedLargeFileLineWithPrompt()
            },
            PaletteCommand("Insert Large-File Line", shortcut: nil, keywords: "large file virtual line insert source") {
                store.insertSelectedLargeFileLineWithPrompt()
            },
            PaletteCommand("Delete Large-File Line", shortcut: nil, keywords: "large file virtual line delete source") {
                store.deleteSelectedLargeFileLineWithPrompt()
            },
            PaletteCommand("Replace Large-File Lines", shortcut: nil, keywords: "large file virtual range block replace rewrite source") {
                store.replaceSelectedLargeFileLinesWithPrompt()
            },
            PaletteCommand("Insert Large-File Lines", shortcut: nil, keywords: "large file virtual range block insert source") {
                store.insertSelectedLargeFileLinesWithPrompt()
            },
            PaletteCommand("Delete Large-File Lines", shortcut: nil, keywords: "large file virtual range block delete source") {
                store.deleteSelectedLargeFileLinesWithPrompt()
            },
            PaletteCommand("Save Numbered Version", shortcut: nil, keywords: "file backup version copy") { store.saveVersionedCopyOfSelected() },
            PaletteCommand("Save With Numbered Backup", shortcut: nil, keywords: "file backup version before overwrite") { store.saveSelectedWithNumberedBackup() },
            PaletteCommand("Save Encrypted Copy", shortcut: nil, keywords: "file encrypted secure password touch id") { store.saveSelectedEncryptedWithPrompt() },
            PaletteCommand("Force Close Buffer", shortcut: nil, keywords: "close discard stuck tab modal") { store.forceCloseSelected() },
            PaletteCommand("Export HTML", shortcut: nil, keywords: "export html markdown file") { store.exportSelectedAsHTML() },
            PaletteCommand("Export PDF", shortcut: nil, keywords: "export pdf print file") { store.exportSelectedAsPDF() },
            PaletteCommand("Export Word", shortcut: nil, keywords: "export word doc file") { store.exportSelectedAsWord() },
            PaletteCommand("Export Drawing as SVG", shortcut: nil, keywords: "drawing whiteboard export svg vector image") { store.exportSelectedDrawingAsSVG() },
            PaletteCommand("Export Drawing as PNG", shortcut: nil, keywords: "drawing whiteboard export png image") { store.exportSelectedDrawingAsPNG() },
            PaletteCommand("Copy Drawing as PNG", shortcut: nil, keywords: "drawing whiteboard copy clipboard png image paste") { store.copySelectedDrawingAsPNG() },
            PaletteCommand("Insert Drawing Widget", shortcut: nil, keywords: "drawing whiteboard markdown widget sldraw image") { store.insertDrawingWidgetIntoMarkdown() },
            PaletteCommand("Export CSV/TSV as Excel", shortcut: nil, keywords: "export excel xls csv tsv spreadsheet") { store.exportSelectedDelimitedTableAsExcel() },
            PaletteCommand("Compare With Previous Tab", shortcut: nil, keywords: "diff compare file tab") { store.compareSelectedBufferWithPreviousTab() },
            PaletteCommand("Compare With File", shortcut: nil, keywords: "diff compare file choose") { store.compareSelectedBufferWithFile() },
            PaletteCommand("Commit Current File", shortcut: nil, keywords: "git commit file version control") { store.commitSelectedFileWithPrompt() },
            PaletteCommand("Add Finder Tag", shortcut: nil, keywords: "finder tag label file") { store.addFinderTagToSelectedFileWithPrompt() },
            PaletteCommand("Clear Finder Tags", shortcut: nil, keywords: "finder tag label file") { store.clearFinderTagsForSelectedFile() },
            PaletteCommand(
                store.selectedSavePolicy == .readOnly ? "Disable Read-Only Mode" : "Enable Read-Only Mode",
                shortcut: nil,
                keywords: "readonly read-only protect save guard"
            ) { store.toggleReadOnlyMode() },
            PaletteCommand(
                store.selectedSavePolicy == .temporary ? "Disable Temporary Mode" : "Enable Temporary Mode",
                shortcut: nil,
                keywords: "temporary temp protect save guard"
            ) { store.toggleTemporaryMode() },
            PaletteCommand("Allow Saving", shortcut: nil, keywords: "save guard normal readonly temporary") {
                store.setSelectedSavePolicy(.normal)
            },
            PaletteCommand("Find", shortcut: "⌘F", keywords: "search") { store.showFind() },
            PaletteCommand("Find and Replace", shortcut: "⌘R", keywords: "search replace") { store.showReplace() },
            PaletteCommand("Find in Files", shortcut: "⇧⌘F", keywords: "global search folder tabs files") { store.showGlobalFind() },
            PaletteCommand("Replace in Files", shortcut: "⇧⌘R", keywords: "global search replace folder tabs files") { store.showGlobalFind() },
            PaletteCommand("Add Next Occurrence", shortcut: "⌘D", keywords: "cursor selection sublime") { store.addNextOccurrence() },
            PaletteCommand("Select All Matches", shortcut: "⌥⌘L", keywords: "cursor selection sublime") { store.selectAllMatches() },
            PaletteCommand("Split Selection Into Lines", shortcut: "⇧⌘L", keywords: "cursor line sublime") { store.performEditorCommand(.splitSelectionIntoLines) },
            PaletteCommand("Expand Selection to Line", shortcut: "⌘L", keywords: "selection line sublime") { store.performEditorCommand(.expandSelectionToLine) },
            PaletteCommand("Toggle Fold", shortcut: nil, keywords: "fold collapse expand json yaml outline heading") { store.toggleStructuredFoldAtSelection() },
            PaletteCommand("Unfold All", shortcut: nil, keywords: "fold collapse expand json yaml outline heading") { store.unfoldAllStructuredBlocks() },
            PaletteCommand("Create Editor Diagnostics", shortcut: nil, keywords: "editor diagnostics performance latency large file syntax") { store.createEditorDiagnosticsScratch() },
            PaletteCommand("Toggle Word Wrap", shortcut: "⌥⌘Z", keywords: "editor wrap") { store.toggleWrapLines() },
            PaletteCommand("Markdown Source Mode", shortcut: "⌥⌘1", keywords: "source markdown editor raw") { store.showSourceMode() },
            PaletteCommand("Markdown Preview Split", shortcut: "⌥⌘2", keywords: "typora preview markdown split") { store.showMarkdownPreviewMode() },
            PaletteCommand("Markdown WYSIWYG Mode", shortcut: "⌥⌘3", keywords: "typora wysiwyg live preview markdown editor") { store.showMarkdownWysiwygMode() },
            PaletteCommand("Toggle Source/WYSIWYG", shortcut: "⌘/", keywords: "markdown typora source wysiwyg mode") { store.toggleWysiwygMode() },
            PaletteCommand("Toggle Markdown Outline", shortcut: "⌥⌘O", keywords: "typora outline markdown") { store.toggleMarkdownOutline() },
            PaletteCommand("Toggle Documents Sidebar", shortcut: "⌥⌘D", keywords: "folder project catalog documents sidebar sublime") { store.toggleDocumentCatalog() },
            PaletteCommand("Add Comment", shortcut: "⌥⌘C", keywords: "comment annotation note review google docs") { store.addCommentToSelection() },
            PaletteCommand("Toggle Comments", shortcut: nil, keywords: "comment annotation note review google docs") { store.toggleCommentsPanel() },
            PaletteCommand("Toggle Tasks", shortcut: "⇧⌘T", keywords: "task kanban board todo checklist") { store.toggleTasksPanel() },
            PaletteCommand("New Task", shortcut: nil, keywords: "task kanban board todo") { store.addManualTaskWithPrompt() },
            PaletteCommand("Generate PO Mode Brief", shortcut: nil, keywords: "po mode product owner mindmap mind map docs gaps kanban analysis") { store.generatePOModeBriefForDocumentCatalog() },
            PaletteCommand("Add PO Gaps as Tasks", shortcut: nil, keywords: "po mode product owner gaps kanban tasks todo") { store.addPOModeGapsAsTasks() },
            PaletteCommand("Open PO Mode Panel", shortcut: nil, keywords: "po mode product owner mindmap mind map docs gaps kanban analysis drilldown") { store.refreshPOModeAnalysisForDocumentCatalog() },
            PaletteCommand("Toggle Scribe", shortcut: nil, keywords: "scribe voice microphone transcript dictation meeting") { store.toggleScribePanel() },
            PaletteCommand("Start Voice Scribe", shortcut: nil, keywords: "scribe voice microphone transcript dictation meeting") { store.startVoiceScribe() },
            PaletteCommand("Stop Voice Scribe", shortcut: nil, keywords: "scribe voice microphone transcript dictation meeting") { store.stopVoiceScribe() },
            PaletteCommand("Toggle Stats", shortcut: nil, keywords: "stats analytics editing timelog activity") { store.toggleStatsPanel() },
            PaletteCommand(
                store.isUsageActivityWatchEnabled ? "Stop Activity Watch" : "Start Activity Watch",
                shortcut: nil,
                keywords: "stats analytics timelog activity app window watch"
            ) { store.toggleUsageActivityWatch() },
            PaletteCommand("Create Today's Timelog", shortcut: nil, keywords: "stats analytics editing timelog activity report") { store.createTodayTimelogScratch() },
            PaletteCommand("Toggle Macros", shortcut: nil, keywords: "macro template snippet automation") { store.toggleMacrosPanel() },
            PaletteCommand("Create Macro From Selection", shortcut: nil, keywords: "macro template snippet selection") { store.createTextMacroFromSelectionWithPrompt() },
            PaletteCommand("Toggle Terminal", shortcut: "⇧⌘J", keywords: "terminal shell command zsh bottom panel") { store.toggleTerminalPanel() },
            PaletteCommand("Restart Terminal", shortcut: nil, keywords: "terminal shell command zsh pty broken reset restart") {
                if let id = store.selectedTerminalSessionID {
                    store.restartTerminalSession(id)
                }
            },
            PaletteCommand("Insert PRD Template", shortcut: nil, keywords: "macro template prd product requirements") {
                if let macro = TextMacro.builtIns.first(where: { $0.id == "built-in:prd" }) {
                    store.applyTextMacro(macro)
                }
            },
            PaletteCommand("Insert 1x1 Template", shortcut: nil, keywords: "macro template one on one meeting") {
                if let macro = TextMacro.builtIns.first(where: { $0.id == "built-in:1x1" }) {
                    store.applyTextMacro(macro)
                }
            },
            PaletteCommand("Toggle Minimap", shortcut: "⌥⌘4", keywords: "sublime minimap overview") { store.toggleMiniMap() },
            PaletteCommand("Toggle Focus Mode", shortcut: "⌥⌘F", keywords: "focus writing") { store.toggleFocusMode() },
            PaletteCommand("Toggle Typewriter Mode", shortcut: "⌥⌘T", keywords: "typewriter writing") { store.toggleTypewriterMode() },
            PaletteCommand("Toggle AI Panel", shortcut: "⇧⌘I", keywords: "agent chat") { store.toggleAIPanel() },
            PaletteCommand("Toggle Companion", shortcut: nil, keywords: "ai companion suggestion review apply comment") { store.toggleCompanionPanel() },
            PaletteCommand(
                store.isCompanionAutoScanEnabled ? "Disable Live Companion" : "Enable Live Companion",
                shortcut: nil,
                keywords: "ai companion live realtime watch autoscan suggestion"
            ) { store.toggleCompanionAutoScan() },
            PaletteCommand("Run Companion Scan", shortcut: nil, keywords: "ai companion suggestion review apply comment") { store.runCompanionScan() },
            PaletteCommand("Translate Selection", shortcut: nil, keywords: "ai translation translate language local llm") { store.translateSelectionWithPrompt() },
            PaletteCommand("Uppercase", shortcut: "⇧⌘U", keywords: "text transform") { store.performTextTransform(.uppercase) },
            PaletteCommand("Lowercase", shortcut: "⌥⌘U", keywords: "text transform") { store.performTextTransform(.lowercase) },
            PaletteCommand("Title Case", shortcut: "⌥⇧⌘T", keywords: "text transform") { store.performTextTransform(.titlecase) },
            PaletteCommand("Swap Case", shortcut: nil, keywords: "text transform") { store.performTextTransform(.swapCase) },
            PaletteCommand("Reverse Selection", shortcut: nil, keywords: "text transform") { store.performTextTransform(.reverseSelection) },
            PaletteCommand("Sort Lines", shortcut: "⌥⌘S", keywords: "text transform sublime") { store.performTextTransform(.sortLines) },
            PaletteCommand("Unique Lines", shortcut: "⌥⇧⌘U", keywords: "text transform") { store.performTextTransform(.uniqueLines) },
            PaletteCommand("Trim Trailing Whitespace", shortcut: "⌥⌘W", keywords: "text transform") { store.performTextTransform(.trimTrailingWhitespace) },
            PaletteCommand("Duplicate Line", shortcut: "⇧⌘D", keywords: "line sublime") { store.performTextTransform(.duplicateLine) },
            PaletteCommand("Join Lines", shortcut: "⌘J", keywords: "line sublime") { store.performTextTransform(.joinLines) },
            PaletteCommand("Format JSON", shortcut: nil, keywords: "json format pretty transform") { store.performTextTransform(.formatJSON) },
            PaletteCommand("Minify JSON", shortcut: nil, keywords: "json minify compact transform") { store.performTextTransform(.minifyJSON) },
            PaletteCommand("Format Markdown Tables", shortcut: nil, keywords: "markdown table format align transform") { store.performTextTransform(.formatMarkdownTables) },
            PaletteCommand("Move Line Up", shortcut: "⌥⌘↑", keywords: "line sublime") { store.performEditorCommand(.moveLineUp) },
            PaletteCommand("Move Line Down", shortcut: "⌥⌘↓", keywords: "line sublime") { store.performEditorCommand(.moveLineDown) },
            PaletteCommand("Delete Line", shortcut: nil, keywords: "line sublime") { store.performEditorCommand(.deleteLine) },
            PaletteCommand("Indent Lines", shortcut: "⌘]", keywords: "line") { store.performEditorCommand(.indentLines) },
            PaletteCommand("Outdent Lines", shortcut: "⌘[", keywords: "line") { store.performEditorCommand(.outdentLines) },
            PaletteCommand("Toggle Comment", shortcut: nil, keywords: "line code") { store.performEditorCommand(.toggleComment) },
            PaletteCommand("Bold", shortcut: "⌘B", keywords: "markdown typora") { store.performMarkdownCommand(.bold) },
            PaletteCommand("Italic", shortcut: "⌘I", keywords: "markdown typora") { store.performMarkdownCommand(.italic) },
            PaletteCommand("Inline Code", shortcut: nil, keywords: "markdown typora") { store.performMarkdownCommand(.inlineCode) },
            PaletteCommand("Strikethrough", shortcut: nil, keywords: "markdown typora delete strike") { store.performMarkdownCommand(.strikethrough) },
            PaletteCommand("Highlight", shortcut: nil, keywords: "markdown typora mark") { store.performMarkdownCommand(.highlight) },
            PaletteCommand("Subscript", shortcut: nil, keywords: "markdown typora") { store.performMarkdownCommand(.subscriptText) },
            PaletteCommand("Superscript", shortcut: nil, keywords: "markdown typora") { store.performMarkdownCommand(.superscriptText) },
            PaletteCommand("Heading 1", shortcut: nil, keywords: "markdown typora") { store.performMarkdownCommand(.heading1) },
            PaletteCommand("Heading 2", shortcut: nil, keywords: "markdown typora") { store.performMarkdownCommand(.heading2) },
            PaletteCommand("Heading 3", shortcut: nil, keywords: "markdown typora") { store.performMarkdownCommand(.heading3) },
            PaletteCommand("Bullet List", shortcut: nil, keywords: "markdown typora") { store.performMarkdownCommand(.unorderedList) },
            PaletteCommand("Numbered List", shortcut: nil, keywords: "markdown typora") { store.performMarkdownCommand(.orderedList) },
            PaletteCommand("Task List", shortcut: nil, keywords: "markdown typora") { store.performMarkdownCommand(.taskList) },
            PaletteCommand("Link", shortcut: nil, keywords: "markdown typora insert") { store.performMarkdownCommand(.link) },
            PaletteCommand("Image", shortcut: nil, keywords: "markdown typora insert") { store.performMarkdownCommand(.image) },
            PaletteCommand("Table", shortcut: nil, keywords: "markdown typora insert") { store.performMarkdownCommand(.table) },
            PaletteCommand("Quote", shortcut: nil, keywords: "markdown typora") { store.performMarkdownCommand(.quote) },
            PaletteCommand("Code Fence", shortcut: nil, keywords: "markdown typora") { store.performMarkdownCommand(.codeFence) },
            PaletteCommand("Math Block", shortcut: nil, keywords: "markdown typora insert latex katex") { store.performMarkdownCommand(.mathBlock) },
            PaletteCommand("Mermaid Diagram", shortcut: nil, keywords: "markdown typora insert mermaid diagram") { store.performMarkdownCommand(.mermaidDiagram) }
        ]

        if let workspace {
            commands.insert(
                PaletteCommand("New Workspace", shortcut: nil, keywords: "workspace work personal hobby context") {
                    workspace.createWorkspaceWithPrompt()
                },
                at: min(1, commands.count)
            )
            commands.insert(
                PaletteCommand("Rename Workspace", shortcut: nil, keywords: "workspace context") {
                    workspace.renameActiveWorkspaceWithPrompt()
                },
                at: min(2, commands.count)
            )

            for profile in workspace.workspaceProfiles where profile.id != workspace.activeWorkspaceID {
                commands.append(
                    PaletteCommand("Switch Workspace: \(profile.name)", shortcut: nil, keywords: "workspace context") {
                        workspace.switchWorkspace(profile.id)
                    }
                )
            }
        }

        if store.selectedBuffer?.language.isDelimitedTable == true {
            commands.append(
                PaletteCommand("Table Preview", shortcut: "⌥⌘P", keywords: "csv tsv table preview data spreadsheet") {
                    store.showDelimitedTablePreviewMode()
                }
            )
        }

        if !(store.selectedBuffer?.language.isMarkdown ?? false) {
            commands.removeAll { $0.keywords.contains("markdown") || $0.keywords.contains("typora") }
        }

        return commands
    }

    private func documentCatalogCommands(matching query: String) -> [PaletteCommand] {
        guard !query.isEmpty else { return [] }

        return store.documentCatalogFileMatches(for: query, limit: 20).map { match in
            PaletteCommand(
                "Open \(match.displayPath)",
                shortcut: "file",
                keywords: "file document catalog \(match.displayPath) \(match.url.lastPathComponent)"
            ) {
                store.openFile(at: match.url)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    store.hideCommandPalette()
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .foregroundStyle(.secondary)
                    CommandPaletteSearchField(
                        query: query,
                        onSubmit: performSelectedCommand,
                        onCancel: store.hideCommandPalette
                    )
                    .frame(height: 22)
                }
                .font(.system(size: 16))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        commandList(commands: filteredCommands)
                            .id(query.text)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selectedIndex) { _, value in
                        proxy.scrollTo(value, anchor: .center)
                    }
                }
            }
            .frame(maxWidth: 620)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor))
            }
            .shadow(radius: 24, y: 12)
            .padding(.horizontal, 20)
            .padding(.top, 52)
        }
        .onChange(of: query.text) { _, _ in
            selectedIndex = 0
        }
        .onMoveCommand { direction in
            guard !filteredCommands.isEmpty else { return }

            switch direction {
            case .down:
                selectedIndex = min(selectedIndex + 1, filteredCommands.count - 1)
            case .up:
                selectedIndex = max(selectedIndex - 1, 0)
            default:
                break
            }
        }
        .onExitCommand {
            store.hideCommandPalette()
        }
    }

    private func performSelectedCommand() {
        guard filteredCommands.indices.contains(selectedIndex) else { return }
        perform(filteredCommands[selectedIndex])
    }

    private func commandList(commands: [PaletteCommand]) -> some View {
        VStack(spacing: 0) {
            if commands.isEmpty {
                Text("No commands")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                    Button {
                        perform(command)
                    } label: {
                        HStack(spacing: 10) {
                            Text(command.title)
                                .lineLimit(1)
                            Spacer()
                            if let shortcut = command.shortcut {
                                Text(shortcut)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(index == selectedIndex ? Color.accentColor.opacity(0.16) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .id(index)
                }
            }
        }
    }

    private func perform(_ command: PaletteCommand) {
        store.hideCommandPalette()
        command.perform()
    }
}

private final class CommandPaletteQuery: ObservableObject {
    @Published private(set) var text = ""

    func setText(_ nextText: String) {
        guard text != nextText else { return }
        text = nextText
    }
}

private struct PaletteCommand: Identifiable {
    var id: String { title }
    let title: String
    let shortcut: String?
    let keywords: String
    let perform: () -> Void

    init(_ title: String, shortcut: String?, keywords: String, perform: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.keywords = keywords
        self.perform = perform
    }
}

private struct CommandPaletteSearchField: NSViewRepresentable {
    @ObservedObject var query: CommandPaletteQuery
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = query.text
        field.placeholderString = "Command"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 16)
        field.textColor = .labelColor
        field.placeholderAttributedString = NSAttributedString(
            string: "Command",
            attributes: [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: NSFont.systemFont(ofSize: 16)
            ]
        )
        field.delegate = context.coordinator
        context.coordinator.installTextChangeObserver(for: field)

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != query.text {
            field.stringValue = query.text
        }

        DispatchQueue.main.async {
            if field.window?.firstResponder !== field.currentEditor() {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandPaletteSearchField
        private var textChangeObserver: NSObjectProtocol?

        init(_ parent: CommandPaletteSearchField) {
            self.parent = parent
        }

        deinit {
            if let textChangeObserver {
                NotificationCenter.default.removeObserver(textChangeObserver)
            }
        }

        func installTextChangeObserver(for field: NSTextField) {
            if let textChangeObserver {
                NotificationCenter.default.removeObserver(textChangeObserver)
            }

            textChangeObserver = NotificationCenter.default.addObserver(
                forName: NSControl.textDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak field] notification in
                guard let self, let field else { return }
                let object = notification.object as AnyObject?
                guard object === field || object === field.currentEditor() else { return }
                self.publish(field.currentEditor()?.string ?? field.stringValue)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField {
                publish(field.currentEditor()?.string ?? field.stringValue)
            } else if let textView = notification.object as? NSTextView {
                publish(textView.string)
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                publish(textView.string)
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        private func publish(_ text: String) {
            guard parent.query.text != text else { return }

            DispatchQueue.main.async { [query = parent.query] in
                query.setText(text)
            }
        }
    }
}
