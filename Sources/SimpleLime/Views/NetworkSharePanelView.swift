import SwiftUI

struct NetworkSharePanelView: View {
    @ObservedObject var store: EditorStore
    @ObservedObject private var network: NetworkShareService

    init(store: EditorStore) {
        self.store = store
        _network = ObservedObject(wrappedValue: store.networkShare)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 280, idealWidth: 330, maxWidth: 430)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .foregroundStyle(.secondary)
            Text("Devices")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                store.toggleNetworkPanel()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Hide devices")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                localDevice
                collaborationStatus
                relayControls

                if network.peers.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 8) {
                        ForEach(network.peers) { peer in
                            peerRow(peer)
                        }
                    }
                }

                if let status = network.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(14)
        }
    }

    private var localDevice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This Mac")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(network.localDisplayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var relayControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                Text("Internet Relay")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            if let relay = store.collaborationRelayState {
                Text(relay.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(relay.shareURL.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else {
                Text("Host this document through a self-hosted relay or join a relay link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    store.startSelfHostedCollaborationRelay()
                } label: {
                    Label("Host", systemImage: "antenna.radiowaves.left.and.right")
                }
                .controlSize(.small)

                Button {
                    store.joinCollaborationRelayWithPrompt()
                } label: {
                    Label("Join", systemImage: "link.badge.plus")
                }
                .controlSize(.small)

                Button {
                    store.copyCollaborationRelayLink()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(store.collaborationRelayState?.shareURL == nil)
                .help("Copy relay link")

                Button {
                    store.stopCollaborationRelay()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(store.collaborationRelayState?.isRunning != true)
                .help("Stop relay")
            }

            if let status = store.collaborationRelayStatus {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var collaborationStatus: some View {
        if let session = store.collaborationSession {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "person.2")
                        .foregroundStyle(.blue)
                    Text("Collaboration")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Leave") {
                        store.endCollaboration()
                    }
                    .controlSize(.small)
                }

                Text(session.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No SimpleLime devices found")
                .font(.system(size: 13, weight: .semibold))
            Text("Open SimpleLime on another Mac connected to the same local network.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }

    private func peerRow(_ peer: NetworkPeer) -> some View {
        HStack(spacing: 10) {
            Image(systemName: peer.isTrusted ? "checkmark.shield" : "macbook")
                .foregroundStyle(peer.isTrusted ? .green : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(peer.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(peer.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if peer.isTrusted {
                Button {
                    store.inviteNetworkPeerToCollaborate(peer.deviceID)
                } label: {
                    Image(systemName: "person.2.wave.2")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(!peer.isAvailable && !peer.isConnected)
                .help("Invite to collaborate")

                Button {
                    store.sendSelectedBuffer(to: peer.deviceID)
                } label: {
                    Image(systemName: "paperplane")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(!peer.isAvailable && !peer.isConnected)
                .help("Send current note")

                Button {
                    store.removeTrustedNetworkDevice(peer.deviceID)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Forget device")
            } else {
                Button("Pair") {
                    store.pairNetworkPeer(peer.deviceID)
                }
                .controlSize(.small)
                .disabled(!peer.isAvailable)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
