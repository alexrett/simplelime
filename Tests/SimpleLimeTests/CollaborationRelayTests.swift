import Foundation
import XCTest
@testable import SimpleLime

final class CollaborationRelayLinkTests: XCTestCase {
    func testRelayLinkRoundTripsThroughSimpleLimeURL() throws {
        let link = CollaborationRelayLink(
            serverURL: URL(string: "http://example.local:48888")!,
            roomID: "room-1",
            token: "secret"
        )

        let parsed = try XCTUnwrap(CollaborationRelayLink(url: link.url))

        XCTAssertEqual(parsed.serverURL.absoluteString, "http://example.local:48888")
        XCTAssertEqual(parsed.roomID, "room-1")
        XCTAssertEqual(parsed.token, "secret")
    }
}

final class CollaborationRelayServerTests: XCTestCase {
    func testRelayHTTPRequestParserRejectsOversizedIncompleteHeaders() {
        let oversizedHeader = Data(("GET /health HTTP/1.1\r\nX-Fill: " + String(repeating: "x", count: 17_000)).utf8)

        XCTAssertThrowsError(try CollaborationRelayHTTPRequestParser.request(from: oversizedHeader)) { error in
            XCTAssertEqual(error as? CollaborationRelayHTTPError, .payloadTooLarge)
        }
    }

    func testRelayHTTPRequestParserHandlesDuplicateQueryItemsWithoutCrashing() throws {
        let requestData = Data(
            "GET /v1/rooms/room/events?since=0&since=2&token=old&token=new HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8
        )

        let request = try XCTUnwrap(CollaborationRelayHTTPRequestParser.request(from: requestData))

        XCTAssertEqual(request.queryItems["since"], "2")
        XCTAssertEqual(request.queryItems["token"], "new")
    }

    func testRelayServerPublishesAndReceivesCollaborationEvents() async throws {
        let port = UInt16.random(in: 49_000...60_000)
        let receivedPayload = expectation(description: "received payload")
        let server = CollaborationRelayServer(port: port, roomID: "room", token: "secret") { payload in
            XCTAssertEqual(payload.kind, .accept)
            receivedPayload.fulfill()
        }
        try server.start()
        defer { server.stop() }

        let invite = relayPayload(kind: .invite, sourceDeviceID: "host")
        server.publish(invite)

        let eventsURL = URL(string: "http://127.0.0.1:\(port)/v1/rooms/room/events?since=0")!
        var eventsRequest = URLRequest(url: eventsURL)
        eventsRequest.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let (eventsData, eventsResponse) = try await URLSession.shared.data(for: eventsRequest)
        XCTAssertEqual((eventsResponse as? HTTPURLResponse)?.statusCode, 200)
        let events = try JSONDecoder.relayDecoder.decode(CollaborationRelayEventsResponse.self, from: eventsData)
        XCTAssertEqual(events.events.map(\.payload.kind), [.invite])

        var request = URLRequest(url: eventsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.relayEncoder.encode(relayPayload(kind: .accept, sourceDeviceID: "guest"))
        let (postData, postResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((postResponse as? HTTPURLResponse)?.statusCode, 200)
        let post = try JSONDecoder.relayDecoder.decode(CollaborationRelayPostResponse.self, from: postData)
        XCTAssertEqual(post.ok, true)
        XCTAssertEqual(post.eventID, 2)

        await fulfillment(of: [receivedPayload], timeout: 2)
    }

    func testRelayServerStillAcceptsLegacyQueryToken() async throws {
        let port = UInt16.random(in: 49_000...60_000)
        let server = CollaborationRelayServer(port: port, roomID: "room", token: "secret") { _ in }
        try server.start()
        defer { server.stop() }

        server.publish(relayPayload(kind: .invite, sourceDeviceID: "host"))

        let eventsURL = URL(string: "http://127.0.0.1:\(port)/v1/rooms/room/events?token=secret&since=0")!
        let (_, response) = try await URLSession.shared.data(from: eventsURL)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    func testRelayServerTrimsStoredEventsByByteBudget() async throws {
        let port = UInt16.random(in: 49_000...60_000)
        let server = CollaborationRelayServer(
            port: port,
            roomID: "room",
            token: "secret",
            maximumStoredEvents: 10,
            maximumStoredEventBytes: 900
        ) { _ in }
        try server.start()
        defer { server.stop() }

        for index in 1...3 {
            server.publish(relayPayload(
                kind: .invite,
                sourceDeviceID: "host-\(index)",
                text: String(repeating: "x", count: 1_000)
            ))
        }

        let eventsURL = URL(string: "http://127.0.0.1:\(port)/v1/rooms/room/events?since=0")!
        var eventsRequest = URLRequest(url: eventsURL)
        eventsRequest.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let (eventsData, eventsResponse) = try await URLSession.shared.data(for: eventsRequest)
        XCTAssertEqual((eventsResponse as? HTTPURLResponse)?.statusCode, 200)
        let events = try JSONDecoder.relayDecoder.decode(CollaborationRelayEventsResponse.self, from: eventsData)

        XCTAssertEqual(events.events.map(\.id), [3])
        XCTAssertEqual(events.events.first?.payload.sourceDeviceID, "host-3")
    }

    func testRelayServerExpiresIdleRoomHistory() async throws {
        var currentDate = Date(timeIntervalSince1970: 0)
        let port = UInt16.random(in: 49_000...60_000)
        let server = CollaborationRelayServer(
            port: port,
            roomID: "room",
            token: "secret",
            roomIdleTimeout: 10,
            now: { currentDate }
        ) { _ in }
        try server.start()
        defer { server.stop() }

        server.publish(relayPayload(kind: .invite, sourceDeviceID: "host-1"))
        currentDate = currentDate.addingTimeInterval(11)
        let secondEvent = server.publish(relayPayload(kind: .invite, sourceDeviceID: "host-2"))
        XCTAssertEqual(secondEvent.id, 2)

        let eventsURL = URL(string: "http://127.0.0.1:\(port)/v1/rooms/room/events?since=0")!
        var eventsRequest = URLRequest(url: eventsURL)
        eventsRequest.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let (eventsData, eventsResponse) = try await URLSession.shared.data(for: eventsRequest)
        XCTAssertEqual((eventsResponse as? HTTPURLResponse)?.statusCode, 200)
        let events = try JSONDecoder.relayDecoder.decode(CollaborationRelayEventsResponse.self, from: eventsData)

        XCTAssertEqual(events.events.map(\.id), [2])
        XCTAssertEqual(events.events.first?.payload.sourceDeviceID, "host-2")
    }

    func testRelayClientSendsBearerTokenWithoutTokenQueryItem() async throws {
        let link = CollaborationRelayLink(
            serverURL: URL(string: "http://relay.example.com")!,
            roomID: "room",
            token: "secret"
        )
        let client = CollaborationRelayClient(link: link, urlSession: mockRelaySession())

        RelayMockURLProtocol.requestHandler = { request in
            let queryItems = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertFalse(queryItems.contains { $0.name == "token" })
            XCTAssertEqual(queryItems.first(where: { $0.name == "since" })?.value, "0")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try JSONEncoder.relayEncoder.encode(CollaborationRelayEventsResponse(events: []))
            return (response, data)
        }

        let events = try await client.fetchEvents()

        XCTAssertEqual(events, [])
    }

    private func relayPayload(
        kind: CollaborationMessageKind,
        sourceDeviceID: String,
        text: String? = nil
    ) -> CollaborationPayload {
        CollaborationPayload(
            kind: kind,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Shared",
            text: text ?? (kind == .invite ? "hello" : nil),
            language: .markdown,
            patch: nil,
            selectionRanges: [.zero],
            revision: 0,
            sentAt: Date(timeIntervalSince1970: 0),
            sourceDeviceID: sourceDeviceID,
            sourceDeviceName: sourceDeviceID,
            sourceToken: nil
        )
    }

    private func mockRelaySession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelayMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class RelayMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
