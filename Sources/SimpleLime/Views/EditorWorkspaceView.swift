import SwiftUI

struct EditorWorkspaceView: View {
    @ObservedObject var store: EditorStore
    let buffer: EditorBuffer

    var body: some View {
        VStack(spacing: 0) {
            if store.isAIPanelVisible {
                HSplitView {
                    mainEditorContent
                        .frame(minWidth: 480)
                    AIChatPanelView(store: store, buffer: buffer)
                }
            } else {
                mainEditorContent
            }

            StatusBarView(store: store, buffer: buffer)
        }
        .clipped()
    }

    private var mainEditorContent: some View {
        Group {
            if store.isPreviewVisible, buffer.language.isMarkdown {
                HSplitView {
                    editor
                        .frame(minWidth: 360)
                    MarkdownPreviewView(text: buffer.text)
                        .frame(minWidth: 320)
                }
            } else {
                editor
            }
        }
    }

    private var editor: some View {
        CodeEditorView(
            text: Binding(
                get: { store.buffers.first(where: { $0.id == buffer.id })?.text ?? "" },
                set: { store.updateText($0, in: buffer.id) }
            ),
            selectionRanges: Binding(
                get: { store.buffers.first(where: { $0.id == buffer.id })?.selectionRanges ?? [.zero] },
                set: { store.updateSelection($0, in: buffer.id) }
            ),
            language: store.buffers.first(where: { $0.id == buffer.id })?.language ?? buffer.language,
            fontSize: store.fontSize,
            onShortcut: handleShortcut,
            onRegisterEditorCommandHandler: { handler in
                store.registerEditorCommandHandler(handler)
            }
        )
        .clipped()
    }

    private func handleShortcut(_ shortcut: EditorShortcut) {
        switch shortcut {
        case .showFind:
            store.showFind()
        case .showReplace:
            store.showReplace()
        case .showGlobalFind:
            store.showGlobalFind()
        case .selectAllMatches:
            store.selectAllMatches()
        case .transform(let transform):
            store.performTextTransform(transform)
        case .increaseFontSize:
            store.increaseFontSize()
        case .decreaseFontSize:
            store.decreaseFontSize()
        case .nextTab:
            store.selectNextTab()
        case .previousTab:
            store.selectPreviousTab()
        case .toggleAI:
            store.toggleAIPanel()
        case .escape:
            store.escape()
        }
    }
}

private struct StatusBarView: View {
    @ObservedObject var store: EditorStore
    let buffer: EditorBuffer

    var body: some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(EditorLanguage.allCases) { language in
                    Button(language.displayName) {
                        store.setLanguage(language)
                    }
                }
            } label: {
                Text(buffer.language.displayName)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text(buffer.filePath ?? "Scratch")
            Text("\((buffer.text as NSString).length) chars")
            Text("\(buffer.text.components(separatedBy: .newlines).count) lines")
            Spacer()
            Text(buffer.isDirty ? "Modified" : "Saved")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}
