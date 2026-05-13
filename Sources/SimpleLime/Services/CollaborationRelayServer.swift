import Foundation
import Network

enum CollaborationRelayHTTPError: LocalizedError, Equatable {
    case malformedRequest
    case unsupportedMethod
    case unsupportedPath
    case invalidToken
    case invalidJSON(String)
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .malformedRequest:
            return "Malformed relay request."
        case .unsupportedMethod:
            return "Unsupported relay method."
        case .unsupportedPath:
            return "Unknown relay endpoint."
        case .invalidToken:
            return "Invalid relay token."
        case .invalidJSON(let detail):
            return "Invalid relay JSON: \(detail)"
        case .payloadTooLarge:
            return "Relay payload is too large."
        }
    }
}

struct CollaborationRelayHTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var queryItems: [String: String]
    var body: Data

    var bearerToken: String? {
        guard let authorization = headers["authorization"] else { return nil }
        let parts = authorization.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              parts[0].caseInsensitiveCompare("Bearer") == .orderedSame else {
            return nil
        }
        let token = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

enum CollaborationRelayHTTPRequestParser {
    private static let maximumHeaderBytes = 16 * 1024
    private static let maximumBodyBytes = 2_000_000

    static func request(from data: Data) throws -> CollaborationRelayHTTPRequest? {
        guard data.count <= maximumHeaderBytes + maximumBodyBytes else {
            throw CollaborationRelayHTTPError.payloadTooLarge
        }

        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            guard data.count <= maximumHeaderBytes else {
                throw CollaborationRelayHTTPError.payloadTooLarge
            }
            return nil
        }

        let headerData = data[..<headerEnd.lowerBound]
        guard headerData.count <= maximumHeaderBytes else {
            throw CollaborationRelayHTTPError.payloadTooLarge
        }
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw CollaborationRelayHTTPError.malformedRequest
        }

        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else {
            throw CollaborationRelayHTTPError.malformedRequest
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw CollaborationRelayHTTPError.malformedRequest
        }

        let method = requestParts[0]
        let rawPath = requestParts[1]
        guard method == "GET" || method == "POST" else {
            throw CollaborationRelayHTTPError.unsupportedMethod
        }

        let headers = headerLines.dropFirst().reduce(into: [String: String]()) { result, line in
            guard let separatorIndex = line.firstIndex(of: ":") else { return }
            let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = value
        }

        let rawContentLength = Int(headers["content-length"] ?? "0") ?? 0
        let contentLength = max(rawContentLength, 0)
        guard contentLength <= maximumBodyBytes else {
            throw CollaborationRelayHTTPError.payloadTooLarge
        }

        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + contentLength else {
            return nil
        }

        let components = URLComponents(string: rawPath)
        let path = components?.path ?? rawPath
        let queryItems = parsedQueryItems(from: components?.queryItems ?? [])
        let body = Data(data[bodyStart..<(bodyStart + contentLength)])
        return CollaborationRelayHTTPRequest(method: method, path: path, headers: headers, queryItems: queryItems, body: body)
    }

    private static func parsedQueryItems(from items: [URLQueryItem]) -> [String: String] {
        items.reduce(into: [String: String]()) { result, item in
            guard let value = item.value else { return }
            result[item.name] = value
        }
    }
}

final class CollaborationRelayServer {
    static let defaultPort: UInt16 = 48888
    static let defaultRoomIdleTimeout: TimeInterval = 24 * 60 * 60

    private let port: UInt16
    private let roomID: String
    private let token: String
    private let maximumStoredEvents: Int
    private let maximumStoredEventBytes: Int
    private let roomIdleTimeout: TimeInterval
    private let now: () -> Date
    private let onPayload: @MainActor (CollaborationPayload) -> Void
    private var listener: NWListener?
    private var events: [CollaborationRelayEvent] = []
    private var nextEventID = 1
    private var lastRoomAccessedAt: Date

    init(
        port: UInt16 = CollaborationRelayServer.defaultPort,
        roomID: String = UUID().uuidString,
        token: String = UUID().uuidString,
        maximumStoredEvents: Int = 2_000,
        maximumStoredEventBytes: Int = 20 * 1024 * 1024,
        roomIdleTimeout: TimeInterval = CollaborationRelayServer.defaultRoomIdleTimeout,
        now: @escaping () -> Date = Date.init,
        onPayload: @escaping @MainActor (CollaborationPayload) -> Void
    ) {
        self.port = port
        self.roomID = roomID
        self.token = token
        self.maximumStoredEvents = max(1, maximumStoredEvents)
        self.maximumStoredEventBytes = max(1, maximumStoredEventBytes)
        self.roomIdleTimeout = max(0, roomIdleTimeout)
        self.now = now
        self.onPayload = onPayload
        self.lastRoomAccessedAt = now()
    }

    var link: CollaborationRelayLink {
        CollaborationRelayLink(serverURL: advertisedServerURL, roomID: roomID, token: token)
    }

    var advertisedServerURL: URL {
        let rawHost = ProcessInfo.processInfo.hostName
        let localHost = rawHost.hasSuffix(".local") ? rawHost : "\(rawHost).local"
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        let safeHost = localHost.unicodeScalars.allSatisfy { allowedCharacters.contains($0) } ? localHost : ""
        return URL(string: "http://\(safeHost):\(port)") ?? URL(string: "http://127.0.0.1:\(port)")!
    }

    func start() throws {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(IPv4Address("0.0.0.0")!),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        events.removeAll()
    }

    @discardableResult
    func publish(_ payload: CollaborationPayload, notifyLocalHandler: Bool = false) -> CollaborationRelayEvent {
        touchRoom()
        let event = CollaborationRelayEvent(id: nextEventID, payload: payload)
        nextEventID += 1
        events.append(event)
        trimEvents()
        if notifyLocalHandler {
            Task { @MainActor in
                onPayload(payload)
            }
        }
        return event
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffered: Data())
    }

    private func receive(on connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            if error != nil {
                connection.cancel()
                return
            }

            var buffer = buffered
            if let data {
                buffer.append(data)
            }

            do {
                guard let request = try CollaborationRelayHTTPRequestParser.request(from: buffer) else {
                    self.receive(on: connection, buffered: buffer)
                    return
                }
                try self.handle(request, on: connection)
            } catch {
                self.send(
                    data: self.encoded(CollaborationRelayPostResponse(ok: false, eventID: nil, message: error.localizedDescription)),
                    statusCode: self.statusCode(for: error),
                    on: connection
                )
            }
        }
    }

    private func handle(_ request: CollaborationRelayHTTPRequest, on connection: NWConnection) throws {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            send(data: Data(#"{"ok":true,"name":"SimpleLime Relay"}"#.utf8), statusCode: 200, on: connection)
        case ("GET", "/v1/rooms/\(roomID)/events"):
            try validateToken(request)
            touchRoom()
            let since = Int(request.queryItems["since"] ?? "0") ?? 0
            let response = CollaborationRelayEventsResponse(events: events.filter { $0.id > since })
            send(data: encoded(response), statusCode: 200, on: connection)
        case ("POST", "/v1/rooms/\(roomID)/events"):
            try validateToken(request)
            touchRoom()
            let payload = try decode(CollaborationPayload.self, from: request.body)
            let event = publish(payload)
            Task { @MainActor in
                self.onPayload(payload)
            }
            send(
                data: encoded(CollaborationRelayPostResponse(ok: true, eventID: event.id, message: "Relayed.")),
                statusCode: 200,
                on: connection
            )
        default:
            throw CollaborationRelayHTTPError.unsupportedPath
        }
    }

    private func validateToken(_ request: CollaborationRelayHTTPRequest) throws {
        guard let providedToken = request.bearerToken ?? request.queryItems["token"],
              Self.constantTimeEquals(providedToken, token) else {
            throw CollaborationRelayHTTPError.invalidToken
        }
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        let maxCount = max(lhsBytes.count, rhsBytes.count)
        var difference = lhsBytes.count ^ rhsBytes.count

        for index in 0..<maxCount {
            let lhsByte = index < lhsBytes.count ? lhsBytes[index] : 0
            let rhsByte = index < rhsBytes.count ? rhsBytes[index] : 0
            difference |= Int(lhsByte ^ rhsByte)
        }

        return difference == 0
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.relayDecoder.decode(type, from: data)
        } catch {
            throw CollaborationRelayHTTPError.invalidJSON(error.localizedDescription)
        }
    }

    private func encoded<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder.relayEncoder.encode(value)) ?? Data()
    }

    private func send(data body: Data, statusCode: Int, on connection: NWConnection) {
        let statusText = statusCode == 200 ? "OK" : "Bad Request"
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Access-Control-Allow-Headers: Content-Type, Authorization\r\n" +
            "Connection: close\r\n" +
            "\r\n"
        var data = Data(header.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusCode(for error: Error) -> Int {
        switch error as? CollaborationRelayHTTPError {
        case .payloadTooLarge:
            return 413
        case .unsupportedPath:
            return 404
        case .unsupportedMethod:
            return 405
        case .invalidToken:
            return 403
        default:
            return 400
        }
    }

    private func trimEvents() {
        if events.count > maximumStoredEvents {
            events.removeFirst(events.count - maximumStoredEvents)
        }

        var retainedBytes = 0
        var firstIndexToKeep = events.endIndex
        for index in events.indices.reversed() {
            let eventBytes = encoded(events[index]).count
            if firstIndexToKeep != events.endIndex,
               retainedBytes + eventBytes > maximumStoredEventBytes {
                break
            }

            retainedBytes += eventBytes
            firstIndexToKeep = index
        }

        if firstIndexToKeep > events.startIndex {
            events.removeFirst(firstIndexToKeep)
        }
    }

    private func touchRoom() {
        let currentDate = now()
        pruneExpiredRoomHistory(referenceDate: currentDate)
        lastRoomAccessedAt = currentDate
    }

    private func pruneExpiredRoomHistory(referenceDate: Date) {
        guard roomIdleTimeout > 0,
              referenceDate.timeIntervalSince(lastRoomAccessedAt) >= roomIdleTimeout else {
            return
        }

        events.removeAll()
    }
}

extension JSONEncoder {
    static var relayEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var relayDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
