import SwiftUI

struct SimpleLimeCommands: Commands {
    @ObservedObject var workspace: WorkspaceStore

    private var store: EditorStore? {
        workspace.activeStore
    }

    private var previewCommandTitle: String {
        guard let store else {
            return "Show Preview"
        }

        if store.isPreviewVisible {
            return "Hide Preview"
        }

        if store.selectedBuffer?.language.isDelimitedTable == true {
            return "Show Table Preview"
        }

        return "Show Markdown Preview"
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About SimpleLime") {
                AppAbout.show()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Scratch Buffer") {
                store?.newScratch()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("New Drawing Board") {
                store?.newDrawingBoard()
            }

            Button("New Window") {
                workspace.newWindow()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open File...") {
                store?.openFiles()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Open Encrypted File...") {
                store?.openEncryptedFileWithPrompt()
            }

            Button("Open Folder...") {
                store?.openFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Move Tab to New Window") {
                workspace.moveSelectedTabToNewWindow(from: store)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("Open Copy in New Window") {
                workspace.openSelectedTabCopyInNewWindow(from: store)
            }

            Button("Compare With Previous Tab") {
                store?.compareSelectedBufferWithPreviousTab()
            }

            Button("Compare With File...") {
                store?.compareSelectedBufferWithFile()
            }

            Divider()

            Button("Network Devices") {
                store?.showNetworkPanel()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                store?.saveSelected()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Save As...") {
                store?.saveSelectedAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Save Chunk Back to Source") {
                store?.saveSelectedLargeFileChunkBackToSource()
            }
            .disabled(!(store?.selectedBufferCanSaveLargeFileChunkBack ?? false))

            Button("Edit Large-File Chunk") {
                store?.enableSelectedLargeFileChunkEditing()
            }
            .disabled(!(store?.selectedLargeFileCanEnableChunkEditing ?? false))

            Button("Replace Large-File Line...") {
                store?.replaceSelectedLargeFileLineWithPrompt()
            }
            .disabled(!(store?.selectedLargeFileCanReplaceLine ?? false))

            Button("Insert Large-File Line...") {
                store?.insertSelectedLargeFileLineWithPrompt()
            }
            .disabled(!(store?.selectedLargeFileCanReplaceLine ?? false))

            Button("Delete Large-File Line...") {
                store?.deleteSelectedLargeFileLineWithPrompt()
            }
            .disabled(!(store?.selectedLargeFileCanReplaceLine ?? false))

            Button("Replace Large-File Lines...") {
                store?.replaceSelectedLargeFileLinesWithPrompt()
            }
            .disabled(!(store?.selectedLargeFileCanReplaceLine ?? false))

            Button("Insert Large-File Lines...") {
                store?.insertSelectedLargeFileLinesWithPrompt()
            }
            .disabled(!(store?.selectedLargeFileCanReplaceLine ?? false))

            Button("Delete Large-File Lines...") {
                store?.deleteSelectedLargeFileLinesWithPrompt()
            }
            .disabled(!(store?.selectedLargeFileCanReplaceLine ?? false))

            Button("Save Numbered Version") {
                store?.saveVersionedCopyOfSelected()
            }

            Button("Save With Numbered Backup") {
                store?.saveSelectedWithNumberedBackup()
            }

            Button("Save Encrypted Copy...") {
                store?.saveSelectedEncryptedWithPrompt()
            }
            .disabled(!(store?.selectedBufferCanSave ?? false))

            Divider()

            Button("Export HTML...") {
                store?.exportSelectedAsHTML()
            }

            Button("Export PDF...") {
                store?.exportSelectedAsPDF()
            }

            Button("Export Word...") {
                store?.exportSelectedAsWord()
            }

            Button("Export Drawing as SVG...") {
                store?.exportSelectedDrawingAsSVG()
            }
            .disabled(!(store?.selectedBuffer?.language.isWhiteboard ?? false))

            Button("Export Drawing as PNG...") {
                store?.exportSelectedDrawingAsPNG()
            }
            .disabled(!(store?.selectedBuffer?.language.isWhiteboard ?? false))

            Button("Copy Drawing as PNG") {
                store?.copySelectedDrawingAsPNG()
            }
            .disabled(!(store?.selectedBuffer?.language.isWhiteboard ?? false))

            Button("Insert Drawing Widget") {
                store?.insertDrawingWidgetIntoMarkdown()
            }
            .disabled(!(
                store?.selectedBuffer?.language.isWhiteboard == true ||
                store?.selectedBuffer?.language.isMarkdown == true
            ))

            Button("Export CSV/TSV as Excel...") {
                store?.exportSelectedDelimitedTableAsExcel()
            }
            .disabled(!(store?.selectedBuffer?.language.isDelimitedTable ?? false))

            Divider()

            Button("Commit Current File...") {
                store?.commitSelectedFileWithPrompt()
            }
            .disabled(store?.selectedGitRepository == nil || !(store?.selectedBufferCanSave ?? false))

            Divider()

            Button("Add Finder Tag...") {
                store?.addFinderTagToSelectedFileWithPrompt()
            }
            .disabled(store?.selectedBuffer?.filePath == nil)

            Button("Clear Finder Tags") {
                store?.clearFinderTagsForSelectedFile()
            }
            .disabled(store?.selectedBuffer?.filePath == nil || store?.selectedFinderTags.isEmpty != false)

            Divider()

            Button(store?.selectedSavePolicy == .readOnly ? "Disable Read-Only Mode" : "Enable Read-Only Mode") {
                store?.toggleReadOnlyMode()
            }

            Button(store?.selectedSavePolicy == .temporary ? "Disable Temporary Mode" : "Enable Temporary Mode") {
                store?.toggleTemporaryMode()
            }

            Button("Allow Saving") {
                store?.setSelectedSavePolicy(.normal)
            }
            .disabled(store?.selectedSavePolicy == .normal)

            Divider()

            Button("Close Buffer") {
                store?.closeSelected()
            }
            .keyboardShortcut("w", modifiers: [.command])

            Button("Force Close Buffer") {
                store?.forceCloseSelected()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(store?.selectedBuffer == nil)
        }

        CommandMenu("Find") {
            Button("Find") {
                store?.showFind()
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Find and Replace") {
                store?.showReplace()
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button("Find in Files") {
                store?.showGlobalFind()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Replace in Files") {
                store?.showGlobalFind()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Select All Matches") {
                store?.selectAllMatches()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button("Find Next") {
                store?.findNext()
            }
            .keyboardShortcut("g", modifiers: [.command])

            Button("Find Previous") {
                store?.findPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button("Add Next Occurrence") {
                store?.addNextOccurrence()
            }
            .keyboardShortcut("g", modifiers: [.command, .option])

            Button("Add Previous Occurrence") {
                store?.addPreviousOccurrence()
            }
            .keyboardShortcut("g", modifiers: [.command, .option, .shift])

            Button("Single Cursor") {
                store?.escape()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }

        CommandMenu("Navigate") {
            Button("Command Palette") {
                store?.showCommandPalette()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Button(store?.isDocumentCatalogVisible == true ? "Hide Documents Sidebar" : "Show Documents Sidebar") {
                store?.toggleDocumentCatalog()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])

            Divider()

            Button("Split Selection Into Lines") {
                store?.performEditorCommand(.splitSelectionIntoLines)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Expand Selection to Line") {
                store?.performEditorCommand(.expandSelectionToLine)
            }
            .keyboardShortcut("l", modifiers: [.command])

            Divider()

            Button("Toggle Fold") {
                store?.toggleStructuredFoldAtSelection()
            }
            .disabled(!(store?.selectedBufferSupportsStructuredFolding ?? false))

            Button("Unfold All") {
                store?.unfoldAllStructuredBlocks()
            }
            .disabled(!(store?.selectedBufferSupportsStructuredFolding ?? false))
        }

        CommandMenu("Workflow") {
            Button("New Workspace...") {
                workspace.createWorkspaceWithPrompt()
            }

            Button("Rename Current Workspace...") {
                workspace.renameActiveWorkspaceWithPrompt()
            }

            Menu("Switch Workspace") {
                ForEach(workspace.workspaceProfiles) { profile in
                    Button(profile.name) {
                        workspace.switchWorkspace(profile.id)
                    }
                    .disabled(profile.id == workspace.activeWorkspaceID)
                }
            }

            Divider()

            Button("Add Comment") {
                store?.addCommentToSelection()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button(store?.isCommentsPanelVisible == true ? "Hide Comments" : "Show Comments") {
                store?.toggleCommentsPanel()
            }

            Button(store?.isScribePanelVisible == true ? "Hide Scribe" : "Show Scribe") {
                store?.toggleScribePanel()
            }

            Button(store?.isVoiceScribeRunning == true ? "Stop Voice Scribe" : "Start Voice Scribe") {
                store?.toggleVoiceScribe()
            }

            Divider()

            Button(store?.isTasksPanelVisible == true ? "Hide Tasks" : "Show Tasks") {
                store?.toggleTasksPanel()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("New Task...") {
                store?.addManualTaskWithPrompt()
            }

            Button("Generate PO Mode Brief") {
                store?.generatePOModeBriefForDocumentCatalog()
            }
            .disabled(store?.documentCatalogRootPath == nil)

            Button("Add PO Gaps as Tasks") {
                store?.addPOModeGapsAsTasks()
            }
            .disabled(store?.documentCatalogRootPath == nil && store?.poModeReport == nil)

            Button(store?.isPOModePanelVisible == true ? "Hide PO Mode" : "Open PO Mode Panel") {
                store?.togglePOModePanel()
            }
            .disabled(store?.documentCatalogRootPath == nil)

            Divider()

            Button(store?.isMacrosPanelVisible == true ? "Hide Macros" : "Show Macros") {
                store?.toggleMacrosPanel()
            }

            Button("Create Macro From Selection...") {
                store?.createTextMacroFromSelectionWithPrompt()
            }

            Button(store?.actionMacroRecording == nil ? "Start Macro Recording..." : "Stop Macro Recording...") {
                if store?.actionMacroRecording == nil {
                    store?.startActionMacroRecordingWithPrompt()
                } else {
                    store?.stopActionMacroRecordingWithPrompt()
                }
            }

            Button("Discard Macro Recording") {
                store?.cancelActionMacroRecording()
            }
            .disabled(store?.actionMacroRecording == nil)

            if let actionMacros = store?.customActionMacros, !actionMacros.isEmpty {
                Divider()

                ForEach(actionMacros) { macro in
                    Button("Play \(macro.title)") {
                        store?.applyActionMacro(macro)
                    }
                }
            }

            Button("Insert PRD Template") {
                if let macro = TextMacro.builtIns.first(where: { $0.id == "built-in:prd" }) {
                    store?.applyTextMacro(macro)
                }
            }

            Button("Insert 1x1 Template") {
                if let macro = TextMacro.builtIns.first(where: { $0.id == "built-in:1x1" }) {
                    store?.applyTextMacro(macro)
                }
            }

            Divider()

            Button(store?.isStatsPanelVisible == true ? "Hide Stats" : "Show Stats") {
                store?.toggleStatsPanel()
            }

            Button(store?.isUsageActivityWatchEnabled == true ? "Stop Activity Watch" : "Start Activity Watch") {
                store?.toggleUsageActivityWatch()
            }

            Button("Create Today's Timelog") {
                store?.createTodayTimelogScratch()
            }
        }

        CommandMenu("Text") {
            Button("Add Next Occurrence") {
                store?.addNextOccurrence()
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button("Duplicate Line") {
                store?.performTextTransform(.duplicateLine)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Button(TextTransform.uppercase.title) {
                store?.performTextTransform(.uppercase)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Button(TextTransform.lowercase.title) {
                store?.performTextTransform(.lowercase)
            }
            .keyboardShortcut("u", modifiers: [.command, .option])

            Button(TextTransform.titlecase.title) {
                store?.performTextTransform(.titlecase)
            }
            .keyboardShortcut("t", modifiers: [.command, .option, .shift])

            Button(TextTransform.swapCase.title) {
                store?.performTextTransform(.swapCase)
            }

            Button(TextTransform.reverseSelection.title) {
                store?.performTextTransform(.reverseSelection)
            }

            Divider()

            Button(TextTransform.sortLines.title) {
                store?.performTextTransform(.sortLines)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button(TextTransform.uniqueLines.title) {
                store?.performTextTransform(.uniqueLines)
            }
            .keyboardShortcut("u", modifiers: [.command, .option, .shift])

            Button(TextTransform.trimTrailingWhitespace.title) {
                store?.performTextTransform(.trimTrailingWhitespace)
            }
            .keyboardShortcut("w", modifiers: [.command, .option])

            Button(TextTransform.joinLines.title) {
                store?.performTextTransform(.joinLines)
            }
            .keyboardShortcut("j", modifiers: [.command])

            Divider()

            Button(TextTransform.formatJSON.title) {
                store?.performTextTransform(.formatJSON)
            }

            Button(TextTransform.minifyJSON.title) {
                store?.performTextTransform(.minifyJSON)
            }

            Button(TextTransform.formatMarkdownTables.title) {
                store?.performTextTransform(.formatMarkdownTables)
            }

            Divider()

            Button("Delete Line") {
                store?.performEditorCommand(.deleteLine)
            }

            Button("Move Line Up") {
                store?.performEditorCommand(.moveLineUp)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])

            Button("Move Line Down") {
                store?.performEditorCommand(.moveLineDown)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Button("Indent Lines") {
                store?.performEditorCommand(.indentLines)
            }
            .keyboardShortcut("]", modifiers: [.command])

            Button("Outdent Lines") {
                store?.performEditorCommand(.outdentLines)
            }
            .keyboardShortcut("[", modifiers: [.command])

            Button("Toggle Comment") {
                store?.performEditorCommand(.toggleComment)
            }
        }

        CommandMenu("Markdown") {
            Button("Source Mode") {
                store?.showSourceMode()
            }
            .keyboardShortcut("1", modifiers: [.command, .option])

            Button("Preview Split Mode") {
                store?.showMarkdownPreviewMode()
            }
            .keyboardShortcut("2", modifiers: [.command, .option])

            Button("WYSIWYG Mode") {
                store?.showMarkdownWysiwygMode()
            }
            .keyboardShortcut("3", modifiers: [.command, .option])

            Divider()

            Button(store?.isWysiwygModeEnabled == true ? "Disable WYSIWYG Mode" : "Enable WYSIWYG Mode") {
                store?.toggleWysiwygMode()
            }
            .keyboardShortcut("/", modifiers: [.command])
            .disabled(!(store?.selectedBuffer?.language.isMarkdown ?? false))

            Divider()

            Button("Bold") {
                store?.performMarkdownCommand(.bold)
            }
            .keyboardShortcut("b", modifiers: [.command])

            Button("Italic") {
                store?.performMarkdownCommand(.italic)
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button("Inline Code") {
                store?.performMarkdownCommand(.inlineCode)
            }

            Button("Strikethrough") {
                store?.performMarkdownCommand(.strikethrough)
            }

            Button("Highlight") {
                store?.performMarkdownCommand(.highlight)
            }

            Button("Subscript") {
                store?.performMarkdownCommand(.subscriptText)
            }

            Button("Superscript") {
                store?.performMarkdownCommand(.superscriptText)
            }

            Divider()

            Button("Heading 1") {
                store?.performMarkdownCommand(.heading1)
            }

            Button("Heading 2") {
                store?.performMarkdownCommand(.heading2)
            }

            Button("Heading 3") {
                store?.performMarkdownCommand(.heading3)
            }

            Divider()

            Button("Bullet List") {
                store?.performMarkdownCommand(.unorderedList)
            }

            Button("Numbered List") {
                store?.performMarkdownCommand(.orderedList)
            }

            Button("Task List") {
                store?.performMarkdownCommand(.taskList)
            }

            Button("Link") {
                store?.performMarkdownCommand(.link)
            }

            Button("Image") {
                store?.performMarkdownCommand(.image)
            }

            Button("Table") {
                store?.performMarkdownCommand(.table)
            }

            Button("Quote") {
                store?.performMarkdownCommand(.quote)
            }

            Button("Code Fence") {
                store?.performMarkdownCommand(.codeFence)
            }

            Button("Math Block") {
                store?.performMarkdownCommand(.mathBlock)
            }

            Button("Mermaid Diagram") {
                store?.performMarkdownCommand(.mermaidDiagram)
            }
        }

        CommandMenu("AI") {
            Button(store?.isAIPanelVisible == true ? "Hide AI Panel" : "Show AI Panel") {
                store?.toggleAIPanel()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button(store?.isCompanionPanelVisible == true ? "Hide Companion" : "Show Companion") {
                store?.toggleCompanionPanel()
            }

            Button(store?.isCompanionAutoScanEnabled == true ? "Disable Live Companion" : "Enable Live Companion") {
                store?.toggleCompanionAutoScan()
            }

            Button("Run Companion Scan") {
                store?.runCompanionScan()
            }

            Button("Translate Selection...") {
                store?.translateSelectionWithPrompt()
            }
            .disabled(store?.isTranslationRunning == true)

            Divider()

            Button("New Copilot Chat") {
                store?.createAIChat(provider: .copilot)
            }

            Button("New Codex Chat") {
                store?.createAIChat(provider: .codex)
            }

            Button("New HTTP LLM Chat") {
                store?.createAIChat(provider: .openAICompatible)
            }

            Button("New Anthropic Chat") {
                store?.createAIChat(provider: .anthropic)
            }

            Button("New Gemini Chat") {
                store?.createAIChat(provider: .gemini)
            }
        }

        CommandGroup(replacing: .toolbar) {
            Button("Increase Font Size") {
                store?.increaseFontSize()
            }
            .keyboardShortcut("+", modifiers: [.command])

            Button("Decrease Font Size") {
                store?.decreaseFontSize()
            }
            .keyboardShortcut("-", modifiers: [.command])

            Divider()

            Button(previewCommandTitle) {
                store?.toggleRenderedPreview()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(!(store?.selectedBuffer?.language.supportsRenderedPreview ?? false))

            Button(store?.isOutlineVisible == true ? "Hide Markdown Outline" : "Show Markdown Outline") {
                store?.toggleMarkdownOutline()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])

            Button(store?.isWysiwygModeEnabled == true ? "Disable WYSIWYG Mode" : "Enable WYSIWYG Mode") {
                store?.toggleWysiwygMode()
            }

            Button(store?.isMiniMapVisible == true ? "Hide Minimap" : "Show Minimap") {
                store?.toggleMiniMap()
            }
            .keyboardShortcut("4", modifiers: [.command, .option])

            Button(store?.isFocusModeEnabled == true ? "Disable Focus Mode" : "Enable Focus Mode") {
                store?.toggleFocusMode()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Button(store?.isTypewriterModeEnabled == true ? "Disable Typewriter Mode" : "Enable Typewriter Mode") {
                store?.toggleTypewriterMode()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Button(store?.isTerminalPanelVisible == true ? "Hide Terminal" : "Show Terminal") {
                store?.toggleTerminalPanel()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])

            Button("Restart Terminal") {
                if let id = store?.selectedTerminalSessionID {
                    store?.restartTerminalSession(id)
                }
            }
            .disabled(store?.selectedTerminalSessionID == nil)

            Button("Run Terminal Diagnostics") {
                store?.runSelectedTerminalDiagnostics()
            }
            .disabled(store == nil)

            Button("Create Editor Diagnostics") {
                store?.createEditorDiagnosticsScratch()
            }
            .disabled(store?.selectedBuffer == nil)

            Button(store?.wrapsLines == true ? "Disable Word Wrap" : "Enable Word Wrap") {
                store?.toggleWrapLines()
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
        }
    }
}
