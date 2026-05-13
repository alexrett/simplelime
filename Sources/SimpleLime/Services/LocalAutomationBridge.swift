import Foundation
import Network

enum LocalAutomationHTTPError: LocalizedError, Equatable {
    case malformedRequest
    case unsupportedMethod
    case unsupportedPath
    case invalidJSON(String)
    case payloadTooLarge
    case rpcError(code: Int, message: String, id: LocalAutomationJSONValue?)

    var errorDescription: String? {
        switch self {
        case .malformedRequest:
            "Malformed HTTP request."
        case .unsupportedMethod:
            "Only GET and POST are supported."
        case .unsupportedPath:
            "Unknown automation endpoint."
        case .invalidJSON(let detail):
            "Invalid JSON payload: \(detail)"
        case .payloadTooLarge:
            "Automation payload is too large."
        case .rpcError(_, let message, _):
            message
        }
    }
}

enum LocalAutomationBridgeEvent: Equatable {
    case health
    case scribe(LocalAutomationScribeRequest)
    case command(LocalAutomationCommandRequest)
}

enum LocalAutomationHTTPResponseKind {
    case rest
    case jsonRPC(id: LocalAutomationJSONValue?)
    case socketLine
}

struct LocalAutomationParsedHTTPRequest {
    var event: LocalAutomationBridgeEvent
    var responseKind: LocalAutomationHTTPResponseKind
}

enum LocalAutomationHTTPRequestParser {
    private static let maximumBodyBytes = 1_000_000

    static func event(from data: Data) throws -> LocalAutomationBridgeEvent? {
        try request(from: data)?.event
    }

    static func request(from data: Data) throws -> LocalAutomationParsedHTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw LocalAutomationHTTPError.malformedRequest
        }

        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else {
            throw LocalAutomationHTTPError.malformedRequest
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw LocalAutomationHTTPError.malformedRequest
        }

        let method = requestParts[0]
        let path = requestParts[1]
        guard method == "GET" || method == "POST" else {
            throw LocalAutomationHTTPError.unsupportedMethod
        }

        let headers = headerLines.dropFirst().reduce(into: [String: String]()) { result, line in
            guard let separatorIndex = line.firstIndex(of: ":") else { return }
            let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = value
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength <= maximumBodyBytes else {
            throw LocalAutomationHTTPError.payloadTooLarge
        }

        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + contentLength else {
            return nil
        }

        let body = data[bodyStart..<(bodyStart + contentLength)]
        switch (method, normalizedPath(path)) {
        case ("GET", "/health"):
            return LocalAutomationParsedHTTPRequest(event: .health, responseKind: .rest)
        case ("POST", "/v1/scribe"):
            return LocalAutomationParsedHTTPRequest(
                event: .scribe(try decode(LocalAutomationScribeRequest.self, from: body)),
                responseKind: .rest
            )
        case ("POST", "/v1/command"):
            return LocalAutomationParsedHTTPRequest(
                event: .command(try decode(LocalAutomationCommandRequest.self, from: body)),
                responseKind: .rest
            )
        case ("POST", "/v1/rpc"):
            return try rpcRequest(from: Data(body))
        default:
            throw LocalAutomationHTTPError.unsupportedPath
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        guard let questionIndex = path.firstIndex(of: "?") else { return path }
        return String(path[..<questionIndex])
    }

    private static func decode<T: Decodable>(_ type: T.Type, from body: Data.SubSequence) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(body))
        } catch {
            throw LocalAutomationHTTPError.invalidJSON(error.localizedDescription)
        }
    }

    private static func rpcRequest(from body: Data) throws -> LocalAutomationParsedHTTPRequest {
        let request: LocalAutomationJSONRPCRequest
        do {
            request = try JSONDecoder().decode(LocalAutomationJSONRPCRequest.self, from: body)
        } catch {
            throw LocalAutomationHTTPError.invalidJSON(error.localizedDescription)
        }

        guard request.jsonrpc == "2.0" else {
            throw LocalAutomationHTTPError.rpcError(
                code: -32600,
                message: "Invalid JSON-RPC request.",
                id: request.id
            )
        }

        switch request.method {
        case "health", "v1.health":
            return LocalAutomationParsedHTTPRequest(
                event: .health,
                responseKind: .jsonRPC(id: request.id)
            )
        case "scribe", "v1.scribe":
            return LocalAutomationParsedHTTPRequest(
                event: .scribe(try decodeRPCParams(LocalAutomationScribeRequest.self, from: request)),
                responseKind: .jsonRPC(id: request.id)
            )
        case "command", "v1.command":
            return LocalAutomationParsedHTTPRequest(
                event: .command(try decodeRPCParams(LocalAutomationCommandRequest.self, from: request)),
                responseKind: .jsonRPC(id: request.id)
            )
        default:
            throw LocalAutomationHTTPError.rpcError(
                code: -32601,
                message: "Unknown JSON-RPC method.",
                id: request.id
            )
        }
    }

    private static func decodeRPCParams<T: Decodable>(
        _ type: T.Type,
        from request: LocalAutomationJSONRPCRequest
    ) throws -> T {
        guard let params = request.params else {
            throw LocalAutomationHTTPError.rpcError(
                code: -32602,
                message: "JSON-RPC params are required.",
                id: request.id
            )
        }

        do {
            let data = try JSONEncoder().encode(params)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LocalAutomationHTTPError.rpcError(
                code: -32602,
                message: "Invalid JSON-RPC params: \(error.localizedDescription)",
                id: request.id
            )
        }
    }
}

enum LocalAutomationSocketRequestParser {
    private static let maximumFrameBytes = 1_000_000

    static func isSocketCandidate(_ data: Data) -> Bool {
        guard let firstByte = data.first(where: { !$0.isWhitespaceASCII }) else {
            return false
        }
        return firstByte == UInt8(ascii: "{")
    }

    static func request(from data: Data) throws -> LocalAutomationParsedHTTPRequest? {
        guard data.count <= maximumFrameBytes else {
            throw LocalAutomationHTTPError.payloadTooLarge
        }

        guard let newlineIndex = data.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }

        let frame = data[..<newlineIndex]
        let socketRequest: LocalAutomationSocketRequest
        do {
            socketRequest = try JSONDecoder().decode(LocalAutomationSocketRequest.self, from: Data(frame))
        } catch {
            throw LocalAutomationHTTPError.invalidJSON(error.localizedDescription)
        }

        let event: LocalAutomationBridgeEvent
        switch socketRequest.type {
        case .health:
            event = .health
        case .scribe:
            event = .scribe(try decodePayload(LocalAutomationScribeRequest.self, from: socketRequest))
        case .command:
            event = .command(try decodePayload(LocalAutomationCommandRequest.self, from: socketRequest))
        }

        return LocalAutomationParsedHTTPRequest(event: event, responseKind: .socketLine)
    }

    private static func decodePayload<T: Decodable>(
        _ type: T.Type,
        from socketRequest: LocalAutomationSocketRequest
    ) throws -> T {
        guard let payload = socketRequest.payload else {
            throw LocalAutomationHTTPError.invalidJSON("Socket payload is required.")
        }

        do {
            let data = try JSONEncoder().encode(payload)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LocalAutomationHTTPError.invalidJSON(error.localizedDescription)
        }
    }
}

private extension UInt8 {
    var isWhitespaceASCII: Bool {
        self == UInt8(ascii: " ") ||
            self == UInt8(ascii: "\t") ||
            self == UInt8(ascii: "\r") ||
            self == UInt8(ascii: "\n")
    }
}

final class LocalAutomationBridge {
    static let defaultPort: UInt16 = 48777

    private let port: UInt16
    private let handler: @MainActor (LocalAutomationBridgeEvent) -> LocalAutomationBridgeResponse
    private var listener: NWListener?

    init(
        port: UInt16 = LocalAutomationBridge.defaultPort,
        handler: @escaping @MainActor (LocalAutomationBridgeEvent) -> LocalAutomationBridgeResponse
    ) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(IPv4Address("127.0.0.1")!),
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

            let isSocketCandidate = LocalAutomationSocketRequestParser.isSocketCandidate(buffer)
            do {
                let parsed = isSocketCandidate
                    ? try LocalAutomationSocketRequestParser.request(from: buffer)
                    : try LocalAutomationHTTPRequestParser.request(from: buffer)
                guard let request = parsed else {
                    self.receive(on: connection, buffered: buffer)
                    return
                }

                Task { @MainActor in
                    let response = self.handler(request.event)
                    self.send(response: response, statusCode: 200, responseKind: request.responseKind, on: connection)
                }
            } catch {
                if isSocketCandidate {
                    self.sendSocketError(error, on: connection)
                } else {
                    self.send(error: error, on: connection)
                }
            }
        }
    }

    private func send(
        response: LocalAutomationBridgeResponse,
        statusCode: Int,
        responseKind: LocalAutomationHTTPResponseKind,
        on connection: NWConnection
    ) {
        let body: Data
        switch responseKind {
        case .rest:
            body = (try? JSONEncoder().encode(response)) ?? Data(#"{"ok":false,"message":"Encoding error"}"#.utf8)
        case .jsonRPC(let id):
            let envelope = LocalAutomationJSONRPCSuccessResponse(id: id ?? .null, result: response)
            body = (try? JSONEncoder().encode(envelope))
                ?? Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Encoding error"}}"#.utf8)
        case .socketLine:
            sendSocketResponse(response, on: connection)
            return
        }

        send(body: body, statusCode: statusCode, on: connection)
    }

    private func sendSocketResponse(_ response: LocalAutomationBridgeResponse, on connection: NWConnection) {
        var body = (try? JSONEncoder().encode(response)) ?? Data(#"{"ok":false,"message":"Encoding error"}"#.utf8)
        body.append(UInt8(ascii: "\n"))
        connection.send(content: body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendSocketError(_ error: Error, on connection: NWConnection) {
        sendSocketResponse(
            LocalAutomationBridgeResponse(
                ok: false,
                message: error.localizedDescription,
                bufferTitle: nil
            ),
            on: connection
        )
    }

    private func send(error: Error, on connection: NWConnection) {
        if case .rpcError(let code, let message, let id) = error as? LocalAutomationHTTPError {
            let envelope = LocalAutomationJSONRPCErrorResponse(
                id: id ?? .null,
                error: LocalAutomationJSONRPCErrorBody(code: code, message: message)
            )
            let body = (try? JSONEncoder().encode(envelope))
                ?? Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Encoding error"}}"#.utf8)
            send(body: body, statusCode: statusCode(for: error), on: connection)
            return
        }

        let response = LocalAutomationBridgeResponse(
            ok: false,
            message: error.localizedDescription,
            bufferTitle: nil
        )
        let body = (try? JSONEncoder().encode(response)) ?? Data(#"{"ok":false,"message":"Encoding error"}"#.utf8)
        send(body: body, statusCode: statusCode(for: error), on: connection)
    }

    private func send(body: Data, statusCode: Int, on connection: NWConnection) {
        let statusText = statusCode == 200 ? "OK" : "Bad Request"
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n" +
            "\r\n"
        var data = Data(header.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusCode(for error: Error) -> Int {
        switch error as? LocalAutomationHTTPError {
        case .payloadTooLarge:
            return 413
        case .unsupportedPath:
            return 404
        case .unsupportedMethod:
            return 405
        case .rpcError:
            return 400
        default:
            return 400
        }
    }
}
