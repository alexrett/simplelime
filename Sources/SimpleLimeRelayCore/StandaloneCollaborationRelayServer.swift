import Foundation
import Network

public enum StandaloneRelayHTTPError: LocalizedError, Equatable {
    case malformedRequest
    case unsupportedMethod
    case unsupportedPath
    case invalidToken
    case invalidJSON(String)
    case payloadTooLarge

    public var errorDescription: String? {
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

public struct StandaloneRelayHTTPRequest: Equatable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var queryItems: [String: String]
    public var body: Data

    public var bearerToken: String? {
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

public enum StandaloneRelayHTTPRequestParser {
    private static let maximumHeaderBytes = 16 * 1024
    private static let maximumBodyBytes = 2_000_000

    public static func request(from data: Data) throws -> StandaloneRelayHTTPRequest? {
        guard data.count <= maximumHeaderBytes + maximumBodyBytes else {
            throw StandaloneRelayHTTPError.payloadTooLarge
        }

        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            guard data.count <= maximumHeaderBytes else {
                throw StandaloneRelayHTTPError.payloadTooLarge
            }
            return nil
        }

        let headerData = data[..<headerEnd.lowerBound]
        guard headerData.count <= maximumHeaderBytes else {
            throw StandaloneRelayHTTPError.payloadTooLarge
        }
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw StandaloneRelayHTTPError.malformedRequest
        }

        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else {
            throw StandaloneRelayHTTPError.malformedRequest
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw StandaloneRelayHTTPError.malformedRequest
        }

        let method = requestParts[0]
        guard method == "GET" || method == "POST" || method == "OPTIONS" else {
            throw StandaloneRelayHTTPError.unsupportedMethod
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
            throw StandaloneRelayHTTPError.payloadTooLarge
        }

        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + contentLength else {
            return nil
        }

        let rawPath = requestParts[1]
        let components = URLComponents(string: rawPath)
        let path = components?.path ?? rawPath
        let queryItems = parsedQueryItems(from: components?.queryItems ?? [])
        let body = Data(data[bodyStart..<(bodyStart + contentLength)])
        return StandaloneRelayHTTPRequest(method: method, path: path, headers: headers, queryItems: queryItems, body: body)
    }

    private static func parsedQueryItems(from items: [URLQueryItem]) -> [String: String] {
        items.reduce(into: [String: String]()) { result, item in
            guard let value = item.value else { return }
            result[item.name] = value
        }
    }
}

public final class StandaloneCollaborationRelayServer {
    public static let defaultPort: UInt16 = 48888
    public static let defaultRoomIdleTimeout: TimeInterval = 24 * 60 * 60

    private let configuration: StandaloneRelayConfiguration
    private let queue = DispatchQueue(label: "SimpleLimeRelay")
    private let onPayload: (@Sendable (RelayJSONValue) -> Void)?
    private let maximumStoredEvents: Int
    private let maximumStoredEventBytes: Int
    private let now: () -> Date
    private var listener: NWListener?
    private var events: [StandaloneCollaborationRelayEvent] = []
    private var nextEventID = 1
    private var lastRoomAccessedAt: Date

    public init(
        configuration: StandaloneRelayConfiguration,
        maximumStoredEvents: Int = 2_000,
        maximumStoredEventBytes: Int = 20 * 1024 * 1024,
        now: @escaping () -> Date = Date.init,
        onPayload: (@Sendable (RelayJSONValue) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.maximumStoredEvents = max(1, maximumStoredEvents)
        self.maximumStoredEventBytes = max(1, maximumStoredEventBytes)
        self.now = now
        self.onPayload = onPayload
        self.lastRoomAccessedAt = now()
    }

    public var link: URL {
        configuration.simpleLimeURL
    }

    public func start() throws {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: networkHost(configuration.bindHost),
            port: NWEndpoint.Port(rawValue: configuration.port)!
        )

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        events.removeAll()
    }

    @discardableResult
    public func publish(_ payload: RelayJSONValue) -> StandaloneCollaborationRelayEvent {
        touchRoom()
        let event = StandaloneCollaborationRelayEvent(id: nextEventID, payload: payload)
        nextEventID += 1
        events.append(event)
        trimEvents()
        onPayload?(payload)
        return event
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
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
                guard let request = try StandaloneRelayHTTPRequestParser.request(from: buffer) else {
                    self.receive(on: connection, buffered: buffer)
                    return
                }
                try self.handle(request, on: connection)
            } catch {
                self.send(
                    data: self.encoded(StandaloneCollaborationRelayPostResponse(ok: false, eventID: nil, message: error.localizedDescription)),
                    statusCode: self.statusCode(for: error),
                    on: connection
                )
            }
        }
    }

    private func handle(_ request: StandaloneRelayHTTPRequest, on connection: NWConnection) throws {
        switch (request.method, request.path) {
        case ("OPTIONS", _):
            send(data: Data(), statusCode: 204, on: connection)
        case ("GET", "/health"):
            let body = #"{"ok":true,"name":"SimpleLime Standalone Relay","room":"\#(configuration.roomID)"}"#
            send(data: Data(body.utf8), statusCode: 200, on: connection)
        case ("GET", "/v1/rooms/\(configuration.roomID)/events"):
            try validateToken(request)
            touchRoom()
            let since = Int(request.queryItems["since"] ?? "0") ?? 0
            let response = StandaloneCollaborationRelayEventsResponse(events: events.filter { $0.id > since })
            send(data: encoded(response), statusCode: 200, on: connection)
        case ("POST", "/v1/rooms/\(configuration.roomID)/events"):
            try validateToken(request)
            touchRoom()
            let payload = try decode(RelayJSONValue.self, from: request.body)
            let event = publish(payload)
            send(
                data: encoded(StandaloneCollaborationRelayPostResponse(ok: true, eventID: event.id, message: "Relayed.")),
                statusCode: 200,
                on: connection
            )
        default:
            throw StandaloneRelayHTTPError.unsupportedPath
        }
    }

    private func validateToken(_ request: StandaloneRelayHTTPRequest) throws {
        guard let providedToken = request.bearerToken ?? request.queryItems["token"],
              Self.constantTimeEquals(providedToken, configuration.token) else {
            throw StandaloneRelayHTTPError.invalidToken
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
            return try JSONDecoder.standaloneRelayDecoder.decode(type, from: data)
        } catch {
            throw StandaloneRelayHTTPError.invalidJSON(error.localizedDescription)
        }
    }

    private func encoded<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder.standaloneRelayEncoder.encode(value)) ?? Data()
    }

    private func send(data body: Data, statusCode: Int, on connection: NWConnection) {
        let statusText = Self.statusText(for: statusCode)
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" +
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
        switch error as? StandaloneRelayHTTPError {
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

    private static func statusText(for statusCode: Int) -> String {
        switch statusCode {
        case 200:
            return "OK"
        case 204:
            return "No Content"
        case 403:
            return "Forbidden"
        case 404:
            return "Not Found"
        case 405:
            return "Method Not Allowed"
        case 413:
            return "Payload Too Large"
        default:
            return "Bad Request"
        }
    }

    private func networkHost(_ host: String) -> NWEndpoint.Host {
        if let ipv4 = IPv4Address(host) {
            return .ipv4(ipv4)
        }
        if let ipv6 = IPv6Address(host) {
            return .ipv6(ipv6)
        }
        return .name(host, nil)
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
        guard configuration.roomIdleTimeout > 0,
              referenceDate.timeIntervalSince(lastRoomAccessedAt) >= configuration.roomIdleTimeout else {
            return
        }

        events.removeAll()
    }
}
