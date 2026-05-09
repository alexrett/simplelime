import SwiftUI
import UniformTypeIdentifiers

struct MobileContentView: View {
    @ObservedObject var store: MobileEditorStore
    @ObservedObject private var network: NetworkShareService

    @State private var isImporting = false

    init(store: MobileEditorStore) {
        self.store = store
        _network = ObservedObject(wrappedValue: store.networkShare)
    }

    var body: some View {
        NavigationStack {
            root
                .navigationTitle(store.selectedBuffer?.displayTitle ?? "SimpleLime")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarLeading) {
                        Button {
                            store.newScratch()
                        } label: {
                            Image(systemName: "doc.badge.plus")
                        }
                        Button {
                            isImporting = true
                        } label: {
                            Image(systemName: "folder")
                        }
                    }

                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button {
                            store.showFind()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        Button {
                            store.showNetworkPanel()
                        } label: {
                            Image(systemName: "network")
                        }
                        Button {
                            store.toggleWrapLines()
                        } label: {
                            Image(systemName: store.wrapsLines ? "text.alignleft" : "arrow.left.and.right.text.vertical")
                        }
                        Menu {
                            Button("Uppercase") { store.performTextTransform(.uppercase) }
                            Button("Lowercase") { store.performTextTransform(.lowercase) }
                            Button("Title Case") { store.performTextTransform(.titlecase) }
                            Divider()
                            Button("Sort Lines") { store.performTextTransform(.sortLines) }
                            Button("Unique Lines") { store.performTextTransform(.uniqueLines) }
                            Button("Trim Trailing Whitespace") { store.performTextTransform(.trimTrailingWhitespace) }
                            Button("Duplicate Line") { store.performTextTransform(.duplicateLine) }
                            Button("Join Lines") { store.performTextTransform(.joinLines) }
                        } label: {
                            Image(systemName: "textformat")
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $store.isNetworkPanelVisible) {
            NavigationStack {
                MobileNetworkPanelView(store: store)
                    .navigationTitle("Devices")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                store.hideNetworkPanel()
                            }
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.text, .plainText, .utf8PlainText, .sourceCode, .json, .data],
            allowsMultipleSelection: true,
            onCompletion: store.openImportedFiles
        )
        .alert("Close note?", isPresented: closeAlertBinding, presenting: store.pendingCloseBuffer) { _ in
            Button("Close Without Saving", role: .destructive) {
                store.closePendingBuffer()
            }
            Button("Cancel", role: .cancel) {
                store.cancelPendingClose()
            }
        } message: { buffer in
            Text("\(buffer.displayTitle) has text or unsaved changes.")
        }
        .alert("Trust device?", isPresented: pairAlertBinding, presenting: network.pendingPairRequest) { _ in
            Button("Trust") {
                store.acceptPendingNetworkPair()
            }
            Button("Reject", role: .cancel) {
                store.rejectPendingNetworkPair()
            }
        } message: { request in
            Text("\(request.name) wants to pair with this device.")
        }
        .alert("SimpleLime", isPresented: errorAlertBinding) {
            Button("OK") {
                store.lastError = nil
            }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private var root: some View {
        VStack(spacing: 0) {
            MobileTabStripView(store: store)

            if store.findPanelMode != .hidden {
                MobileFindBar(store: store)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()
                .overlay(Color.white.opacity(0.06))

            editor

            MobileStatusBarView(store: store)
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.11))
    }

    @ViewBuilder
    private var editor: some View {
        if let buffer = store.selectedBuffer {
            MobileCodeEditorView(
                text: Binding(
                    get: { store.buffer(id: buffer.id)?.text ?? "" },
                    set: { store.updateText($0, in: buffer.id) }
                ),
                selectionRanges: Binding(
                    get: { store.buffer(id: buffer.id)?.selectionRanges ?? [.zero] },
                    set: { store.updateSelection($0, in: buffer.id) }
                ),
                language: buffer.language,
                fontSize: store.fontSize,
                wrapsLines: store.wrapsLines
            )
            .id(buffer.id)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("No Note")
                    .font(.headline)
                Text("Create a new scratch note.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var closeAlertBinding: Binding<Bool> {
        Binding(
            get: { store.pendingCloseBuffer != nil },
            set: { if !$0 { store.cancelPendingClose() } }
        )
    }

    private var pairAlertBinding: Binding<Bool> {
        Binding(
            get: { network.pendingPairRequest != nil },
            set: { if !$0 { store.rejectPendingNetworkPair() } }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }
}

private struct MobileNetworkPanelView: View {
    @ObservedObject var store: MobileEditorStore
    @ObservedObject private var network: NetworkShareService

    init(store: MobileEditorStore) {
        self.store = store
        _network = ObservedObject(wrappedValue: store.networkShare)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This Device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(network.localDisplayName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, 4)
            }

            Section("SimpleLime Devices") {
                if network.peers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No devices found")
                            .font(.headline)
                        Text("Open SimpleLime on another trusted Mac, iPad, or iPhone on the same local network.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(network.peers) { peer in
                        peerRow(peer)
                    }
                }
            }

            if let status = network.statusMessage {
                Section {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.10, green: 0.10, blue: 0.11))
    }

    private func peerRow(_ peer: NetworkPeer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: peer.isTrusted ? "checkmark.shield" : "network")
                .foregroundStyle(peer.isTrusted ? .green : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(peer.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(peer.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if peer.isTrusted {
                Button {
                    store.sendSelectedBuffer(to: peer.deviceID)
                } label: {
                    Image(systemName: "paperplane")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .disabled(!peer.isAvailable && !peer.isConnected)

                Button(role: .destructive) {
                    store.removeTrustedNetworkDevice(peer.deviceID)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
            } else {
                Button("Pair") {
                    store.pairNetworkPeer(peer.deviceID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!peer.isAvailable)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MobileTabStripView: View {
    @ObservedObject var store: MobileEditorStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(store.buffers) { buffer in
                    Button {
                        store.select(buffer.id)
                    } label: {
                        HStack(spacing: 8) {
                            Text(buffer.displayTitle)
                                .lineLimit(1)
                                .font(.system(size: 15, weight: store.selectedBufferID == buffer.id ? .semibold : .regular, design: .rounded))
                            if buffer.isDirty {
                                Circle()
                                    .fill(Color.white.opacity(0.55))
                                    .frame(width: 5, height: 5)
                            }
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    store.requestClose(buffer.id)
                                }
                        }
                        .frame(minWidth: 150, maxWidth: 230, minHeight: 48, alignment: .center)
                        .padding(.horizontal, 10)
                        .background(store.selectedBufferID == buffer.id ? Color(red: 0.14, green: 0.18, blue: 0.24) : Color.clear)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(store.selectedBufferID == buffer.id ? Color.blue : Color.clear)
                                .frame(height: 2)
                        }
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    store.newScratch()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 56, height: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .frame(height: 48)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    }
}

private struct MobileFindBar: View {
    @ObservedObject var store: MobileEditorStore

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Find", text: $store.findQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        store.findNext()
                    }

                Toggle(".*", isOn: $store.findUsesRegex)
                    .toggleStyle(.button)
                    .font(.system(.body, design: .monospaced))

                Button {
                    store.findPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                }
                Button {
                    store.findNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                Button("All") {
                    store.selectAllMatches()
                }
                Button {
                    store.hideFindPanel()
                } label: {
                    Image(systemName: "xmark")
                }
            }

            if store.findPanelMode == .replace {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(.secondary)
                    TextField("Replace", text: $store.replaceText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button("Replace") {
                        store.replaceCurrent()
                    }
                    Button("Replace All") {
                        store.replaceAll()
                    }
                }
            } else {
                HStack {
                    Button("Replace") {
                        store.showReplace()
                    }
                    Spacer()
                }
            }
        }
        .buttonStyle(.bordered)
        .padding(12)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }
}

private struct MobileStatusBarView: View {
    @ObservedObject var store: MobileEditorStore

    var body: some View {
        HStack(spacing: 14) {
            if let buffer = store.selectedBuffer {
                Menu {
                    ForEach(EditorLanguage.allCases) { language in
                        Button(language.displayName) {
                            store.setLanguage(language)
                        }
                    }
                } label: {
                    Label(buffer.language.displayName, systemImage: "chevron.down")
                        .labelStyle(.titleOnly)
                }
                .menuStyle(.button)

                Text(buffer.subtitle)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Text("\((buffer.text as NSString).length) chars")
                    .foregroundStyle(.secondary)

                Text("\(lineCount(buffer.text)) lines")
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    store.decreaseFontSize()
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                Button {
                    store.increaseFontSize()
                } label: {
                    Image(systemName: "textformat.size.larger")
                }

                Text(buffer.isDirty ? "Modified" : "Saved")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    }

    private func lineCount(_ text: String) -> Int {
        max(1, text.components(separatedBy: .newlines).count)
    }
}
