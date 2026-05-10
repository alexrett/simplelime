import SwiftUI

struct AIChatPanelView: View {
    @ObservedObject var store: EditorStore
    let buffer: EditorBuffer

    @State private var selectedProvider: AIAgentProvider = .copilot
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let session = selectedSession {
                messagesView(session: session)
                composer(session: session)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 260, idealWidth: 390, maxWidth: 500)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var currentBuffer: EditorBuffer {
        store.buffers.first(where: { $0.id == buffer.id }) ?? buffer
    }

    private var selectedSession: AIChatSession? {
        store.selectedAIChatSession(in: buffer.id)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text("AI")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    store.toggleAIPanel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Hide AI")
            }

            HStack(spacing: 8) {
                Picker("Agent", selection: $selectedProvider) {
                    ForEach(AIAgentProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 118)
                .controlSize(.small)

                Button {
                    store.createAIChat(provider: selectedProvider)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("New chat")

                if !currentBuffer.aiSessions.isEmpty {
                    Picker("Session", selection: sessionSelectionBinding) {
                        ForEach(currentBuffer.aiSessions) { session in
                            Text(session.title).tag(Optional(session.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .controlSize(.small)
                } else {
                    Spacer()
                }

                if let selectedSession {
                    Button {
                        store.deleteAIChat(selectedSession.id, in: buffer.id)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Delete chat")
                    .disabled(store.isAIRunning(selectedSession.id))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sessionSelectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedSession?.id },
            set: { store.selectAIChat($0, in: buffer.id) }
        )
    }

    private func messagesView(session: AIChatSession) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session.messages) { message in
                            AIMessageRow(message: message)
                                .id(message.id)
                        }

                        if let status = store.aiStatus(for: session.id) {
                            HStack(spacing: 6) {
                                if store.isAIRunning(session.id) {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(status)
                                    .lineLimit(2)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 14)
                }
                .onChange(of: session.messages.last?.id) { _, id in
                    if let id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func composer(session: AIChatSession) -> some View {
        VStack(spacing: 8) {
            Divider()

            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(height: 86)

                if draft.isEmpty {
                    Text("Ask \(session.provider.displayName) to edit or explain this tab")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
            }

            HStack {
                Text("cmd+return")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if store.isAIRunning(session.id) {
                    Button {
                        store.cancelAIChat(session.id)
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                }

                Button {
                    send(session: session)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isAIRunning(session.id))
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No AI chat")
                .font(.headline)
            Button {
                store.createAIChat(provider: selectedProvider)
            } label: {
                Label("New Chat", systemImage: "plus")
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func send(session: AIChatSession) {
        let text = draft
        draft = ""
        store.sendAIMessage(text, in: buffer.id, sessionID: session.id)
    }
}

private struct AIMessageRow: View {
    let message: AIChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 44)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .semibold))
                    Text(label)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Text(message.text)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: message.role == .user ? 360 : 430, alignment: .leading)

            if message.role != .user {
                Spacer(minLength: 44)
            }
        }
        .padding(.horizontal, 14)
    }

    private var label: String {
        switch message.role {
        case .user: "You"
        case .assistant: "Assistant"
        case .system: "SimpleLime"
        }
    }

    private var iconName: String {
        switch message.role {
        case .user: "person.fill"
        case .assistant: "sparkles"
        case .system: "exclamationmark.circle"
        }
    }

    private var background: Color {
        switch message.role {
        case .user:
            Color(nsColor: .controlAccentColor).opacity(0.18)
        case .assistant:
            Color(nsColor: .controlBackgroundColor)
        case .system:
            Color.secondary.opacity(0.10)
        }
    }
}
