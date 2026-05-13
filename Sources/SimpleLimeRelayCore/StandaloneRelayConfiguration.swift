import Foundation

public struct StandaloneRelayConfiguration: Equatable {
    public var bindHost: String
    public var port: UInt16
    public var roomID: String
    public var token: String
    public var publicURL: URL?
    public var allowInsecurePublicURL: Bool
    public var roomIdleTimeout: TimeInterval
    public var printLinkOnly: Bool

    public init(
        bindHost: String = "0.0.0.0",
        port: UInt16 = StandaloneCollaborationRelayServer.defaultPort,
        roomID: String = UUID().uuidString,
        token: String = UUID().uuidString,
        publicURL: URL? = nil,
        allowInsecurePublicURL: Bool = false,
        roomIdleTimeout: TimeInterval = StandaloneCollaborationRelayServer.defaultRoomIdleTimeout,
        printLinkOnly: Bool = false
    ) {
        self.bindHost = bindHost
        self.port = port
        self.roomID = roomID
        self.token = token
        self.publicURL = publicURL
        self.allowInsecurePublicURL = allowInsecurePublicURL
        self.roomIdleTimeout = max(0, roomIdleTimeout)
        self.printLinkOnly = printLinkOnly
    }

    public var advertisedServerURL: URL {
        if let publicURL {
            return publicURL
        }

        let host = bindHost == "0.0.0.0" ? Self.defaultAdvertisedHost() : bindHost
        return URL(string: "http://\(host):\(port)") ?? URL(string: "http://127.0.0.1:\(port)")!
    }

    public var simpleLimeURL: URL {
        var components = URLComponents()
        components.scheme = "simplelime"
        components.host = "collab"
        components.queryItems = [
            URLQueryItem(name: "server", value: advertisedServerURL.absoluteString),
            URLQueryItem(name: "room", value: roomID),
            URLQueryItem(name: "token", value: token)
        ]
        return components.url ?? advertisedServerURL
    }

    private static func defaultAdvertisedHost() -> String {
        let rawHost = ProcessInfo.processInfo.hostName
        let localHost = rawHost.hasSuffix(".local") ? rawHost : "\(rawHost).local"
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        if localHost.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) {
            return localHost
        }
        return "127.0.0.1"
    }
}

public enum StandaloneRelayCommandLineError: LocalizedError, Equatable {
    case helpRequested
    case missingValue(String)
    case invalidPort(String)
    case invalidURL(String)
    case insecurePublicURL(String)
    case invalidRoomIdleTimeout(String)
    case unknownArgument(String)

    public var errorDescription: String? {
        switch self {
        case .helpRequested:
            return StandaloneRelayCommandLine.usage
        case .missingValue(let option):
            return "\(option) requires a value."
        case .invalidPort(let value):
            return "Invalid relay port: \(value)."
        case .invalidURL(let value):
            return "Invalid public URL: \(value)."
        case .insecurePublicURL(let value):
            return "Public relay URLs must use https unless they are local, or --allow-insecure-public-url is set: \(value)."
        case .invalidRoomIdleTimeout(let value):
            return "Invalid relay room idle timeout: \(value)."
        case .unknownArgument(let value):
            return "Unknown relay argument: \(value)."
        }
    }
}

public enum StandaloneRelayCommandLine {
    public static let usage = """
    usage: SimpleLimeRelay [--host 0.0.0.0] [--port 48888] [--room ROOM] [--token TOKEN] [--public-url URL] [--allow-insecure-public-url] [--room-idle-timeout SECONDS] [--print-link-only]

    Runs a standalone SimpleLime collaboration relay compatible with simplelime://collab links.
    Non-local --public-url values must use https unless --allow-insecure-public-url is set.
    """

    public static func parse(arguments: [String]) throws -> StandaloneRelayConfiguration {
        var configuration = StandaloneRelayConfiguration()
        var index = 0

        func value(after option: String) throws -> String {
            let valueIndex = index + 1
            guard arguments.indices.contains(valueIndex) else {
                throw StandaloneRelayCommandLineError.missingValue(option)
            }
            index = valueIndex
            return arguments[valueIndex]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                throw StandaloneRelayCommandLineError.helpRequested
            case "--host":
                configuration.bindHost = try value(after: argument)
            case "--port":
                let rawPort = try value(after: argument)
                guard let port = UInt16(rawPort), port > 0 else {
                    throw StandaloneRelayCommandLineError.invalidPort(rawPort)
                }
                configuration.port = port
            case "--room":
                configuration.roomID = try value(after: argument)
            case "--token":
                configuration.token = try value(after: argument)
            case "--public-url":
                let rawURL = try value(after: argument)
                guard let url = URL(string: rawURL),
                      let scheme = url.scheme?.lowercased(),
                      ["http", "https"].contains(scheme),
                      url.host != nil else {
                    throw StandaloneRelayCommandLineError.invalidURL(rawURL)
                }
                configuration.publicURL = url
            case "--allow-insecure-public-url":
                configuration.allowInsecurePublicURL = true
            case "--room-idle-timeout":
                let rawTimeout = try value(after: argument)
                guard let timeout = TimeInterval(rawTimeout), timeout >= 0 else {
                    throw StandaloneRelayCommandLineError.invalidRoomIdleTimeout(rawTimeout)
                }
                configuration.roomIdleTimeout = timeout
            case "--print-link-only":
                configuration.printLinkOnly = true
            default:
                throw StandaloneRelayCommandLineError.unknownArgument(argument)
            }

            index += 1
        }

        try validate(configuration)
        return configuration
    }

    private static func validate(_ configuration: StandaloneRelayConfiguration) throws {
        guard let publicURL = configuration.publicURL,
              publicURL.scheme?.lowercased() == "http",
              !configuration.allowInsecurePublicURL,
              let host = publicURL.host,
              !isLocalHTTPHost(host) else {
            return
        }

        throw StandaloneRelayCommandLineError.insecurePublicURL(publicURL.absoluteString)
    }

    private static func isLocalHTTPHost(_ host: String) -> Bool {
        let lowercasedHost = host.lowercased()
        return lowercasedHost == "localhost" ||
            lowercasedHost.hasSuffix(".localhost") ||
            lowercasedHost.hasSuffix(".local") ||
            lowercasedHost == "::1" ||
            lowercasedHost == "0:0:0:0:0:0:0:1" ||
            lowercasedHost.hasPrefix("127.")
    }
}
