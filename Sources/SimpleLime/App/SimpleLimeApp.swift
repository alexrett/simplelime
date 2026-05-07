import AppKit
import SwiftUI

extension Notification.Name {
    static let simpleLimeOpenURLs = Notification.Name("SimpleLimeOpenURLs")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var pendingOpenURLs: [URL] = []
    private var windowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let window = notification.object as? NSWindow {
                Self.configure(window)
            }
            self?.removeSystemTabbingMenuItems()
        }

        DispatchQueue.main.async { [weak self] in
            NSApp.windows.forEach(Self.configure)
            self?.removeSystemTabbingMenuItems()
        }

        Self.enqueueOpenURLs(Self.fileURLsFromCommandLine())
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Self.enqueueOpenURLs(urls)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    deinit {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
    }

    static func drainPendingOpenURLs() -> [URL] {
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        return urls
    }

    private static func configure(_ window: NSWindow) {
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
    }

    private func removeSystemTabbingMenuItems() {
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else {
            return
        }

        viewMenu.items.removeAll { item in
            item.title == "Show Tab Bar" || item.title == "Show All Tabs"
        }
    }

    private static func enqueueOpenURLs(_ urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return }

        pendingOpenURLs.append(contentsOf: fileURLs)
        NotificationCenter.default.post(
            name: .simpleLimeOpenURLs,
            object: nil,
            userInfo: ["urls": fileURLs]
        )
    }

    private static func fileURLsFromCommandLine() -> [URL] {
        CommandLine.arguments.dropFirst().compactMap { argument in
            guard !argument.hasPrefix("-") else { return nil }

            let expanded = (argument as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }
}

@main
struct SimpleLimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = EditorStore()

    var body: some Scene {
        Window("SimpleLime", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 320, minHeight: 320)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.persistNow()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    store.persistNow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SimpleLimeCommands(store: store)
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
