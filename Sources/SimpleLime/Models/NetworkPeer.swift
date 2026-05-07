import Foundation

struct NetworkPeer: Identifiable, Equatable {
    var id: String { deviceID }

    let deviceID: String
    var name: String
    var isTrusted: Bool
    var isAvailable: Bool
    var isConnected: Bool

    var statusText: String {
        if isConnected {
            return "Connected"
        }

        if isTrusted, isAvailable {
            return "Trusted"
        }

        if isTrusted {
            return "Trusted, offline"
        }

        return isAvailable ? "Available" : "Offline"
    }
}

struct TrustedNetworkDevice: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var token: String?
    var pairedAt: Date
    var lastSeenAt: Date?
}

struct PendingPairRequest: Identifiable, Equatable {
    var id: String { deviceID }

    var deviceID: String
    var name: String
    var token: String?
}

struct SharedNotePayload: Codable, Equatable {
    var type = "note"
    var id: UUID
    var title: String
    var text: String
    var language: EditorLanguage
    var sentAt: Date
    var sourceDeviceID: String
    var sourceDeviceName: String
    var sourceToken: String?
}
