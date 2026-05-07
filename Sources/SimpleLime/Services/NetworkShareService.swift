import Combine
import Foundation
@preconcurrency import MultipeerConnectivity

final class NetworkShareService: NSObject, ObservableObject {
    private static let serviceType = "simplelime"
    private static let localDeviceIDKey = "network.localDeviceID"
    private static let localPairingTokenKey = "network.localPairingToken"
    private static let trustedDevicesKey = "network.trustedDevices"

    @Published private(set) var peers: [NetworkPeer] = []
    @Published private(set) var trustedDevices: [TrustedNetworkDevice]
    @Published var pendingPairRequest: PendingPairRequest?
    @Published var statusMessage: String?

    let localDeviceID: String
    let localDisplayName: String
    private let localPairingToken: String

    var onReceivedNote: ((SharedNotePayload) -> Void)?

    private let userDefaults: UserDefaults
    private let localPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    private var discoveredPeers: [String: DiscoveredPeer] = [:]
    private var deviceIDsByPeerID: [MCPeerID: String] = [:]
    private var pendingInvitationHandler: ((Bool, MCSession?) -> Void)?
    private var outgoingPairDeviceIDs = Set<String>()
    private var pendingNotesByDeviceID: [String: SharedNotePayload] = [:]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedDeviceID = userDefaults.string(forKey: Self.localDeviceIDKey)
        let resolvedDeviceID = storedDeviceID ?? UUID().uuidString
        if storedDeviceID == nil {
            userDefaults.set(resolvedDeviceID, forKey: Self.localDeviceIDKey)
        }

        let storedPairingToken = userDefaults.string(forKey: Self.localPairingTokenKey)
        let resolvedPairingToken = storedPairingToken ?? UUID().uuidString
        if storedPairingToken == nil {
            userDefaults.set(resolvedPairingToken, forKey: Self.localPairingTokenKey)
        }

        localDeviceID = resolvedDeviceID
        localPairingToken = resolvedPairingToken
        localDisplayName = Self.makeDisplayName(deviceID: resolvedDeviceID)
        localPeerID = MCPeerID(displayName: localDisplayName)
        trustedDevices = Self.loadTrustedDevices(from: userDefaults)

        session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: [
                "deviceID": resolvedDeviceID,
                "name": localDisplayName
            ],
            serviceType: Self.serviceType
        )
        browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: Self.serviceType)

        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        refreshPeers()
    }

    deinit {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    func pair(with deviceID: String) {
        guard let peer = discoveredPeers[deviceID], peer.isAvailable else {
            statusMessage = "Device is not available."
            return
        }

        outgoingPairDeviceIDs.insert(deviceID)
        browser.invitePeer(
            peer.peerID,
            to: session,
            withContext: encodeInvitation(type: "pair"),
            timeout: 30
        )
        statusMessage = "Pairing with \(peer.name)..."
    }

    func acceptPendingPair() {
        guard let request = pendingPairRequest,
              let handler = pendingInvitationHandler else {
            return
        }

        addTrustedDevice(id: request.deviceID, name: request.name, token: request.token)
        pendingPairRequest = nil
        pendingInvitationHandler = nil
        handler(true, session)
        statusMessage = "\(request.name) is trusted."
    }

    func rejectPendingPair() {
        pendingPairRequest = nil
        pendingInvitationHandler?(false, nil)
        pendingInvitationHandler = nil
    }

    func removeTrustedDevice(_ deviceID: String) {
        trustedDevices.removeAll { $0.id == deviceID }
        saveTrustedDevices()
        refreshPeers()
    }

    func send(note: SharedNotePayload, to deviceID: String) {
        guard isTrusted(deviceID) else {
            statusMessage = "Pair this device first."
            return
        }

        guard let peer = discoveredPeers[deviceID], peer.isAvailable || peer.isConnected else {
            statusMessage = "Trusted device is offline."
            return
        }

        var trustedNote = note
        trustedNote.sourceToken = localPairingToken

        if peer.isConnected {
            sendNow(note: trustedNote, to: peer)
            return
        }

        pendingNotesByDeviceID[deviceID] = trustedNote
        browser.invitePeer(
            peer.peerID,
            to: session,
            withContext: encodeInvitation(type: "trustedConnect"),
            timeout: 20
        )
        statusMessage = "Connecting to \(peer.name)..."
    }

    private func handleFoundPeer(_ peerID: MCPeerID, info: [String: String]?) {
        guard let deviceID = info?["deviceID"], deviceID != localDeviceID else {
            return
        }

        let name = info?["name"] ?? peerID.displayName
        discoveredPeers[deviceID] = DiscoveredPeer(
            peerID: peerID,
            deviceID: deviceID,
            name: name,
            isAvailable: true,
            isConnected: session.connectedPeers.contains(peerID)
        )
        deviceIDsByPeerID[peerID] = deviceID
        markTrustedDeviceSeen(id: deviceID, name: name)
        refreshPeers()
    }

    private func handleLostPeer(_ peerID: MCPeerID) {
        guard let deviceID = deviceIDsByPeerID[peerID] else {
            return
        }

        discoveredPeers[deviceID]?.isAvailable = false
        refreshPeers()
    }

    private func handleInvitation(from peerID: MCPeerID, context: Data?, handler: @escaping (Bool, MCSession?) -> Void) {
        let invitation = decodeInvitation(context, fallbackName: peerID.displayName)
        deviceIDsByPeerID[peerID] = invitation.deviceID

        discoveredPeers[invitation.deviceID] = DiscoveredPeer(
            peerID: peerID,
            deviceID: invitation.deviceID,
            name: invitation.name,
            isAvailable: true,
            isConnected: false
        )

        if isTrusted(invitation.deviceID, token: invitation.token) {
            markTrustedDeviceSeen(id: invitation.deviceID, name: invitation.name)
            handler(true, session)
            refreshPeers()
            return
        }

        if isTrusted(invitation.deviceID) {
            statusMessage = "Rejected \(invitation.name): trust token did not match."
            handler(false, nil)
            return
        }

        guard invitation.type == "pair" else {
            handler(false, nil)
            return
        }

        pendingInvitationHandler?(false, nil)
        pendingInvitationHandler = handler
        pendingPairRequest = PendingPairRequest(
            deviceID: invitation.deviceID,
            name: invitation.name,
            token: invitation.token
        )
        refreshPeers()
    }

    private func handleConnectionState(_ state: MCSessionState, peerID: MCPeerID) {
        let deviceID = deviceIDsByPeerID[peerID] ?? discoveredPeers.first { $0.value.peerID == peerID }?.key

        guard let deviceID else {
            refreshPeers()
            return
        }

        if var peer = discoveredPeers[deviceID] {
            peer.isConnected = state == .connected
            discoveredPeers[deviceID] = peer
        }

        if state == .connected {
            if let peer = discoveredPeers[deviceID],
               outgoingPairDeviceIDs.contains(deviceID) || isTrusted(deviceID) {
                sendPairAck(to: peer)
            }

            if isTrusted(deviceID),
               let note = pendingNotesByDeviceID.removeValue(forKey: deviceID),
               let peer = discoveredPeers[deviceID] {
                sendNow(note: note, to: peer)
            }
        }

        refreshPeers()
    }

    private func handleReceivedData(_ data: Data, from peerID: MCPeerID) {
        if let control = try? JSONDecoder.networkDecoder.decode(NetworkControlPayload.self, from: data),
           control.type == "pairAck" {
            handlePairAck(control, from: peerID)
            return
        }

        guard let note = try? JSONDecoder.networkDecoder.decode(SharedNotePayload.self, from: data),
              note.type == "note",
              let peerDeviceID = deviceIDsByPeerID[peerID],
              peerDeviceID == note.sourceDeviceID,
              isTrusted(peerDeviceID, token: note.sourceToken) else {
            return
        }

        onReceivedNote?(note)
        statusMessage = "Received \(note.title) from \(note.sourceDeviceName)."
    }

    private func handlePairAck(_ control: NetworkControlPayload, from peerID: MCPeerID) {
        deviceIDsByPeerID[peerID] = control.deviceID
        let wasOutgoingPair = outgoingPairDeviceIDs.remove(control.deviceID) != nil

        guard wasOutgoingPair || isTrusted(control.deviceID) else {
            return
        }

        if var peer = discoveredPeers[control.deviceID] {
            peer.name = control.name
            peer.isConnected = session.connectedPeers.contains(peerID)
            discoveredPeers[control.deviceID] = peer
        }

        addTrustedDevice(id: control.deviceID, name: control.name, token: control.token)
        statusMessage = "\(control.name) is trusted."
    }

    private func sendNow(note: SharedNotePayload, to peer: DiscoveredPeer) {
        do {
            let data = try JSONEncoder.networkEncoder.encode(note)
            try session.send(data, toPeers: [peer.peerID], with: .reliable)
            statusMessage = "Sent \(note.title) to \(peer.name)."
        } catch {
            statusMessage = "Could not send note: \(error.localizedDescription)"
        }
    }

    private func sendPairAck(to peer: DiscoveredPeer) {
        do {
            let data = try JSONEncoder.networkEncoder.encode(
                NetworkControlPayload(
                    type: "pairAck",
                    deviceID: localDeviceID,
                    name: localDisplayName,
                    token: localPairingToken
                )
            )
            try session.send(data, toPeers: [peer.peerID], with: .reliable)
        } catch {
            statusMessage = "Could not confirm pairing: \(error.localizedDescription)"
        }
    }

    private func isTrusted(_ deviceID: String) -> Bool {
        trustedDevices.contains { $0.id == deviceID }
    }

    private func isTrusted(_ deviceID: String, token: String?) -> Bool {
        guard let storedToken = trustedDevices.first(where: { $0.id == deviceID })?.token,
              let token else {
            return false
        }

        return storedToken == token
    }

    private func addTrustedDevice(id: String, name: String, token: String?) {
        if let index = trustedDevices.firstIndex(where: { $0.id == id }) {
            trustedDevices[index].name = name
            trustedDevices[index].token = token
            trustedDevices[index].lastSeenAt = Date()
        } else {
            trustedDevices.append(
                TrustedNetworkDevice(id: id, name: name, token: token, pairedAt: Date(), lastSeenAt: Date())
            )
        }

        saveTrustedDevices()
        refreshPeers()
    }

    private func markTrustedDeviceSeen(id: String, name: String) {
        guard let index = trustedDevices.firstIndex(where: { $0.id == id }) else {
            return
        }

        trustedDevices[index].name = name
        trustedDevices[index].lastSeenAt = Date()
        saveTrustedDevices()
    }

    private func refreshPeers() {
        let discoveredRows = discoveredPeers.values.map { peer in
            NetworkPeer(
                deviceID: peer.deviceID,
                name: trustedDevices.first(where: { $0.id == peer.deviceID })?.name ?? peer.name,
                isTrusted: isTrusted(peer.deviceID),
                isAvailable: peer.isAvailable,
                isConnected: peer.isConnected
            )
        }

        let discoveredIDs = Set(discoveredRows.map(\.deviceID))
        let offlineTrustedRows = trustedDevices
            .filter { !discoveredIDs.contains($0.id) }
            .map {
                NetworkPeer(
                    deviceID: $0.id,
                    name: $0.name,
                    isTrusted: true,
                    isAvailable: false,
                    isConnected: false
                )
            }

        peers = (discoveredRows + offlineTrustedRows).sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected {
                return lhs.isConnected && !rhs.isConnected
            }

            if lhs.isAvailable != rhs.isAvailable {
                return lhs.isAvailable && !rhs.isAvailable
            }

            if lhs.isTrusted != rhs.isTrusted {
                return lhs.isTrusted && !rhs.isTrusted
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func encodeInvitation(type: String) -> Data? {
        try? JSONEncoder.networkEncoder.encode(
            NetworkInvitationContext(
                type: type,
                deviceID: localDeviceID,
                name: localDisplayName,
                token: localPairingToken
            )
        )
    }

    private func decodeInvitation(_ data: Data?, fallbackName: String) -> NetworkInvitationContext {
        if let data,
           let context = try? JSONDecoder.networkDecoder.decode(NetworkInvitationContext.self, from: data) {
            return context
        }

        return NetworkInvitationContext(type: "trustedConnect", deviceID: fallbackName, name: fallbackName, token: nil)
    }

    private func saveTrustedDevices() {
        guard let data = try? JSONEncoder.networkEncoder.encode(trustedDevices) else {
            return
        }

        userDefaults.set(data, forKey: Self.trustedDevicesKey)
    }

    private static func loadTrustedDevices(from userDefaults: UserDefaults) -> [TrustedNetworkDevice] {
        guard let data = userDefaults.data(forKey: trustedDevicesKey),
              let devices = try? JSONDecoder.networkDecoder.decode([TrustedNetworkDevice].self, from: data) else {
            return []
        }

        return devices
    }

    private static func makeDisplayName(deviceID: String) -> String {
        let rawName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let baseName = rawName
            .replacingOccurrences(of: ".local", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shortID = String(deviceID.prefix(6))
        let name = baseName.isEmpty ? "Mac" : baseName
        let maxBaseLength = max(1, 58 - shortID.count)
        let clippedName = String(name.prefix(maxBaseLength))

        return "\(clippedName)-\(shortID)"
    }
}

extension NetworkShareService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in
            self?.handleFoundPeer(peerID, info: info)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            self?.handleLostPeer(peerID)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "Could not browse network: \(error.localizedDescription)"
        }
    }
}

extension NetworkShareService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.handleInvitation(from: peerID, context: context, handler: invitationHandler)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "Could not advertise SimpleLime: \(error.localizedDescription)"
        }
    }
}

extension NetworkShareService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            self?.handleConnectionState(state, peerID: peerID)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            self?.handleReceivedData(data, from: peerID)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}

private struct DiscoveredPeer {
    var peerID: MCPeerID
    var deviceID: String
    var name: String
    var isAvailable: Bool
    var isConnected: Bool
}

private struct NetworkInvitationContext: Codable {
    var type: String
    var deviceID: String
    var name: String
    var token: String?
}

private struct NetworkControlPayload: Codable {
    var type: String
    var deviceID: String
    var name: String
    var token: String?
}

private extension JSONEncoder {
    static var networkEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var networkDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
