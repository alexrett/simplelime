import SwiftUI

struct SimpleLimeCommands: Commands {
    @ObservedObject var workspace: WorkspaceStore

    private var store: EditorStore? {
        workspace.activeStore
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

            Button("New Window") {
                workspace.newWindow()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open File...") {
                store?.openFiles()
            }
            .keyboardShortcut("o", modifiers: [.command])

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

            Divider()

            Button("Close Buffer") {
                store?.closeSelected()
            }
            .keyboardShortcut("w", modifiers: [.command])
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
        }

        CommandMenu("Comments") {
            Button("Add Comment") {
                store?.addCommentToSelection()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button(store?.isCommentsPanelVisible == true ? "Hide Comments" : "Show Comments") {
                store?.toggleCommentsPanel()
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

            Divider()

            Button("New Copilot Chat") {
                store?.createAIChat(provider: .copilot)
            }

            Button("New Codex Chat") {
                store?.createAIChat(provider: .codex)
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

            Button(store?.isPreviewVisible == true ? "Hide Markdown Preview" : "Show Markdown Preview") {
                store?.toggleMarkdownPreview()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

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

            Button(store?.wrapsLines == true ? "Disable Word Wrap" : "Enable Word Wrap") {
                store?.toggleWrapLines()
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
        }
    }
}
