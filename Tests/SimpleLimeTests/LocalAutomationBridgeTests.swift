import Network
import XCTest
@testable import SimpleLime

final class LocalAutomationBridgeTests: XCTestCase {
    func testParsesHealthRequest() throws {
        let request = Data("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)

        XCTAssertEqual(try LocalAutomationHTTPRequestParser.event(from: request), .health)
    }

    func testParsesScribeRequest() throws {
        let body = #"{"title":"Daily","text":"We shipped it.","speaker":"Alex","timestamp":"10:15","language":"markdown"}"#
        let request = httpRequest(path: "/v1/scribe", body: body)

        let event = try LocalAutomationHTTPRequestParser.event(from: request)

        XCTAssertEqual(
            event,
            .scribe(
                LocalAutomationScribeRequest(
                    title: "Daily",
                    text: "We shipped it.",
                    speaker: "Alex",
                    timestamp: "10:15",
                    language: .markdown,
                    mode: nil
                )
            )
        )
    }

    func testParsesCommandRequest() throws {
        let request = httpRequest(path: "/v1/command", body: #"{"command":"insertText","text":"hello"}"#)

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: request),
            .command(LocalAutomationCommandRequest(command: .insertText, text: "hello"))
        )
    }

    func testParsesReplaceLargeFileLineCommandRequest() throws {
        let request = httpRequest(
            path: "/v1/command",
            body: #"{"command":"replaceLargeFileLine","lineNumber":42,"text":"edited"}"#
        )

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: request),
            .command(LocalAutomationCommandRequest(command: .replaceLargeFileLine, text: "edited", lineNumber: 42))
        )
    }

    func testParsesInsertAndDeleteLargeFileLineCommandRequests() throws {
        let insertRequest = httpRequest(
            path: "/v1/command",
            body: #"{"command":"insertLargeFileLine","lineNumber":42,"text":"inserted"}"#
        )
        let deleteRequest = httpRequest(
            path: "/v1/command",
            body: #"{"command":"deleteLargeFileLine","lineNumber":42}"#
        )

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: insertRequest),
            .command(LocalAutomationCommandRequest(command: .insertLargeFileLine, text: "inserted", lineNumber: 42))
        )
        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: deleteRequest),
            .command(LocalAutomationCommandRequest(command: .deleteLargeFileLine, text: nil, lineNumber: 42))
        )
    }

    func testParsesLargeFileLineRangeCommandRequests() throws {
        let replaceRequest = httpRequest(
            path: "/v1/command",
            body: #"{"command":"replaceLargeFileLines","lineNumber":42,"endLineNumber":45,"text":"a\nb"}"#
        )
        let insertRequest = httpRequest(
            path: "/v1/command",
            body: #"{"command":"insertLargeFileLines","lineNumber":42,"text":"a\nb"}"#
        )
        let deleteRequest = httpRequest(
            path: "/v1/command",
            body: #"{"command":"deleteLargeFileLines","lineNumber":42,"endLineNumber":45}"#
        )

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: replaceRequest),
            .command(LocalAutomationCommandRequest(command: .replaceLargeFileLines, text: "a\nb", lineNumber: 42, endLineNumber: 45))
        )
        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: insertRequest),
            .command(LocalAutomationCommandRequest(command: .insertLargeFileLines, text: "a\nb", lineNumber: 42))
        )
        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: deleteRequest),
            .command(LocalAutomationCommandRequest(command: .deleteLargeFileLines, text: nil, lineNumber: 42, endLineNumber: 45))
        )
    }

    func testParsesToggleScribeCommandRequest() throws {
        let request = httpRequest(path: "/v1/command", body: #"{"command":"toggleScribe"}"#)

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: request),
            .command(LocalAutomationCommandRequest(command: .toggleScribe, text: nil))
        )
    }

    func testParsesForceCloseCommandRequest() throws {
        let request = httpRequest(path: "/v1/command", body: #"{"command":"forceClose"}"#)

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: request),
            .command(LocalAutomationCommandRequest(command: .forceClose, text: nil))
        )
    }

    func testParsesForceClosePathCommandRequest() throws {
        let request = httpRequest(path: "/v1/command", body: #"{"command":"forceClosePath","text":"/tmp/openapi.json"}"#)

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: request),
            .command(LocalAutomationCommandRequest(command: .forceClosePath, text: "/tmp/openapi.json"))
        )
    }

    func testParsesRPCScribeRequest() throws {
        let body = """
        {"jsonrpc":"2.0","id":"scribe-1","method":"v1.scribe","params":{"title":"Daily","text":"We shipped it.","mode":"newBuffer"}}
        """
        let request = httpRequest(path: "/v1/rpc", body: body)

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: request),
            .scribe(
                LocalAutomationScribeRequest(
                    title: "Daily",
                    text: "We shipped it.",
                    speaker: nil,
                    timestamp: nil,
                    language: nil,
                    mode: .newBuffer
                )
            )
        )
    }

    func testParsesRPCCommandRequest() throws {
        let body = #"{"jsonrpc":"2.0","id":"cmd-1","method":"command","params":{"command":"insertText","text":"hello"}}"#
        let request = httpRequest(path: "/v1/rpc", body: body)

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: request),
            .command(LocalAutomationCommandRequest(command: .insertText, text: "hello"))
        )
    }

    func testParsesRPCReplaceLargeFileLineCommandRequest() throws {
        let body = #"{"jsonrpc":"2.0","id":"cmd-1","method":"command","params":{"command":"replaceLargeFileLine","lineNumber":42,"text":"edited"}}"#
        let request = httpRequest(path: "/v1/rpc", body: body)

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: request),
            .command(LocalAutomationCommandRequest(command: .replaceLargeFileLine, text: "edited", lineNumber: 42))
        )
    }

    func testParsesRPCInsertAndDeleteLargeFileLineCommandRequests() throws {
        let insertBody = #"{"jsonrpc":"2.0","id":"cmd-1","method":"command","params":{"command":"insertLargeFileLine","lineNumber":42,"text":"inserted"}}"#
        let deleteBody = #"{"jsonrpc":"2.0","id":"cmd-2","method":"command","params":{"command":"deleteLargeFileLine","lineNumber":42}}"#

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: httpRequest(path: "/v1/rpc", body: insertBody)),
            .command(LocalAutomationCommandRequest(command: .insertLargeFileLine, text: "inserted", lineNumber: 42))
        )
        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: httpRequest(path: "/v1/rpc", body: deleteBody)),
            .command(LocalAutomationCommandRequest(command: .deleteLargeFileLine, text: nil, lineNumber: 42))
        )
    }

    func testParsesRPCLargeFileLineRangeCommandRequest() throws {
        let body = #"{"jsonrpc":"2.0","id":"cmd-1","method":"command","params":{"command":"replaceLargeFileLines","lineNumber":42,"endLineNumber":45,"text":"a\nb"}}"#
        let request = httpRequest(path: "/v1/rpc", body: body)

        XCTAssertEqual(
            try LocalAutomationHTTPRequestParser.event(from: request),
            .command(LocalAutomationCommandRequest(command: .replaceLargeFileLines, text: "a\nb", lineNumber: 42, endLineNumber: 45))
        )
    }

    func testRejectsUnknownRPCMethodWithJSONRPCError() throws {
        let body = #"{"jsonrpc":"2.0","id":"bad-1","method":"missing.method"}"#
        let request = httpRequest(path: "/v1/rpc", body: body)

        XCTAssertThrowsError(try LocalAutomationHTTPRequestParser.event(from: request)) { error in
            XCTAssertEqual(
                error as? LocalAutomationHTTPError,
                .rpcError(code: -32601, message: "Unknown JSON-RPC method.", id: .string("bad-1"))
            )
        }
    }

    func testParsesSocketHealthRequest() throws {
        let request = socketRequest(#"{"type":"health"}"#)

        XCTAssertEqual(
            try LocalAutomationSocketRequestParser.request(from: request)?.event,
            .health
        )
    }

    func testParsesSocketScribeRequest() throws {
        let request = socketRequest(#"{"type":"scribe","payload":{"title":"Daily","text":"We shipped it.","speaker":"Alex"}}"#)

        XCTAssertEqual(
            try LocalAutomationSocketRequestParser.request(from: request)?.event,
            .scribe(
                LocalAutomationScribeRequest(
                    title: "Daily",
                    text: "We shipped it.",
                    speaker: "Alex",
                    timestamp: nil,
                    language: nil,
                    mode: nil
                )
            )
        )
    }

    func testParsesSocketCommandRequest() throws {
        let request = socketRequest(#"{"type":"command","payload":{"command":"insertText","text":"hello"}}"#)

        XCTAssertEqual(
            try LocalAutomationSocketRequestParser.request(from: request)?.event,
            .command(LocalAutomationCommandRequest(command: .insertText, text: "hello"))
        )
    }

    func testParsesSocketReplaceLargeFileLineCommandRequest() throws {
        let request = socketRequest(#"{"type":"command","payload":{"command":"replaceLargeFileLine","lineNumber":42,"text":"edited"}}"#)

        XCTAssertEqual(
            try LocalAutomationSocketRequestParser.request(from: request)?.event,
            .command(LocalAutomationCommandRequest(command: .replaceLargeFileLine, text: "edited", lineNumber: 42))
        )
    }

    func testParsesSocketInsertAndDeleteLargeFileLineCommandRequests() throws {
        let insertRequest = socketRequest(#"{"type":"command","payload":{"command":"insertLargeFileLine","lineNumber":42,"text":"inserted"}}"#)
        let deleteRequest = socketRequest(#"{"type":"command","payload":{"command":"deleteLargeFileLine","lineNumber":42}}"#)

        XCTAssertEqual(
            try LocalAutomationSocketRequestParser.request(from: insertRequest)?.event,
            .command(LocalAutomationCommandRequest(command: .insertLargeFileLine, text: "inserted", lineNumber: 42))
        )
        XCTAssertEqual(
            try LocalAutomationSocketRequestParser.request(from: deleteRequest)?.event,
            .command(LocalAutomationCommandRequest(command: .deleteLargeFileLine, text: nil, lineNumber: 42))
        )
    }

    func testParsesSocketLargeFileLineRangeCommandRequest() throws {
        let request = socketRequest(#"{"type":"command","payload":{"command":"deleteLargeFileLines","lineNumber":42,"endLineNumber":45}}"#)

        XCTAssertEqual(
            try LocalAutomationSocketRequestParser.request(from: request)?.event,
            .command(LocalAutomationCommandRequest(command: .deleteLargeFileLines, text: nil, lineNumber: 42, endLineNumber: 45))
        )
    }

    func testSocketParserWaitsForNewlineFrameTerminator() throws {
        let request = Data(#"{"type":"health"}"#.utf8)

        XCTAssertNil(try LocalAutomationSocketRequestParser.request(from: request))
    }

    func testWaitsForIncompleteBody() throws {
        let request = Data("POST /v1/scribe HTTP/1.1\r\nContent-Length: 20\r\n\r\n{}".utf8)

        XCTAssertNil(try LocalAutomationHTTPRequestParser.event(from: request))
    }

    func testFormatsTranscriptLineWithSpeakerAndTimestamp() {
        let request = LocalAutomationScribeRequest(
            title: nil,
            text: "  next step is clear  ",
            speaker: "Maya",
            timestamp: "00:01:12",
            language: nil,
            mode: nil
        )

        XCTAssertEqual(request.formattedTranscriptLine, "[00:01:12] **Maya**: next step is clear")
    }

    func testBridgeRespondsToHealthOverLoopback() throws {
        let port = UInt16.random(in: 49_000...60_000)
        let receivedResponse = expectation(description: "received bridge response")
        let bridge = LocalAutomationBridge(port: port) { event in
            XCTAssertEqual(event, .health)
            return LocalAutomationBridgeResponse(ok: true, message: "ok", bufferTitle: "Scratch")
        }
        try bridge.start()
        defer { bridge.stop() }

        let connection = NWConnection(
            host: .ipv4(IPv4Address("127.0.0.1")!),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        var response = Data()

        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let data {
                    response.append(data)
                }

                if isComplete || error != nil {
                    connection.cancel()
                    receivedResponse.fulfill()
                } else {
                    receive()
                }
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let request = Data("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
                connection.send(content: request, completion: .contentProcessed { error in
                    if error != nil {
                        connection.cancel()
                        receivedResponse.fulfill()
                        return
                    }
                    receive()
                })
            case .failed:
                receivedResponse.fulfill()
            default:
                break
            }
        }
        connection.start(queue: .main)

        wait(for: [receivedResponse], timeout: 2)
        let responseText = String(data: response, encoding: .utf8)
        XCTAssertTrue(responseText?.contains("HTTP/1.1 200 OK") == true)
        XCTAssertTrue(responseText?.contains(#""message":"ok""#) == true)
    }

    func testBridgeRespondsToRPCCommandOverLoopback() throws {
        let port = UInt16.random(in: 49_000...60_000)
        let bridge = LocalAutomationBridge(port: port) { event in
            XCTAssertEqual(event, .command(LocalAutomationCommandRequest(command: .insertText, text: "hello")))
            return LocalAutomationBridgeResponse(ok: true, message: "inserted", bufferTitle: "Scratch")
        }
        try bridge.start()
        defer { bridge.stop() }

        let body = #"{"jsonrpc":"2.0","id":"cmd-1","method":"command","params":{"command":"insertText","text":"hello"}}"#
        let response = try sendLoopbackRequest(httpRequest(path: "/v1/rpc", body: body), port: port)
        let responseText = String(data: response, encoding: .utf8)

        XCTAssertTrue(responseText?.contains("HTTP/1.1 200 OK") == true)
        XCTAssertTrue(responseText?.contains(#""jsonrpc":"2.0""#) == true)
        XCTAssertTrue(responseText?.contains(#""id":"cmd-1""#) == true)
        XCTAssertTrue(responseText?.contains(#""result":{"#) == true)
        XCTAssertTrue(responseText?.contains(#""message":"inserted""#) == true)
    }

    func testBridgeRespondsToRPCErrorOverLoopback() throws {
        let port = UInt16.random(in: 49_000...60_000)
        let bridge = LocalAutomationBridge(port: port) { _ in
            XCTFail("Unknown RPC methods should not reach the bridge handler.")
            return LocalAutomationBridgeResponse(ok: false, message: "unexpected", bufferTitle: nil)
        }
        try bridge.start()
        defer { bridge.stop() }

        let body = #"{"jsonrpc":"2.0","id":"bad-1","method":"missing.method"}"#
        let response = try sendLoopbackRequest(httpRequest(path: "/v1/rpc", body: body), port: port)
        let responseText = String(data: response, encoding: .utf8)

        XCTAssertTrue(responseText?.contains("HTTP/1.1 400 Bad Request") == true)
        XCTAssertTrue(responseText?.contains(#""id":"bad-1""#) == true)
        XCTAssertTrue(responseText?.contains(#""code":-32601"#) == true)
        XCTAssertTrue(responseText?.contains(#""message":"Unknown JSON-RPC method.""#) == true)
    }

    func testBridgeRespondsToSocketCommandOverLoopback() throws {
        let port = UInt16.random(in: 49_000...60_000)
        let bridge = LocalAutomationBridge(port: port) { event in
            XCTAssertEqual(event, .command(LocalAutomationCommandRequest(command: .insertText, text: "hello")))
            return LocalAutomationBridgeResponse(ok: true, message: "inserted", bufferTitle: "Scratch")
        }
        try bridge.start()
        defer { bridge.stop() }

        let response = try sendLoopbackRequest(
            socketRequest(#"{"type":"command","payload":{"command":"insertText","text":"hello"}}"#),
            port: port
        )
        let responseText = String(data: response, encoding: .utf8)

        XCTAssertEqual(responseText?.hasPrefix("HTTP/1.1"), false)
        XCTAssertTrue(responseText?.hasSuffix("\n") == true)
        XCTAssertTrue(responseText?.contains(#""ok":true"#) == true)
        XCTAssertTrue(responseText?.contains(#""message":"inserted""#) == true)
    }

    func testBridgeRespondsToSocketErrorOverLoopback() throws {
        let port = UInt16.random(in: 49_000...60_000)
        let bridge = LocalAutomationBridge(port: port) { _ in
            XCTFail("Invalid socket frames should not reach the bridge handler.")
            return LocalAutomationBridgeResponse(ok: false, message: "unexpected", bufferTitle: nil)
        }
        try bridge.start()
        defer { bridge.stop() }

        let response = try sendLoopbackRequest(socketRequest(#"{"type":"command"}"#), port: port)
        let responseText = String(data: response, encoding: .utf8)

        XCTAssertEqual(responseText?.hasPrefix("HTTP/1.1"), false)
        XCTAssertTrue(responseText?.hasSuffix("\n") == true)
        XCTAssertTrue(responseText?.contains(#""ok":false"#) == true)
        XCTAssertTrue(responseText?.contains("Socket payload is required.") == true)
    }

    private func httpRequest(path: String, body: String) -> Data {
        Data(
            """
            POST \(path) HTTP/1.1\r
            Host: 127.0.0.1\r
            Content-Type: application/json\r
            Content-Length: \(body.utf8.count)\r
            \r
            \(body)
            """.utf8
        )
    }

    private func socketRequest(_ body: String) -> Data {
        Data((body + "\n").utf8)
    }

    private func sendLoopbackRequest(_ request: Data, port: UInt16) throws -> Data {
        let receivedResponse = expectation(description: "received bridge response")
        let connection = NWConnection(
            host: .ipv4(IPv4Address("127.0.0.1")!),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        var response = Data()

        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let data {
                    response.append(data)
                }

                if isComplete || error != nil {
                    connection.cancel()
                    receivedResponse.fulfill()
                } else {
                    receive()
                }
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: request, completion: .contentProcessed { error in
                    if error != nil {
                        connection.cancel()
                        receivedResponse.fulfill()
                        return
                    }
                    receive()
                })
            case .failed:
                receivedResponse.fulfill()
            default:
                break
            }
        }
        connection.start(queue: .main)

        wait(for: [receivedResponse], timeout: 2)
        return response
    }
}
