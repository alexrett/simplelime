import AppKit
import SwiftUI

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var groups: [EditorWindowGroup] = []
    @Published var activeGroupID: UUID?
    @Published private(set) var workspaceProfiles: [WorkspaceProfile] = []
    @Published private(set) var activeWorkspaceID: UUID
    @Published private(set) var localAutomationBridgeStatus: String?
    @Published private(set) var appDataSyncStatus: String?

    let networkShare = NetworkShareService()

    private var workspacePersistence: WorkspacePersistence
    private var persistence: SessionPersistence
    private let opensRestoredManualWindows: Bool
    private let restoresPersistedSession: Bool
    private var pendingSaveTask: Task<Void, Never>?
    private var openURLObserver: NSObjectProtocol?
    private var collaborationLinkObserver: NSObjectProtocol?
    private var manualWindows: [UUID: NSWindow] = [:]
    private var manualWindowDelegates: [UUID: WindowDelegate] = [:]
    // Keep closed manual windows alive for the process lifetime. Releasing these custom
    // full-size-content SwiftUI windows during or shortly after close can crash AppKit.
    private var retiredManualWindows: [NSWindow] = []
    private var retiredManualWindowDelegates: [WindowDelegate] = []
    private var closingManualGroupIDs = Set<UUID>()
    private var isTerminating = false
    private var localAutomationBridge: LocalAutomationBridge?
    private var appDataRootSnapshot: AppDataRootSnapshot?
    private var appDataContentSnapshot: AppDataContentSnapshot?
    private var appDataRootMonitorTask: Task<Void, Never>?

    init(
        workspacePersistence: WorkspacePersistence = WorkspacePersistence(),
        opensRestoredManualWindows: Bool = true,
        restoresPersistedSession: Bool = !SimpleLimeLaunchOptions.shouldSkipRestoredSession(),
        observesExternalOpenURLs: Bool = true,
        startsLocalAutomationBridge: Bool? = nil,
        monitorsExternalAppDataChanges: Bool? = nil,
        localAutomationBridgeFactory: (@MainActor @escaping (LocalAutomationBridgeEvent) -> LocalAutomationBridgeResponse) -> LocalAutomationBridge = { handler in
            LocalAutomationBridge(handler: handler)
        }
    ) {
        self.workspacePersistence = workspacePersistence
        self.opensRestoredManualWindows = opensRestoredManualWindows
        self.restoresPersistedSession = restoresPersistedSession

        let workspaceIndex = workspacePersistence.loadIndex()
        let profiles = workspaceIndex.profiles.isEmpty ? [WorkspaceProfile.default] : workspaceIndex.profiles
        let selectedWorkspaceID = workspaceIndex.selectedWorkspaceID.flatMap { selectedID in
            profiles.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? profiles.first?.id ?? WorkspaceProfile.defaultID
        workspaceProfiles = profiles
        activeWorkspaceID = selectedWorkspaceID
        let activeProfile = profiles.first(where: { $0.id == selectedWorkspaceID }) ?? WorkspaceProfile.default
        persistence = workspacePersistence.sessionPersistence(for: activeProfile)

        let session = currentLaunchWindowSession()
        let states = session.groups
        let resolvedStates = states.isEmpty ? [Self.defaultGroupState()] : states
        groups = resolvedStates.map { makeGroup(from: $0) }
        activeGroupID = session.selectedGroupID.flatMap { selectedGroupID in
            groups.contains(where: { $0.id == selectedGroupID }) ? selectedGroupID : nil
        } ?? groups.first?.id
        networkShare.onReceivedNote = { [weak self] note in
            self?.importSharedNote(note)
        }
        networkShare.onReceivedCollaboration = { [weak self] payload in
            self?.handleCollaborationPayload(payload)
        }
        if observesExternalOpenURLs {
            installOpenURLObserver()
        }
        let shouldStartLocalAutomationBridge = startsLocalAutomationBridge ?? !Self.isRunningTests
        if shouldStartLocalAutomationBridge {
            startLocalAutomationBridge(factory: localAutomationBridgeFactory)
        }
        refreshAppDataSnapshots()
        let shouldMonitorExternalAppDataChanges = monitorsExternalAppDataChanges ?? !Self.isRunningTests
        if shouldMonitorExternalAppDataChanges {
            startAppDataRootChangeMonitor()
        }

        DispatchQueue.main.async { [weak self] in
            self?.openPendingExternalFiles()
            self?.openRestoredManualWindowsIfNeeded()
        }
    }

    deinit {
        pendingSaveTask?.cancel()
        appDataRootMonitorTask?.cancel()
        localAutomationBridge?.stop()
        if let openURLObserver {
            NotificationCenter.default.removeObserver(openURLObserver)
        }
        if let collaborationLinkObserver {
            NotificationCenter.default.removeObserver(collaborationLinkObserver)
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

    var activeWorkspaceName: String {
        activeWorkspaceProfile?.name ?? WorkspaceProfile.default.name
    }

    var activeWorkspaceProfile: WorkspaceProfile? {
        workspaceProfiles.first(where: { $0.id == activeWorkspaceID })
    }

    func store(for groupID: UUID?) -> EditorStore? {
        guard let groupID else { return nil }
        return groups.first(where: { $0.id == groupID })?.store
    }

    func activate(_ groupID: UUID) {
        activeGroupID = groupID
    }

    @discardableResult
    func createWorkspace(named rawName: String, switchToCreatedWorkspace: Bool = true) -> WorkspaceProfile? {
        let name = WorkspacePersistence.normalizedName(rawName)
        guard !name.isEmpty else {
            activeStore?.lastError = "Workspace name cannot be empty."
            return nil
        }

        guard !workspaceProfiles.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            activeStore?.lastError = "A workspace named \(name) already exists."
            return nil
        }

        let now = Date()
        let profile = WorkspaceProfile(
            id: UUID(),
            name: name,
            createdAt: now,
            updatedAt: now,
            documentCatalogRootPath: nil
        )
        workspaceProfiles.append(profile)
        persistWorkspaceIndex()

        if switchToCreatedWorkspace {
            switchWorkspace(profile.id)
        }

        return profile
    }

    func createWorkspaceWithPrompt() {
        promptForWorkspaceName(title: "New Workspace", defaultName: "") { [weak self] name in
            self?.createWorkspace(named: name)
        }
    }

    @discardableResult
    func renameActiveWorkspace(to rawName: String) -> Bool {
        let name = WorkspacePersistence.normalizedName(rawName)
        guard !name.isEmpty else {
            activeStore?.lastError = "Workspace name cannot be empty."
            return false
        }

        guard !workspaceProfiles.contains(where: {
            $0.id != activeWorkspaceID && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            activeStore?.lastError = "A workspace named \(name) already exists."
            return false
        }

        guard let index = workspaceProfiles.firstIndex(where: { $0.id == activeWorkspaceID }) else {
            return false
        }

        workspaceProfiles[index].name = name
        workspaceProfiles[index].updatedAt = Date()
        refreshManualWindowTitles()
        persistWorkspaceIndex()
        return true
    }

    func renameActiveWorkspaceWithPrompt() {
        promptForWorkspaceName(title: "Rename Workspace", defaultName: activeWorkspaceName) { [weak self] name in
            self?.renameActiveWorkspace(to: name)
        }
    }

    func switchWorkspace(_ workspaceID: UUID) {
        guard workspaceID != activeWorkspaceID,
              let profile = workspaceProfiles.first(where: { $0.id == workspaceID }) else {
            return
        }

        persistNow()
        closeManualWindowsForWorkspaceSwitch()

        activeWorkspaceID = profile.id
        persistence = workspacePersistence.sessionPersistence(for: profile)
        loadGroupsFromActivePersistence()
        persistWorkspaceIndex()
        openRestoredManualWindowsIfNeeded()
        refreshAppDataSnapshots()
    }

    func reloadAppDataRoot(workspacePersistence newWorkspacePersistence: WorkspacePersistence = WorkspacePersistence()) {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        closeManualWindowsForWorkspaceSwitch()

        workspacePersistence = newWorkspacePersistence
        let workspaceIndex = workspacePersistence.loadIndex()
        let profiles = workspaceIndex.profiles.isEmpty ? [WorkspaceProfile.default] : workspaceIndex.profiles
        let selectedWorkspaceID = workspaceIndex.selectedWorkspaceID.flatMap { selectedID in
            profiles.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? profiles.first?.id ?? WorkspaceProfile.defaultID

        workspaceProfiles = profiles
        activeWorkspaceID = selectedWorkspaceID
        let activeProfile = profiles.first(where: { $0.id == selectedWorkspaceID }) ?? WorkspaceProfile.default
        persistence = workspacePersistence.sessionPersistence(for: activeProfile)
        loadGroupsFromActivePersistence()
        persistWorkspaceIndex()
        openRestoredManualWindowsIfNeeded()
        refreshManualWindowTitles()
        refreshAppDataSnapshots()
    }

    @discardableResult
    func reloadAppDataRootIfChanged() -> Bool {
        let nextRootSnapshot = AppDataRootSnapshot.capture(rootURL: workspacePersistence.appDataRootURL)
        guard let previousRootSnapshot = appDataRootSnapshot else {
            appDataRootSnapshot = nextRootSnapshot
            appDataContentSnapshot = currentAppDataContentSnapshot()
            return false
        }
        guard previousRootSnapshot != nextRootSnapshot else { return false }

        if let appDataContentSnapshot,
           appDataContentSnapshot != currentAppDataContentSnapshot() {
            appDataSyncStatus = "App data changed on disk; pending local edits were kept in the current window."
            activeStore?.lastError = appDataSyncStatus
            return false
        }

        reloadAppDataRoot(workspacePersistence: workspacePersistence)
        appDataSyncStatus = nextRootSnapshot.reachedEntryLimit
            ? "App data reloaded from disk after detecting external changes. Some files were outside the sync scan limit."
            : "App data reloaded from disk after detecting external changes."
        return true
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
        ensureVisibleEditorWindow()
    }

    func importSharedNote(_ note: SharedNotePayload) {
        let store = activeStore ?? groups.first?.store
        store?.importSharedNote(note)
    }

    func handleLocalAutomationEvent(_ event: LocalAutomationBridgeEvent) -> LocalAutomationBridgeResponse {
        let store = activeStore ?? groups.first?.store

        switch event {
        case .health:
            return LocalAutomationBridgeResponse(
                ok: true,
                message: "SimpleLime local automation bridge is running for workspace \(activeWorkspaceName).",
                bufferTitle: store?.selectedBuffer?.displayTitle
            )
        case .scribe(let request):
            guard let store else {
                return LocalAutomationBridgeResponse(ok: false, message: "No editor window is available.", bufferTitle: nil)
            }
            return store.appendScribeTranscript(request)
        case .command(let request):
            guard let store else {
                return LocalAutomationBridgeResponse(ok: false, message: "No editor window is available.", bufferTitle: nil)
            }
            return store.performLocalAutomationCommand(request)
        }
    }

    func handleCollaborationPayload(_ payload: CollaborationPayload) {
        if let store = groups.map(\.store).first(where: { $0.canHandleCollaborationPayload(payload) }) {
            store.handleCollaborationPayload(payload)
            return
        }

        let store = activeStore ?? groups.first?.store
        store?.handleCollaborationPayload(payload)
    }

    func prepareForTermination() {
        isTerminating = true
    }

    func persistNow() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        groups.forEach { $0.store.persistCommentsNow() }
        captureActiveWorkspaceDocumentCatalogRoot()

        do {
            try workspacePersistence.save(profiles: workspaceProfiles, selectedWorkspaceID: activeWorkspaceID)
            try persistence.save(
                windowGroups: groups.map {
                    EditorWindowGroupState(
                        id: $0.id,
                        selectedBufferID: $0.store.selectedBufferID,
                        buffers: $0.store.buffersForPersistence
                    )
                },
                selectedGroupID: activeGroupID
            )
            refreshAppDataSnapshots()
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

            _ = AppDelegate.drainPendingOpenURLs()
            Task { @MainActor [weak self] in
                self?.scheduleExternalOpen(fileURLs: urls, collaborationURLs: [])
            }
        }

        collaborationLinkObserver = NotificationCenter.default.addObserver(
            forName: .simpleLimeOpenCollaborationLinks,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let urls = notification.userInfo?["urls"] as? [URL] else {
                return
            }

            _ = AppDelegate.drainPendingCollaborationLinks()
            Task { @MainActor [weak self] in
                self?.scheduleExternalOpen(fileURLs: [], collaborationURLs: urls)
            }
        }
    }

    private func startLocalAutomationBridge(
        factory: (@MainActor @escaping (LocalAutomationBridgeEvent) -> LocalAutomationBridgeResponse) -> LocalAutomationBridge
    ) {
        let bridge = factory { [weak self] event in
            self?.handleLocalAutomationEvent(event) ??
                LocalAutomationBridgeResponse(ok: false, message: "SimpleLime workspace is unavailable.", bufferTitle: nil)
        }

        do {
            try bridge.start()
            localAutomationBridge = bridge
            localAutomationBridgeStatus = "Local bridge: http://127.0.0.1:\(LocalAutomationBridge.defaultPort)"
        } catch {
            localAutomationBridgeStatus = "Local bridge unavailable: \(error.localizedDescription)"
            activeStore?.lastError = localAutomationBridgeStatus
        }
    }

    private func startAppDataRootChangeMonitor() {
        appDataRootMonitorTask?.cancel()
        appDataRootMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    _ = self.reloadAppDataRootIfChanged()
                }
            }
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTestCase") != nil ||
            NSClassFromString("XCTest.XCTestCase") != nil
    }

    private func openPendingExternalFiles() {
        scheduleExternalOpen(
            fileURLs: AppDelegate.drainPendingOpenURLs(),
            collaborationURLs: AppDelegate.drainPendingCollaborationLinks()
        )
    }

    private func scheduleExternalOpen(fileURLs: [URL], collaborationURLs: [URL]) {
        guard !fileURLs.isEmpty || !collaborationURLs.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.openFilesInActiveWindow(fileURLs)
                self.openCollaborationLinks(collaborationURLs)
            }
        }
    }

    private func openCollaborationLinks(_ urls: [URL]) {
        guard let url = urls.first else { return }
        let store = activeStore ?? groups.first?.store
        store?.joinCollaborationRelay(link: url.absoluteString)
        ensureVisibleEditorWindow()
    }

    private func ensureVisibleEditorWindow() {
        guard !Self.isRunningTests else { return }

        let hasVisibleWindow = NSApp.windows.contains { [manualWindows] window in
            guard window.isVisible && !window.isMiniaturized else { return false }
            if manualWindows.values.contains(where: { $0 === window }) {
                return true
            }
            return EditorWindowChrome.isEditorWindow(window)
        }
        guard !hasVisibleWindow else { return }

        openManualWindow(for: activeGroupID ?? primaryGroupID)
    }

    private func loadGroupsFromActivePersistence() {
        let session = currentLaunchWindowSession()
        let states = session.groups
        let resolvedStates = states.isEmpty ? [Self.defaultGroupState()] : states
        groups = resolvedStates.map { makeGroup(from: $0) }
        activeGroupID = session.selectedGroupID.flatMap { selectedGroupID in
            groups.contains(where: { $0.id == selectedGroupID }) ? selectedGroupID : nil
        } ?? groups.first?.id
    }

    private func currentLaunchWindowSession() -> (groups: [EditorWindowGroupState], selectedGroupID: UUID?) {
        restoresPersistedSession ? persistence.loadWindowSession() : ([], nil)
    }

    private func persistWorkspaceIndex() {
        do {
            try workspacePersistence.save(profiles: workspaceProfiles, selectedWorkspaceID: activeWorkspaceID)
            refreshAppDataSnapshots()
        } catch {
            activeStore?.lastError = "Could not persist workspaces: \(error.localizedDescription)"
        }
    }

    private func refreshAppDataSnapshots() {
        appDataRootSnapshot = AppDataRootSnapshot.capture(rootURL: workspacePersistence.appDataRootURL)
        appDataContentSnapshot = currentAppDataContentSnapshot()
    }

    private func currentAppDataContentSnapshot() -> AppDataContentSnapshot {
        AppDataContentSnapshot(
            profiles: workspaceProfiles,
            activeWorkspaceID: activeWorkspaceID,
            groups: groups.map {
                AppDataContentSnapshot.Group(
                    id: $0.id,
                    buffers: $0.store.buffersForPersistence.map(AppDataContentSnapshot.Buffer.init)
                )
            }
        )
    }

    private func promptForWorkspaceName(
        title: String,
        defaultName: String,
        completion: @escaping (String) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Name this workspace."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultName
        field.placeholderString = "Workspace name"
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            completion(field.stringValue)
        }
    }

    private func openRestoredManualWindowsIfNeeded() {
        guard opensRestoredManualWindows else { return }
        openRestoredManualWindows()
    }

    private func openRestoredManualWindows() {
        for group in groups.dropFirst() {
            openManualWindow(for: group.id)
        }
    }

    private func closeManualWindowsForWorkspaceSwitch() {
        guard !manualWindows.isEmpty else { return }

        let closingIDs = Set(manualWindows.keys)
        closingManualGroupIDs.formUnion(closingIDs)

        retiredManualWindows.append(contentsOf: manualWindows.values)
        retiredManualWindowDelegates.append(contentsOf: manualWindowDelegates.values)

        for window in manualWindows.values {
            window.close()
        }

        manualWindows.removeAll()
        manualWindowDelegates.removeAll()
        closingManualGroupIDs.subtract(closingIDs)
    }

    private func refreshManualWindowTitles() {
        let title = "SimpleLime - \(activeWorkspaceName)"
        for window in manualWindows.values {
            EditorWindowChrome.configure(window, logicalTitle: title)
        }
    }

    private func makeGroup(from state: EditorWindowGroupState) -> EditorWindowGroup {
        let store = EditorStore(
            windowGroupID: state.id,
            initialBuffers: state.buffers.isEmpty ? [EditorBuffer.scratch(index: 1)] : state.buffers,
            selectedID: state.selectedBufferID,
            persistence: nil,
            taskPersistence: taskPersistenceForActiveWorkspace(),
            globalTaskPersistence: workspacePersistence.globalTaskBoardPersistence(),
            networkShare: networkShare,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
        store.applyWorkspaceDocumentCatalogRoot(activeWorkspaceProfile?.documentCatalogRootPath)
        store.onPersistRequested = { [weak self] in
            self?.persistSoon()
        }
        store.onMoveTabBetweenGroups = { [weak self] sourceGroupID, targetGroupID, bufferID in
            self?.moveTab(sourceGroupID: sourceGroupID, targetGroupID: targetGroupID, bufferID: bufferID)
        }
        store.onDocumentCatalogRootChanged = { [weak self, weak store] rootPath in
            guard let self, let sourceStore = store else { return }
            self.updateActiveWorkspaceDocumentCatalogRoot(rootPath, sourceStore: sourceStore)
        }
        store.onGlobalManualTasksChanged = { [weak self, weak store] tasks in
            guard let self, let sourceStore = store else { return }
            self.updateGlobalManualTasks(tasks, sourceStore: sourceStore)
        }

        return EditorWindowGroup(id: state.id, store: store)
    }

    private func captureActiveWorkspaceDocumentCatalogRoot() {
        let rootPath = activeStore?.documentCatalogRootPath
            ?? groups.map(\.store).compactMap(\.documentCatalogRootPath).first
        updateActiveWorkspaceProfileDocumentCatalogRoot(rootPath)
    }

    private func updateActiveWorkspaceDocumentCatalogRoot(_ rootPath: String?, sourceStore: EditorStore) {
        updateActiveWorkspaceProfileDocumentCatalogRoot(rootPath)
        for group in groups where group.store !== sourceStore {
            group.store.applyWorkspaceDocumentCatalogRoot(rootPath)
        }
        persistSoon()
    }

    private func updateActiveWorkspaceProfileDocumentCatalogRoot(_ rootPath: String?) {
        guard let index = workspaceProfiles.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }
        guard workspaceProfiles[index].documentCatalogRootPath != rootPath else { return }
        workspaceProfiles[index].documentCatalogRootPath = rootPath
        workspaceProfiles[index].updatedAt = Date()
    }

    private func updateGlobalManualTasks(_ tasks: [ManualTask], sourceStore: EditorStore) {
        for group in groups where group.store !== sourceStore {
            group.store.replaceGlobalManualTasks(tasks)
        }
    }

    private func taskPersistenceForActiveWorkspace() -> TaskBoardPersistence? {
        guard let profile = activeWorkspaceProfile else { return nil }
        return workspacePersistence.taskBoardPersistence(for: profile)
    }

    private func openManualWindow(for groupID: UUID) {
        if let window = manualWindows[groupID] {
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let store = store(for: groupID) else { return }

        let rootView = ContentView(store: store, workspace: self) { [weak self] in
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
        let logicalTitle = "SimpleLime - \(activeWorkspaceName)"
        window.title = logicalTitle
        window.center()
        EditorWindowChrome.configure(window, logicalTitle: logicalTitle)
        window.isReleasedWhenClosed = false

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

private struct AppDataContentSnapshot: Equatable {
    struct Group: Equatable {
        var id: UUID
        var buffers: [Buffer]
    }

    struct Buffer: Equatable {
        var id: UUID
        var title: String
        var kind: BufferKind
        var filePath: String?
        var text: String
        var language: EditorLanguage
        var aiSessions: [AIChatSession]
        var selectedAIChatSessionID: UUID?
        var savePolicy: BufferSavePolicy
        var isLargeFileMode: Bool
        var fileSizeBytes: Int64?
        var largeFileSourcePath: String?
        var largeFileSourceStartOffsetBytes: Int64?
        var largeFileSourceByteCount: Int?
        var largeFileSourceFileSizeBytes: Int64?
        var isEncrypted: Bool

        init(_ buffer: EditorBuffer) {
            id = buffer.id
            title = buffer.title
            kind = buffer.kind
            filePath = buffer.filePath
            text = buffer.text
            language = buffer.language
            aiSessions = buffer.aiSessions
            selectedAIChatSessionID = buffer.selectedAIChatSessionID
            savePolicy = buffer.savePolicy
            isLargeFileMode = buffer.isLargeFileMode
            fileSizeBytes = buffer.fileSizeBytes
            largeFileSourcePath = buffer.largeFileSourcePath
            largeFileSourceStartOffsetBytes = buffer.largeFileSourceStartOffsetBytes
            largeFileSourceByteCount = buffer.largeFileSourceByteCount
            largeFileSourceFileSizeBytes = buffer.largeFileSourceFileSizeBytes
            isEncrypted = buffer.isEncrypted
        }
    }

    var profiles: [WorkspaceProfile]
    var activeWorkspaceID: UUID
    var groups: [Group]
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
