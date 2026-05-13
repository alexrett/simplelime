import SwiftUI

struct TextMacroPanelView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    recordingStatus
                    macroSection("Built In", macros: TextMacro.builtIns)
                    macroSection("Custom", macros: store.customTextMacros)
                    actionMacroSection("Recorded", macros: store.customActionMacros)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.badge.plus")
                .foregroundStyle(.secondary)
            Text("Macros")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                if store.actionMacroRecording == nil {
                    store.startActionMacroRecordingWithPrompt()
                } else {
                    store.stopActionMacroRecordingWithPrompt()
                }
            } label: {
                Image(systemName: store.actionMacroRecording == nil ? "record.circle" : "stop.circle.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.actionMacroRecording == nil ? Color.secondary : Color.red)
            .help(store.actionMacroRecording == nil ? "Record action macro" : "Stop recording")

            Button {
                store.createTextMacroFromSelectionWithPrompt()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Create macro from selection")

            Button {
                store.toggleMacrosPanel()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Hide macros")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var recordingStatus: some View {
        if let recording = store.actionMacroRecording {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                Text("Recording")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(recording.steps.count)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    store.stopActionMacroRecordingWithPrompt()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Stop recording")

                Button {
                    store.cancelActionMacroRecording()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Discard recording")
            }
            .padding(9)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.red.opacity(0.35), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func macroSection(_ title: String, macros: [TextMacro]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if macros.isEmpty {
                Text("No macros")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .center)
            } else {
                ForEach(macros) { macro in
                    TextMacroRowView(
                        macro: macro,
                        isPinned: store.isTextMacroPinned(macro.id),
                        onInsert: {
                            store.applyTextMacro(macro)
                        },
                        onTogglePin: {
                            store.toggleTextMacroPinned(macro.id)
                        },
                        onDelete: macro.isBuiltIn ? nil : {
                            store.deleteCustomTextMacro(macro.id)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func actionMacroSection(_ title: String, macros: [ActionMacro]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if macros.isEmpty {
                Text("No recordings")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .center)
            } else {
                ForEach(macros) { macro in
                    ActionMacroRowView(
                        macro: macro,
                        isPinned: store.isActionMacroPinned(macro.id),
                        onPlay: {
                            store.applyActionMacro(macro)
                        },
                        onTogglePin: {
                            store.toggleActionMacroPinned(macro.id)
                        },
                        onDelete: {
                            store.deleteCustomActionMacro(macro.id)
                        }
                    )
                }
            }
        }
    }
}

private struct TextMacroRowView: View {
    let macro: TextMacro
    let isPinned: Bool
    let onInsert: () -> Void
    let onTogglePin: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(macro.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                .help(isPinned ? "Unpin macro button" : "Pin macro as a button")

                Button(action: onInsert) {
                    Image(systemName: "text.insert")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Insert macro")

                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Delete macro")
                }
            }

            Text(macro.body)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct ActionMacroRowView: View {
    let macro: ActionMacro
    let isPinned: Bool
    let onPlay: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    private var stepPreview: String {
        macro.steps
            .prefix(5)
            .map(\.title)
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(macro.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(macro.steps.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                .help(isPinned ? "Unpin macro button" : "Pin macro as a button")

                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Play macro")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete macro")
            }

            Text(stepPreview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }
}
