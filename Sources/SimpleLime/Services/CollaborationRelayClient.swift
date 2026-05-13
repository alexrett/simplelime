import Foundation

final class CollaborationRelayClient {
    private let link: CollaborationRelayLink
    private let urlSession: URLSession
    private var pollingTask: Task<Void, Never>?
    private var lastEventID: Int

    init(link: CollaborationRelayLink, lastEventID: Int = 0, urlSession: URLSession = .shared) {
        self.link = link
        self.lastEventID = lastEventID
        self.urlSession = urlSession
    }

    deinit {
        stop()
    }

    func startPolling(
        localDeviceID: String,
        onPayload: @escaping @MainActor (CollaborationPayload) -> Void,
        onStatus: @escaping @MainActor (String) -> Void
    ) {
        stop()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let events = try await self.fetchEvents()
                    for event in events {
                        self.lastEventID = max(self.lastEventID, event.id)
                        guard event.payload.sourceDeviceID != localDeviceID else { continue }
                        await MainActor.run {
                            onPayload(event.payload)
                        }
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    await MainActor.run {
                        onStatus("Relay sync error: \(error.localizedDescription)")
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func send(_ payload: CollaborationPayload) async throws -> Int? {
        var request = authorizedRequest(url: eventURL(since: nil))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.relayEncoder.encode(payload)

        let (data, response) = try await urlSession.data(for: request)
        try validate(response)
        return try JSONDecoder.relayDecoder.decode(CollaborationRelayPostResponse.self, from: data).eventID
    }

    func fetchEvents() async throws -> [CollaborationRelayEvent] {
        let request = authorizedRequest(url: eventURL(since: lastEventID))
        let (data, response) = try await urlSession.data(for: request)
        try validate(response)
        return try JSONDecoder.relayDecoder.decode(CollaborationRelayEventsResponse.self, from: data).events
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(link.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func eventURL(since: Int?) -> URL {
        var url = link.serverURL
        if !url.path.hasSuffix("/") {
            url.appendPathComponent("")
        }
        url.appendPathComponent("v1")
        url.appendPathComponent("rooms")
        url.appendPathComponent(link.roomID)
        url.appendPathComponent("events")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        var queryItems: [URLQueryItem] = []
        if let since {
            queryItems.append(URLQueryItem(name: "since", value: String(since)))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url ?? url
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw CollaborationRelayClientError.badResponse
        }
    }
}

private enum CollaborationRelayClientError: LocalizedError {
    case badResponse

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "Relay server returned an unsuccessful response."
        }
    }
}
