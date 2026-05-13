import SwiftUI

struct CompanionPanelView: View {
    @ObservedObject var store: EditorStore
    let buffer: EditorBuffer

    private var currentBuffer: EditorBuffer {
        store.buffers.first(where: { $0.id == buffer.id }) ?? buffer
    }

    private var suggestions: [CompanionSuggestion] {
        store.companionSuggestions(for: buffer.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if suggestions.isEmpty {
                emptyState
            } else {
                suggestionList
            }
        }
        .frame(minWidth: 280, idealWidth: 380, maxWidth: 500)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
                Text("Companion")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    store.toggleCompanionPanel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Hide companion")
            }

            HStack(spacing: 8) {
                if store.isCompanionRunning {
                    Button {
                        store.cancelCompanionScan()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                }

                Button {
                    store.runCompanionScan()
                } label: {
                    Label("Scan", systemImage: "sparkles")
                }
                .disabled(store.isCompanionRunning || currentBuffer.language.isBinaryPreview)

                Spacer()
            }
            .controlSize(.small)

            if let status = store.companionStatus {
                HStack(spacing: 6) {
                    if store.isCompanionRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(status)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "eye")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No suggestions")
                .font(.headline)
            Button {
                store.runCompanionScan()
            } label: {
                Label("Scan Current Tab", systemImage: "sparkles")
            }
            .disabled(store.isCompanionRunning || currentBuffer.language.isBinaryPreview)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(suggestions) { suggestion in
                    CompanionSuggestionRow(
                        suggestion: suggestion,
                        onApply: {
                            store.applyCompanionSuggestion(suggestion.id, in: buffer.id)
                        },
                        onComment: {
                            store.addCompanionSuggestionAsComment(suggestion.id, in: buffer.id)
                        }
                    )
                }
            }
            .padding(12)
        }
    }
}

private struct CompanionSuggestionRow: View {
    let suggestion: CompanionSuggestion
    let onApply: () -> Void
    let onComment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(suggestion.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                Spacer()
                if suggestion.isApplied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Applied")
                }
            }

            if !suggestion.comment.isEmpty {
                Text(suggestion.comment)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if suggestion.hasPatchEdit, let patchText = suggestion.patchText {
                Text(patchText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if suggestion.canApplyEdit {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.findText)
                        .foregroundStyle(.red)
                    Text(suggestion.replacementText)
                        .foregroundStyle(.green)
                }
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    onApply()
                } label: {
                    Label("Apply", systemImage: "checkmark")
                }
                .disabled(!suggestion.canApplyEdit || suggestion.isApplied)

                Button {
                    onComment()
                } label: {
                    Label("Comment", systemImage: "text.bubble")
                }
                .disabled(!suggestion.canAddComment)

                Spacer()
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }
}
