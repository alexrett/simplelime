import XCTest
@testable import SimpleLime

final class CollaborationPatchTests: XCTestCase {
    func testPatchAppliesDirectReplacement() throws {
        let patch = try XCTUnwrap(
            CollaborationTextPatch.make(oldText: "alpha beta gamma", newText: "alpha brave gamma")
        )

        XCTAssertEqual(patch.apply(to: "alpha beta gamma"), "alpha brave gamma")
    }

    func testPatchRelocatesWithContextAfterIndependentPrefixChange() throws {
        let patch = try XCTUnwrap(
            CollaborationTextPatch.make(oldText: "alpha beta gamma", newText: "alpha brave beta gamma")
        )

        XCTAssertEqual(patch.apply(to: "intro\nalpha beta gamma"), "intro\nalpha brave beta gamma")
    }
}

@MainActor
final class EditorStoreCollaborationTests: XCTestCase {
    func testHostInviteSendsInvitePayloadAndStartsSession() throws {
        let network = makeNetwork()
        network.seedTrustedPeerForTesting(deviceID: "peer-1", name: "Peer Mac")
        var sent: [(CollaborationPayload, String)] = []
        network.collaborationSendInterceptor = { payload, deviceID in
            sent.append((payload, deviceID))
            return true
        }

        let store = makeStore(text: "alpha beta", networkShare: network)
        store.updateSelectedSelection([TextRange(location: 5, length: 0)])

        store.inviteNetworkPeerToCollaborate("peer-1")

        let invite = try XCTUnwrap(sent.first)
        XCTAssertEqual(invite.1, "peer-1")
        XCTAssertEqual(invite.0.kind, .invite)
        XCTAssertEqual(invite.0.text, "alpha beta")
        XCTAssertEqual(invite.0.selectionRanges, [TextRange(location: 5, length: 0)])
        XCTAssertEqual(invite.0.sourceDeviceID, network.localDeviceID)
        XCTAssertEqual(invite.0.sourceDeviceName, network.localDisplayName)
        XCTAssertNotNil(invite.0.sourceToken)
        XCTAssertEqual(store.collaborationSession?.collaborators.first?.deviceID, "peer-1")
    }

    func testLocalEditAndSelectionSendPatchPayloadsToCollaborator() throws {
        let network = makeNetwork()
        network.seedTrustedPeerForTesting(deviceID: "peer-1", name: "Peer Mac")
        var sent: [(CollaborationPayload, String)] = []
        network.collaborationSendInterceptor = { payload, deviceID in
            sent.append((payload, deviceID))
            return true
        }

        let store = makeStore(text: "alpha beta", networkShare: network)
        store.inviteNetworkPeerToCollaborate("peer-1")
        sent.removeAll()

        let bufferID = try XCTUnwrap(store.selectedBufferID)
        store.updateText("alpha brave beta", in: bufferID)

        let patchMessage = try XCTUnwrap(sent.first)
        XCTAssertEqual(patchMessage.1, "peer-1")
        XCTAssertEqual(patchMessage.0.kind, .patch)
        XCTAssertEqual(patchMessage.0.patch?.apply(to: "alpha beta"), "alpha brave beta")
        XCTAssertEqual(patchMessage.0.revision, 1)

        sent.removeAll()
        store.updateSelection([TextRange(location: 12, length: 0)], in: bufferID)

        let selectionMessage = try XCTUnwrap(sent.first)
        XCTAssertEqual(selectionMessage.1, "peer-1")
        XCTAssertEqual(selectionMessage.0.kind, .selection)
        XCTAssertEqual(selectionMessage.0.selectionRanges, [TextRange(location: 12, length: 0)])
    }

    func testHostRelaysRemotePatchToOtherCollaboratorsPreservingActor() throws {
        let network = makeNetwork()
        network.seedTrustedPeerForTesting(deviceID: "peer-1", name: "Peer One")
        network.seedTrustedPeerForTesting(deviceID: "peer-2", name: "Peer Two")
        var sent: [(CollaborationPayload, String)] = []
        network.collaborationSendInterceptor = { payload, deviceID in
            sent.append((payload, deviceID))
            return true
        }

        let store = makeStore(text: "alpha beta", networkShare: network)
        store.inviteNetworkPeerToCollaborate("peer-1")
        store.inviteNetworkPeerToCollaborate("peer-2")
        sent.removeAll()

        let sessionID = try XCTUnwrap(store.collaborationSession?.id)
        let patch = try XCTUnwrap(
            CollaborationTextPatch.make(oldText: "alpha beta", newText: "alpha brave beta")
        )
        store.handleCollaborationPayload(
            CollaborationPayload(
                kind: .patch,
                sessionID: sessionID,
                title: "Shared Draft",
                text: nil,
                language: .markdown,
                patch: patch,
                selectionRanges: [TextRange(location: 12, length: 0)],
                revision: 1,
                sentAt: Date(),
                sourceDeviceID: "peer-1",
                sourceDeviceName: "Peer One",
                sourceToken: nil
            )
        )

        XCTAssertEqual(store.selectedBuffer?.text, "alpha brave beta")
        let relayed = try XCTUnwrap(sent.first)
        XCTAssertEqual(relayed.1, "peer-2")
        XCTAssertEqual(relayed.0.kind, .patch)
        XCTAssertEqual(relayed.0.sourceDeviceID, network.localDeviceID)
        XCTAssertEqual(relayed.0.actorDeviceID, "peer-1")
        XCTAssertEqual(relayed.0.actorDeviceName, "Peer One")
        XCTAssertEqual(relayed.0.patch?.apply(to: "alpha beta"), "alpha brave beta")
    }

    func testHostRelaysRemoteSelectionToOtherCollaboratorsPreservingActor() throws {
        let network = makeNetwork()
        network.seedTrustedPeerForTesting(deviceID: "peer-1", name: "Peer One")
        network.seedTrustedPeerForTesting(deviceID: "peer-2", name: "Peer Two")
        var sent: [(CollaborationPayload, String)] = []
        network.collaborationSendInterceptor = { payload, deviceID in
            sent.append((payload, deviceID))
            return true
        }

        let store = makeStore(text: "alpha beta", networkShare: network)
        store.inviteNetworkPeerToCollaborate("peer-1")
        store.inviteNetworkPeerToCollaborate("peer-2")
        sent.removeAll()

        let sessionID = try XCTUnwrap(store.collaborationSession?.id)
        store.handleCollaborationPayload(
            CollaborationPayload(
                kind: .selection,
                sessionID: sessionID,
                title: "Shared Draft",
                text: nil,
                language: .markdown,
                patch: nil,
                selectionRanges: [TextRange(location: 3, length: 2)],
                revision: 0,
                sentAt: Date(),
                sourceDeviceID: "peer-1",
                sourceDeviceName: "Peer One",
                sourceToken: nil
            )
        )

        let relayed = try XCTUnwrap(sent.first)
        XCTAssertEqual(relayed.1, "peer-2")
        XCTAssertEqual(relayed.0.kind, .selection)
        XCTAssertEqual(relayed.0.actorDeviceID, "peer-1")
        XCTAssertEqual(relayed.0.selectionRanges, [TextRange(location: 3, length: 2)])
    }

    func testIncomingInviteCreatesLocalCopyAndRemotePatchUpdatesIt() throws {
        let store = makeStore(text: "")
        let sessionID = UUID()

        store.handleCollaborationPayload(
            CollaborationPayload(
                kind: .invite,
                sessionID: sessionID,
                title: "Shared Draft",
                text: "alpha beta gamma",
                language: .markdown,
                patch: nil,
                selectionRanges: [TextRange(location: 6, length: 0)],
                revision: 0,
                sentAt: Date(),
                sourceDeviceID: "peer-1",
                sourceDeviceName: "Peer Mac",
                sourceToken: nil
            )
        )

        let buffer = try XCTUnwrap(store.selectedBuffer)
        XCTAssertEqual(buffer.title, "Shared Draft")
        XCTAssertEqual(buffer.text, "alpha beta gamma")
        XCTAssertEqual(store.collaborationSession?.id, sessionID)
        XCTAssertEqual(store.collaborationSession?.collaborators.first?.name, "Peer Mac")

        let patch = try XCTUnwrap(
            CollaborationTextPatch.make(oldText: "alpha beta gamma", newText: "alpha brave beta gamma")
        )
        store.handleCollaborationPayload(
            CollaborationPayload(
                kind: .patch,
                sessionID: sessionID,
                title: "Shared Draft",
                text: nil,
                language: .markdown,
                patch: patch,
                selectionRanges: [TextRange(location: 12, length: 0)],
                revision: 1,
                sentAt: Date(),
                sourceDeviceID: "peer-1",
                sourceDeviceName: "Peer Mac",
                sourceToken: nil
            )
        )

        XCTAssertEqual(store.selectedBuffer?.text, "alpha brave beta gamma")
        XCTAssertEqual(store.collaborationSession?.collaborators.first?.selectionRanges, [TextRange(location: 12, length: 0)])
    }

    func testIncomingInviteSendsAcceptPayloadBackToHost() throws {
        let network = makeNetwork()
        network.seedTrustedPeerForTesting(deviceID: "peer-1", name: "Peer Mac")
        var sent: [(CollaborationPayload, String)] = []
        network.collaborationSendInterceptor = { payload, deviceID in
            sent.append((payload, deviceID))
            return true
        }

        let store = makeStore(text: "", networkShare: network)
        let sessionID = UUID()

        store.handleCollaborationPayload(
            CollaborationPayload(
                kind: .invite,
                sessionID: sessionID,
                title: "Shared Draft",
                text: "alpha beta",
                language: .markdown,
                patch: nil,
                selectionRanges: [TextRange(location: 5, length: 0)],
                revision: 0,
                sentAt: Date(),
                sourceDeviceID: "peer-1",
                sourceDeviceName: "Peer Mac",
                sourceToken: nil
            )
        )

        let accept = try XCTUnwrap(sent.first)
        XCTAssertEqual(accept.1, "peer-1")
        XCTAssertEqual(accept.0.kind, .accept)
        XCTAssertEqual(accept.0.sessionID, sessionID)
        XCTAssertNil(accept.0.text)
        XCTAssertNil(accept.0.patch)
    }

    func testRelayedPatchUpdatesActorCollaboratorOnReceiver() throws {
        let network = makeNetwork()
        network.seedTrustedPeerForTesting(deviceID: "host", name: "Host Mac")
        var sent: [(CollaborationPayload, String)] = []
        network.collaborationSendInterceptor = { payload, deviceID in
            sent.append((payload, deviceID))
            return true
        }

        let store = makeStore(text: "", networkShare: network)
        let sessionID = UUID()
        store.handleCollaborationPayload(
            CollaborationPayload(
                kind: .invite,
                sessionID: sessionID,
                title: "Shared Draft",
                text: "alpha beta",
                language: .markdown,
                patch: nil,
                selectionRanges: [.zero],
                revision: 0,
                sentAt: Date(),
                sourceDeviceID: "host",
                sourceDeviceName: "Host Mac",
                sourceToken: nil
            )
        )
        sent.removeAll()

        let patch = try XCTUnwrap(
            CollaborationTextPatch.make(oldText: "alpha beta", newText: "alpha brave beta")
        )
        store.handleCollaborationPayload(
            CollaborationPayload(
                kind: .patch,
                sessionID: sessionID,
                title: "Shared Draft",
                text: nil,
                language: .markdown,
                patch: patch,
                selectionRanges: [TextRange(location: 12, length: 0)],
                revision: 1,
                sentAt: Date(),
                sourceDeviceID: "host",
                sourceDeviceName: "Host Mac",
                sourceToken: nil,
                actorDeviceID: "peer-1",
                actorDeviceName: "Peer One"
            )
        )

        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(store.selectedBuffer?.text, "alpha brave beta")
        XCTAssertTrue(
            store.collaborationSession?.collaborators.contains {
                $0.deviceID == "peer-1" &&
                    $0.name == "Peer One" &&
                    $0.selectionRanges == [TextRange(location: 12, length: 0)]
            } ?? false
        )
    }

    func testLeaveKeepsLocalCopyOpen() throws {
        let store = makeStore(text: "draft")
        let sessionID = UUID()

        store.handleCollaborationPayload(
            CollaborationPayload(
                kind: .invite,
                sessionID: sessionID,
                title: "Shared Draft",
                text: "draft",
                language: .markdown,
                patch: nil,
                selectionRanges: [.zero],
                revision: 0,
                sentAt: Date(),
                sourceDeviceID: "peer-1",
                sourceDeviceName: "Peer Mac",
                sourceToken: nil
            )
        )
        store.handleCollaborationPayload(
            CollaborationPayload(
                kind: .leave,
                sessionID: sessionID,
                title: "Shared Draft",
                text: nil,
                language: nil,
                patch: nil,
                selectionRanges: [],
                revision: 0,
                sentAt: Date(),
                sourceDeviceID: "peer-1",
                sourceDeviceName: "Peer Mac",
                sourceToken: nil
            )
        )

        XCTAssertNil(store.collaborationSession)
        XCTAssertEqual(store.selectedBuffer?.text, "draft")
    }

    func testHostLeaveSendsLeavePayloadAndKeepsLocalCopyOpen() throws {
        let network = makeNetwork()
        network.seedTrustedPeerForTesting(deviceID: "peer-1", name: "Peer Mac")
        var sent: [(CollaborationPayload, String)] = []
        network.collaborationSendInterceptor = { payload, deviceID in
            sent.append((payload, deviceID))
            return true
        }

        let store = makeStore(text: "draft", networkShare: network)
        store.inviteNetworkPeerToCollaborate("peer-1")
        sent.removeAll()

        store.endCollaboration()

        let leave = try XCTUnwrap(sent.first)
        XCTAssertEqual(leave.1, "peer-1")
        XCTAssertEqual(leave.0.kind, .leave)
        XCTAssertNil(store.collaborationSession)
        XCTAssertEqual(store.selectedBuffer?.text, "draft")
    }

    func testSelfHostedRelayCreatesShareLinkAndCollaborationSession() throws {
        let store = makeStore(text: "draft")
        let port = UInt16.random(in: 49_000...60_000)

        store.startSelfHostedCollaborationRelay(port: port)
        defer { store.stopCollaborationRelay() }

        let relay = try XCTUnwrap(store.collaborationRelayState)
        XCTAssertEqual(relay.role, .host)
        XCTAssertEqual(relay.shareURL.scheme, "simplelime")
        XCTAssertTrue(relay.shareURL.absoluteString.contains("room="))
        XCTAssertTrue(store.collaborationSession?.isHost == true)
        XCTAssertTrue(store.isNetworkPanelVisible)
    }

    private func makeStore(text: String, networkShare: NetworkShareService? = nil) -> EditorStore {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = text
        return EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            commentPersistence: nil,
            networkShare: networkShare ?? makeNetwork(),
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func makeNetwork() -> NetworkShareService {
        NetworkShareService(
            userDefaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard,
            startNetworkServices: false
        )
    }
}
