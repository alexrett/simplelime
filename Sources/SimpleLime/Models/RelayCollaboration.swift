import Foundation

struct CollaborationRelayLink: Equatable {
    static let scheme = "simplelime"
    static let host = "collab"

    var serverURL: URL
    var roomID: String
    var token: String

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [
            URLQueryItem(name: "server", value: serverURL.absoluteString),
            URLQueryItem(name: "room", value: roomID),
            URLQueryItem(name: "token", value: token)
        ]
        return components.url ?? serverURL
    }

    init(serverURL: URL, roomID: String, token: String) {
        self.serverURL = serverURL
        self.roomID = roomID
        self.token = token
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme,
              components.host == Self.host else {
            return nil
        }

        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )
        guard let server = items["server"].flatMap(URL.init(string:)),
              let roomID = items["room"], !roomID.isEmpty,
              let token = items["token"], !token.isEmpty else {
            return nil
        }

        self.serverURL = server
        self.roomID = roomID
        self.token = token
    }
}

struct CollaborationRelayEvent: Codable, Equatable {
    var id: Int
    var payload: CollaborationPayload
}

struct CollaborationRelayEventsResponse: Codable, Equatable {
    var events: [CollaborationRelayEvent]
}

struct CollaborationRelayPostResponse: Codable, Equatable {
    var ok: Bool
    var eventID: Int?
    var message: String
}

struct CollaborationRelayState: Equatable {
    enum Role: String, Equatable {
        case host
        case guest
    }

    var role: Role
    var link: CollaborationRelayLink
    var lastEventID: Int
    var isRunning: Bool

    var shareURL: URL {
        link.url
    }

    var statusText: String {
        switch role {
        case .host:
            return isRunning ? "Relay hosting active" : "Relay hosting stopped"
        case .guest:
            return isRunning ? "Relay connected" : "Relay disconnected"
        }
    }
}
