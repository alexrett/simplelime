import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
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
    }

    deinit {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
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
}

@main
struct SimpleLimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = EditorStore()

    var body: some Scene {
        WindowGroup("SimpleLime") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 640)
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
