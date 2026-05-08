import AppKit
import SwiftUI

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var groups: [EditorWindowGroup] = []
    @Published var activeGroupID: UUID?

    let networkShare = NetworkShareService()

    private let persistence: SessionPersistence
    private var pendingSaveTask: Task<Void, Never>?
    private var openURLObserver: NSObjectProtocol?
    private var manualWindows: [UUID: NSWindow] = [:]
    private var manualWindowDelegates: [UUID: WindowDelegate] = [:]
    // Keep closed manual windows alive for the process lifetime. Releasing these custom
    // full-size-content SwiftUI windows during or shortly after close can crash AppKit.
    private var retiredManualWindows: [NSWindow] = []
    private var retiredManualWindowDelegates: [WindowDelegate] = []
    private var closingManualGroupIDs = Set<UUID>()
    private var isTerminating = false

    init(persistence: SessionPersistence = SessionPersistence()) {
        self.persistence = persistence

        let states = persistence.loadWindowGroups()
        let resolvedStates = states.isEmpty ? [Self.defaultGroupState()] : states
        groups = resolvedStates.map { makeGroup(from: $0) }
        activeGroupID = groups.first?.id
        networkShare.onReceivedNote = { [weak self] note in
            self?.importSharedNote(note)
        }
        installOpenURLObserver()

        DispatchQueue.main.async { [weak self] in
            self?.openPendingExternalFiles()
            self?.openRestoredManualWindows()
        }
    }

    deinit {
        pendingSaveTask?.cancel()
        if let openURLObserver {
            NotificationCenter.default.removeObserver(openURLObserver)
        }
    }

    var primaryGroupID: UUID {
        if let first = groups.first {
            return first.id
        }

        let group = makeGroup(from: Self.defaultGroupState())
        groups = [group]
        activeGroupID = group.id
        return group.id
    }

    var activeStore: EditorStore? {
        store(for: activeGroupID) ?? groups.first?.store
    }

    func store(for groupID: UUID?) -> EditorStore? {
        guard let groupID else { return nil }
        return groups.first(where: { $0.id == groupID })?.store
    }

    func activate(_ groupID: UUID) {
        activeGroupID = groupID
    }

    func newWindow() {
        let group = makeGroup(from: Self.defaultGroupState())
        groups.append(group)
        activeGroupID = group.id
        openManualWindow(for: group.id)
        persistSoon()
    }

    func moveSelectedTabToNewWindow(from store: EditorStore?) {
        guard let store,
              let buffer = store.detachSelectedBufferForNewWindow() else {
            return
        }

        let group = makeGroup(
            from: EditorWindowGroupState(
                id: UUID(),
                selectedBufferID: buffer.id,
                buffers: [buffer]
            )
        )
        groups.append(group)
        activeGroupID = group.id
        openManualWindow(for: group.id)
        persistSoon()
    }

    func openSelectedTabCopyInNewWindow(from store: EditorStore?) {
        guard let store,
              let buffer = store.copySelectedBufferForNewWindow() else {
            return
        }

        let group = makeGroup(
            from: EditorWindowGroupState(
                id: UUID(),
                selectedBufferID: buffer.id,
                buffers: [buffer]
            )
        )
        groups.append(group)
        activeGroupID = group.id
        openManualWindow(for: group.id)
        persistSoon()
    }

    func moveTab(sourceGroupID: UUID, targetGroupID: UUID, bufferID: UUID) {
        guard sourceGroupID != targetGroupID,
              let source = store(for: sourceGroupID),
              let target = store(for: targetGroupID),
              let buffer = source.detachBuffer(id: bufferID) else {
            return
        }

        target.appendMovedBuffer(buffer)
        activeGroupID = targetGroupID
        persistSoon()
    }

    func openFilesInActiveWindow(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let store = activeStore ?? groups.first?.store
        store?.openFiles(at: urls)
    }

    func importSharedNote(_ note: SharedNotePayload) {
        let store = activeStore ?? groups.first?.store
        store?.importSharedNote(note)
    }

    func prepareForTermination() {
        isTerminating = true
    }

    func persistNow() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil

        do {
            try persistence.save(
                windowGroups: groups.map {
                    EditorWindowGroupState(
                        id: $0.id,
                        selectedBufferID: $0.store.selectedBufferID,
                        buffers: $0.store.buffers
                    )
                },
                selectedGroupID: activeGroupID
            )
        } catch {
            activeStore?.lastError = "Could not persist session: \(error.localizedDescription)"
        }
    }

    func persistSoon() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run {
                self?.persistNow()
            }
        }
    }

    private func installOpenURLObserver() {
        openURLObserver = NotificationCenter.default.addObserver(
            forName: .simpleLimeOpenURLs,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let urls = notification.userInfo?["urls"] as? [URL] else {
                return
            }

            Task { @MainActor in
                self?.openFilesInActiveWindow(urls)
                _ = AppDelegate.drainPendingOpenURLs()
            }
        }
    }

    private func openPendingExternalFiles() {
        let urls = AppDelegate.drainPendingOpenURLs()
        openFilesInActiveWindow(urls)
    }

    private func openRestoredManualWindows() {
        for group in groups.dropFirst() {
            openManualWindow(for: group.id)
        }
    }

    private func makeGroup(from state: EditorWindowGroupState) -> EditorWindowGroup {
        let store = EditorStore(
            windowGroupID: state.id,
            initialBuffers: state.buffers.isEmpty ? [EditorBuffer.scratch(index: 1)] : state.buffers,
            selectedID: state.selectedBufferID,
            persistence: nil,
            networkShare: networkShare,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
        store.onPersistRequested = { [weak self] in
            self?.persistSoon()
        }
        store.onMoveTabBetweenGroups = { [weak self] sourceGroupID, targetGroupID, bufferID in
            self?.moveTab(sourceGroupID: sourceGroupID, targetGroupID: targetGroupID, bufferID: bufferID)
        }

        return EditorWindowGroup(id: state.id, store: store)
    }

    private func openManualWindow(for groupID: UUID) {
        if let window = manualWindows[groupID] {
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let store = store(for: groupID) else { return }

        let rootView = ContentView(store: store) { [weak self] in
            self?.activate(groupID)
        }
        let hostingController = NSHostingController(rootView: rootView.frame(minWidth: 320, minHeight: 320))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "SimpleLime"
        window.center()
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        let delegate = WindowDelegate { [weak self] in
            self?.handleManualWindowWillClose(groupID: groupID)
        }
        window.delegate = delegate
        manualWindows[groupID] = window
        manualWindowDelegates[groupID] = delegate
        window.makeKeyAndOrderFront(nil)
    }

    private func handleManualWindowWillClose(groupID: UUID) {
        guard !closingManualGroupIDs.contains(groupID) else { return }
        closingManualGroupIDs.insert(groupID)

        if let closingWindow = manualWindows[groupID] {
            retiredManualWindows.append(closingWindow)
            manualWindows[groupID] = nil
        }

        if let closingDelegate = manualWindowDelegates[groupID] {
            retiredManualWindowDelegates.append(closingDelegate)
            manualWindowDelegates[groupID] = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700)) { [weak self] in
            self?.finalizeManualWindowClose(groupID: groupID)
        }
    }

    private func finalizeManualWindowClose(groupID: UUID) {
        closingManualGroupIDs.remove(groupID)

        guard !isTerminating, groupID != primaryGroupID else {
            persistSoon()
            return
        }

        mergeGroupIntoPrimary(groupID)
    }

    private func mergeGroupIntoPrimary(_ groupID: UUID) {
        guard let sourceIndex = groups.firstIndex(where: { $0.id == groupID }),
              let target = store(for: primaryGroupID) else {
            return
        }

        let source = groups[sourceIndex].store
        for buffer in source.buffers {
            if !buffer.text.isEmpty || buffer.isDirty || buffer.filePath != nil {
                target.appendMovedBuffer(buffer)
            }
        }

        groups.remove(at: sourceIndex)
        activeGroupID = primaryGroupID
        persistSoon()
    }

    private static func defaultGroupState() -> EditorWindowGroupState {
        let buffer = EditorBuffer.scratch(index: 1)
        return EditorWindowGroupState(id: UUID(), selectedBufferID: buffer.id, buffers: [buffer])
    }
}

@MainActor
final class EditorWindowGroup: Identifiable {
    let id: UUID
    let store: EditorStore

    init(id: UUID, store: EditorStore) {
        self.id = id
        self.store = store
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    private let onWillClose: () -> Void

    init(onWillClose: @escaping () -> Void) {
        self.onWillClose = onWillClose
    }

    func windowWillClose(_ notification: Notification) {
        onWillClose()
    }
}
