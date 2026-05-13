import Foundation

public enum RelayJSONValue: Codable, Equatable, Sendable {
    case object([String: RelayJSONValue])
    case array([RelayJSONValue])
    case string(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RelayJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: RelayJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct StandaloneCollaborationRelayEvent: Codable, Equatable, Sendable {
    public var id: Int
    public var payload: RelayJSONValue

    public init(id: Int, payload: RelayJSONValue) {
        self.id = id
        self.payload = payload
    }
}

public struct StandaloneCollaborationRelayEventsResponse: Codable, Equatable, Sendable {
    public var events: [StandaloneCollaborationRelayEvent]

    public init(events: [StandaloneCollaborationRelayEvent]) {
        self.events = events
    }
}

public struct StandaloneCollaborationRelayPostResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var eventID: Int?
    public var message: String

    public init(ok: Bool, eventID: Int?, message: String) {
        self.ok = ok
        self.eventID = eventID
        self.message = message
    }
}

public extension JSONEncoder {
    static var standaloneRelayEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var standaloneRelayDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
