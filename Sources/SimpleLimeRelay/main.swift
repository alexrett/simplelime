import Foundation
import SimpleLimeRelayCore

do {
    let configuration = try StandaloneRelayCommandLine.parse(
        arguments: Array(CommandLine.arguments.dropFirst())
    )
    let server = StandaloneCollaborationRelayServer(configuration: configuration)
    try server.start()

    if configuration.printLinkOnly {
        print(server.link.absoluteString)
    } else {
        print("SimpleLime relay listening on \(configuration.bindHost):\(configuration.port)")
        print("Room: \(configuration.roomID)")
        print("Room idle timeout: \(Int(configuration.roomIdleTimeout))s")
        print("Link: \(server.link.absoluteString)")
    }

    RunLoop.main.run()
} catch StandaloneRelayCommandLineError.helpRequested {
    print(StandaloneRelayCommandLine.usage)
} catch {
    fputs("SimpleLimeRelay: \(error.localizedDescription)\n", stderr)
    exit(1)
}
