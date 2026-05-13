import Foundation
import SimpleLimeRelayCore
import XCTest

final class StandaloneRelayCommandLineTests: XCTestCase {
    func testParsesExplicitConfiguration() throws {
        let configuration = try StandaloneRelayCommandLine.parse(arguments: [
            "--host", "127.0.0.1",
            "--port", "49999",
            "--room", "room-1",
            "--token", "secret",
            "--public-url", "https://relay.example.com",
            "--room-idle-timeout", "3600",
            "--print-link-only"
        ])

        XCTAssertEqual(configuration.bindHost, "127.0.0.1")
        XCTAssertEqual(configuration.port, 49_999)
        XCTAssertEqual(configuration.roomID, "room-1")
        XCTAssertEqual(configuration.token, "secret")
        XCTAssertEqual(configuration.publicURL?.absoluteString, "https://relay.example.com")
        XCTAssertFalse(configuration.allowInsecurePublicURL)
        XCTAssertEqual(configuration.roomIdleTimeout, 3_600)
        XCTAssertTrue(configuration.printLinkOnly)
    }

    func testRejectsInvalidPortAndUnknownArguments() {
        XCTAssertThrowsError(try StandaloneRelayCommandLine.parse(arguments: ["--port", "70000"])) { error in
            XCTAssertEqual(error as? StandaloneRelayCommandLineError, .invalidPort("70000"))
        }

        XCTAssertThrowsError(try StandaloneRelayCommandLine.parse(arguments: ["--public-url", "httpx://relay.example.com"])) { error in
            XCTAssertEqual(error as? StandaloneRelayCommandLineError, .invalidURL("httpx://relay.example.com"))
        }

        XCTAssertThrowsError(try StandaloneRelayCommandLine.parse(arguments: ["--room-idle-timeout", "-1"])) { error in
            XCTAssertEqual(error as? StandaloneRelayCommandLineError, .invalidRoomIdleTimeout("-1"))
        }

        XCTAssertThrowsError(try StandaloneRelayCommandLine.parse(arguments: ["--bogus"])) { error in
            XCTAssertEqual(error as? StandaloneRelayCommandLineError, .unknownArgument("--bogus"))
        }
    }

    func testRejectsNonLocalHTTPPublicURLUnlessExplicitlyAllowed() throws {
        XCTAssertThrowsError(try StandaloneRelayCommandLine.parse(arguments: [
            "--public-url", "http://relay.example.com"
        ])) { error in
            XCTAssertEqual(error as? StandaloneRelayCommandLineError, .insecurePublicURL("http://relay.example.com"))
        }

        let configuration = try StandaloneRelayCommandLine.parse(arguments: [
            "--public-url", "http://relay.example.com",
            "--allow-insecure-public-url"
        ])

        XCTAssertEqual(configuration.publicURL?.absoluteString, "http://relay.example.com")
        XCTAssertTrue(configuration.allowInsecurePublicURL)
    }

    func testAllowsLocalHTTPPublicURLForDevelopment() throws {
        let configuration = try StandaloneRelayCommandLine.parse(arguments: [
            "--public-url", "http://127.0.0.1:48888"
        ])

        XCTAssertEqual(configuration.publicURL?.absoluteString, "http://127.0.0.1:48888")
        XCTAssertFalse(configuration.allowInsecurePublicURL)
    }

    func testSimpleLimeLinkUsesPublicServerURLRoomAndToken() throws {
        let configuration = StandaloneRelayConfiguration(
            bindHost: "127.0.0.1",
            port: 48_888,
            roomID: "room-1",
            token: "secret",
            publicURL: URL(string: "https://relay.example.com")!
        )
        let components = try XCTUnwrap(URLComponents(url: configuration.simpleLimeURL, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(components.scheme, "simplelime")
        XCTAssertEqual(components.host, "collab")
        XCTAssertEqual(queryItems["server"], "https://relay.example.com")
        XCTAssertEqual(queryItems["room"], "room-1")
        XCTAssertEqual(queryItems["token"], "secret")
    }
}

final class StandaloneCollaborationRelayServerTests: XCTestCase {
    func testStandaloneRelayHTTPRequestParserRejectsOversizedIncompleteHeaders() {
        let oversizedHeader = Data(("GET /health HTTP/1.1\r\nX-Fill: " + String(repeating: "x", count: 17_000)).utf8)

        XCTAssertThrowsError(try StandaloneRelayHTTPRequestParser.request(from: oversizedHeader)) { error in
            XCTAssertEqual(error as? StandaloneRelayHTTPError, .payloadTooLarge)
        }
    }

    func testStandaloneRelayHTTPRequestParserHandlesDuplicateQueryItemsWithoutCrashing() throws {
        let requestData = Data(
            "GET /v1/rooms/room/events?since=0&since=2&token=old&token=new HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8
        )

        let request = try XCTUnwrap(StandaloneRelayHTTPRequestParser.request(from: requestData))

        XCTAssertEqual(request.queryItems["since"], "2")
        XCTAssertEqual(request.queryItems["token"], "new")
    }

    func testStandaloneRelayPublishesAndReceivesOpaqueEventsOverHTTP() async throws {
        let port = UInt16.random(in: 49_000...60_000)
        let configuration = StandaloneRelayConfiguration(
            bindHost: "127.0.0.1",
            port: port,
            roomID: "room",
            token: "secret",
            publicURL: URL(string: "http://127.0.0.1:\(port)")!
        )
        let server = StandaloneCollaborationRelayServer(configuration: configuration)
        try server.start()
        defer { server.stop() }

        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        try await waitForHealth(baseURL: baseURL)

        let published = server.publish(.object([
            "type": .string("collaboration"),
            "kind": .string("invite"),
            "revision": .integer(0)
        ]))
        XCTAssertEqual(published.id, 1)

        let eventsURL = baseURL.appendingPathComponent("/v1/rooms/room/events")
            .appending(queryItems: [
                URLQueryItem(name: "since", value: "0")
            ])
        var initialEventsRequest = URLRequest(url: eventsURL)
        initialEventsRequest.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let (initialEventsData, initialEventsResponse) = try await URLSession.shared.data(for: initialEventsRequest)
        XCTAssertEqual((initialEventsResponse as? HTTPURLResponse)?.statusCode, 200)
        let initialEvents = try JSONDecoder.standaloneRelayDecoder.decode(
            StandaloneCollaborationRelayEventsResponse.self,
            from: initialEventsData
        )
        XCTAssertEqual(initialEvents.events.map(\.id), [1])

        let acceptPayload = RelayJSONValue.object([
            "type": .string("collaboration"),
            "kind": .string("accept"),
            "revision": .integer(1),
            "sourceDeviceID": .string("guest"),
            "selectionRanges": .array([.object(["location": .integer(0), "length": .integer(0)])])
        ])
        var request = URLRequest(url: eventsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.standaloneRelayEncoder.encode(acceptPayload)

        let (postData, postResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((postResponse as? HTTPURLResponse)?.statusCode, 200)
        let post = try JSONDecoder.standaloneRelayDecoder.decode(
            StandaloneCollaborationRelayPostResponse.self,
            from: postData
        )
        XCTAssertEqual(post.ok, true)
        XCTAssertEqual(post.eventID, 2)

        let sinceOneURL = baseURL.appendingPathComponent("/v1/rooms/room/events")
            .appending(queryItems: [
                URLQueryItem(name: "since", value: "1")
            ])
        var sinceOneRequest = URLRequest(url: sinceOneURL)
        sinceOneRequest.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let (eventsData, eventsResponse) = try await URLSession.shared.data(for: sinceOneRequest)
        XCTAssertEqual((eventsResponse as? HTTPURLResponse)?.statusCode, 200)
        let events = try JSONDecoder.standaloneRelayDecoder.decode(
            StandaloneCollaborationRelayEventsResponse.self,
            from: eventsData
        )
        XCTAssertEqual(events.events.map(\.id), [2])
        XCTAssertEqual(events.events.first?.payload, acceptPayload)

        let wrongTokenURL = baseURL.appendingPathComponent("/v1/rooms/room/events")
            .appending(queryItems: [
                URLQueryItem(name: "since", value: "0")
            ])
        var wrongTokenRequest = URLRequest(url: wrongTokenURL)
        wrongTokenRequest.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
        let (_, wrongTokenResponse) = try await URLSession.shared.data(for: wrongTokenRequest)
        XCTAssertEqual((wrongTokenResponse as? HTTPURLResponse)?.statusCode, 403)
    }

    func testStandaloneRelayStillAcceptsLegacyQueryToken() async throws {
        let port = UInt16.random(in: 49_000...60_000)
        let configuration = StandaloneRelayConfiguration(
            bindHost: "127.0.0.1",
            port: port,
            roomID: "room",
            token: "secret",
            publicURL: URL(string: "http://127.0.0.1:\(port)")!
        )
        let server = StandaloneCollaborationRelayServer(configuration: configuration)
        try server.start()
        defer { server.stop() }
        try await waitForHealth(baseURL: URL(string: "http://127.0.0.1:\(port)")!)

        let eventsURL = URL(string: "http://127.0.0.1:\(port)/v1/rooms/room/events?token=secret&since=0")!
        let (_, response) = try await URLSession.shared.data(from: eventsURL)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    func testStandaloneRelayTrimsStoredEventsByByteBudget() async throws {
        let port = UInt16.random(in: 49_000...60_000)
        let configuration = StandaloneRelayConfiguration(
            bindHost: "127.0.0.1",
            port: port,
            roomID: "room",
            token: "secret",
            publicURL: URL(string: "http://127.0.0.1:\(port)")!
        )
        let server = StandaloneCollaborationRelayServer(
            configuration: configuration,
            maximumStoredEvents: 10,
            maximumStoredEventBytes: 900
        )
        try server.start()
        defer { server.stop() }
        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        try await waitForHealth(baseURL: baseURL)

        for index in 1...3 {
            server.publish(.object([
                "kind": .string("invite"),
                "sourceDeviceID": .string("host-\(index)"),
                "blob": .string(String(repeating: "x", count: 1_000))
            ]))
        }

        let eventsURL = baseURL.appendingPathComponent("/v1/rooms/room/events")
            .appending(queryItems: [
                URLQueryItem(name: "since", value: "0")
            ])
        var request = URLRequest(url: eventsURL)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let (eventsData, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let events = try JSONDecoder.standaloneRelayDecoder.decode(
            StandaloneCollaborationRelayEventsResponse.self,
            from: eventsData
        )

        XCTAssertEqual(events.events.map(\.id), [3])
        XCTAssertEqual(events.events.first?.payload, .object([
            "kind": .string("invite"),
            "sourceDeviceID": .string("host-3"),
            "blob": .string(String(repeating: "x", count: 1_000))
        ]))
    }

    func testStandaloneRelayExpiresIdleRoomHistory() async throws {
        var currentDate = Date(timeIntervalSince1970: 0)
        let port = UInt16.random(in: 49_000...60_000)
        let configuration = StandaloneRelayConfiguration(
            bindHost: "127.0.0.1",
            port: port,
            roomID: "room",
            token: "secret",
            publicURL: URL(string: "http://127.0.0.1:\(port)")!,
            roomIdleTimeout: 10
        )
        let server = StandaloneCollaborationRelayServer(
            configuration: configuration,
            now: { currentDate }
        )
        try server.start()
        defer { server.stop() }
        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        try await waitForHealth(baseURL: baseURL)

        server.publish(.object([
            "kind": .string("invite"),
            "sourceDeviceID": .string("host-1")
        ]))
        currentDate = currentDate.addingTimeInterval(11)
        let secondEvent = server.publish(.object([
            "kind": .string("invite"),
            "sourceDeviceID": .string("host-2")
        ]))
        XCTAssertEqual(secondEvent.id, 2)

        let eventsURL = baseURL.appendingPathComponent("/v1/rooms/room/events")
            .appending(queryItems: [
                URLQueryItem(name: "since", value: "0")
            ])
        var request = URLRequest(url: eventsURL)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let (eventsData, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let events = try JSONDecoder.standaloneRelayDecoder.decode(
            StandaloneCollaborationRelayEventsResponse.self,
            from: eventsData
        )

        XCTAssertEqual(events.events.map(\.id), [2])
        XCTAssertEqual(events.events.first?.payload, .object([
            "kind": .string("invite"),
            "sourceDeviceID": .string("host-2")
        ]))
    }

    private func waitForHealth(baseURL: URL) async throws {
        let healthURL = baseURL.appendingPathComponent("/health")
        var lastError: Error?

        for _ in 0..<100 {
            do {
                let (data, response) = try await URLSession.shared.data(from: healthURL)
                if (response as? HTTPURLResponse)?.statusCode == 200,
                   String(data: data, encoding: .utf8)?.contains("SimpleLime Standalone Relay") == true {
                    return
                }
            } catch {
                lastError = error
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        if let lastError {
            throw lastError
        }
        XCTFail("Timed out waiting for standalone relay health endpoint")
    }
}
