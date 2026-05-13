import AppKit
import SwiftUI

extension Notification.Name {
    static let simpleLimeOpenURLs = Notification.Name("SimpleLimeOpenURLs")
    static let simpleLimeOpenCollaborationLinks = Notification.Name("SimpleLimeOpenCollaborationLinks")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var pendingOpenURLs: [URL] = []
    private static var pendingCollaborationLinks: [URL] = []
    private var windowObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        CommentReminderService.shared.activate()

        let center = NotificationCenter.default
        windowObservers.append(center.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let window = notification.object as? NSWindow {
                Self.configure(window)
            }
            self?.removeSystemTabbingMenuItems()
        })

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
        true
    }

    deinit {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    static func drainPendingOpenURLs() -> [URL] {
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        return urls
    }

    static func drainPendingCollaborationLinks() -> [URL] {
        let urls = pendingCollaborationLinks
        pendingCollaborationLinks.removeAll()
        return urls
    }

    private static func configure(_ window: NSWindow) {
        guard EditorWindowChrome.isEditorWindow(window) else { return }
        EditorWindowChrome.configure(window)
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
        let collaborationURLs = urls.filter { CollaborationRelayLink(url: $0) != nil }

        if !fileURLs.isEmpty {
            pendingOpenURLs.append(contentsOf: fileURLs)
            NotificationCenter.default.post(
                name: .simpleLimeOpenURLs,
                object: nil,
                userInfo: ["urls": fileURLs]
            )
        }

        if !collaborationURLs.isEmpty {
            pendingCollaborationLinks.append(contentsOf: collaborationURLs)
            NotificationCenter.default.post(
                name: .simpleLimeOpenCollaborationLinks,
                object: nil,
                userInfo: ["urls": collaborationURLs]
            )
        }
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
    @StateObject private var workspace = WorkspaceStore()

    var body: some Scene {
        WindowGroup("SimpleLime") {
            WorkspaceRootView(workspace: workspace)
                .frame(minWidth: 320, minHeight: 320)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    workspace.prepareForTermination()
                    workspace.persistNow()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    workspace.persistNow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SimpleLimeCommands(workspace: workspace)
        }

        Settings {
            SettingsView(workspace: workspace)
        }
    }
}

private struct WorkspaceRootView: View {
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        if let store = workspace.store(for: workspace.primaryGroupID) {
            ContentView(store: store, workspace: workspace) {
                workspace.activate(workspace.primaryGroupID)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
