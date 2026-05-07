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

            Button("Find in All Tabs") {
                store?.showGlobalFind()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Select All Matches") {
                store?.selectAllMatches()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

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

            Button("Single Cursor") {
                store?.escape()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }

        CommandMenu("Text") {
            Button("Duplicate Line") {
                store?.performTextTransform(.duplicateLine)
            }
            .keyboardShortcut("d", modifiers: [.command])

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
            .keyboardShortcut("t", modifiers: [.command, .option])

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
                store?.isPreviewVisible.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }
}
