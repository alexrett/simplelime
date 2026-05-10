import AppKit
import Foundation

@MainActor
final class EditorStore: ObservableObject {
    @Published var buffers: [EditorBuffer]
    @Published var selectedBufferID: UUID?
    @Published var findQuery = "" {
        didSet {
            if findQuery != oldValue {
                globalReplaceStatusText = ""
            }
        }
    }
    @Published var replaceText = "" {
        didSet {
            if replaceText != oldValue {
                globalReplaceStatusText = ""
            }
        }
    }
    @Published var findUsesRegex = false {
        didSet {
            if findUsesRegex != oldValue {
                globalReplaceStatusText = ""
            }
        }
    }
    @Published var findMatchesCase = false {
        didSet {
            if findMatchesCase != oldValue {
                globalReplaceStatusText = ""
            }
        }
    }
    @Published var findWholeWord = false {
        didSet {
            if findWholeWord != oldValue {
                globalReplaceStatusText = ""
            }
        }
    }
    @Published var globalReplaceStatusText = ""
    @Published var findPanelMode: FindPanelMode = .hidden
    @Published var isPreviewVisible = false
    @Published var isOutlineVisible: Bool {
        didSet {
            UserDefaults.standard.set(isOutlineVisible, forKey: Self.outlineDefaultsKey)
        }
    }
    @Published var isFocusModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isFocusModeEnabled, forKey: Self.focusModeDefaultsKey)
        }
    }
    @Published var isTypewriterModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTypewriterModeEnabled, forKey: Self.typewriterModeDefaultsKey)
        }
    }
    @Published var isMiniMapVisible: Bool {
        didSet {
            UserDefaults.standard.set(isMiniMapVisible, forKey: Self.miniMapDefaultsKey)
        }
    }
    @Published var isWysiwygModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isWysiwygModeEnabled, forKey: Self.wysiwygModeDefaultsKey)
        }
    }
    @Published var isDocumentCatalogVisible: Bool {
        didSet {
            UserDefaults.standard.set(isDocumentCatalogVisible, forKey: Self.documentCatalogVisibleDefaultsKey)
        }
    }
    @Published var documentCatalogRootPath: String? {
        didSet {
            if let documentCatalogRootPath {
                UserDefaults.standard.set(documentCatalogRootPath, forKey: Self.documentCatalogRootDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.documentCatalogRootDefaultsKey)
            }
        }
    }
    @Published var documentCatalogNodes: [DocumentCatalogNode] = []
    @Published var documentCatalogQuery = ""
    @Published var isCommandPaletteVisible = false
    @Published var fontSize: Double = 14
    @Published var wrapsLines: Bool {
        didSet {
            UserDefaults.standard.set(wrapsLines, forKey: Self.wrapsLinesDefaultsKey)
        }
    }
    @Published var lastError: String?
    @Published var pendingCloseBuffer: EditorBuffer?
    @Published var isAIPanelVisible = false
    @Published var isNetworkPanelVisible = false
    @Published var aiRunningSessions = Set<UUID>()
    @Published var aiSessionStatuses: [UUID: String] = [:]

    let windowGroupID: UUID
    let networkShare: NetworkShareService
    var onPersistRequested: (() -> Void)?
    var onMoveTabBetweenGroups: ((_ sourceGroupID: UUID, _ targetGroupID: UUID, _ bufferID: UUID) -> Void)?

    private let persistence: SessionPersistence?
    private let aiFileBridge = AIBufferFileBridge()
    private var pendingSaveTask: Task<Void, Never>?
    private var editorCommandHandler: ((EditorCommand) -> Bool)?
    private var aiClients: [UUID: ACPAgentClient] = [:]
    private var aiChatIDsByAgentSession: [String: UUID] = [:]
    private var aiStreamingMessageIDs: [UUID: UUID] = [:]
    private var pendingFileLoadIDs = Set<UUID>()

    private static let wrapsLinesDefaultsKey = "editor.wrapsLines"
    private static let outlineDefaultsKey = "editor.markdownOutline"
    private static let focusModeDefaultsKey = "editor.focusMode"
    private static let typewriterModeDefaultsKey = "editor.typewriterMode"
    private static let miniMapDefaultsKey = "editor.miniMap"
    private static let wysiwygModeDefaultsKey = "editor.markdownWysiwyg"
    private static let documentCatalogVisibleDefaultsKey = "editor.documentCatalogVisible"
    private static let documentCatalogRootDefaultsKey = "editor.documentCatalogRoot"

    init(
        windowGroupID: UUID = UUID(),
        initialBuffers: [EditorBuffer]? = nil,
        selectedID: UUID? = nil,
        persistence: SessionPersistence? = SessionPersistence(),
        networkShare: NetworkShareService = NetworkShareService(),
        autoPersistOnInit: Bool = true,
        registerNetworkReceiver: Bool = true
    ) {
        self.windowGroupID = windowGroupID
        self.persistence = persistence
        self.networkShare = networkShare
        self.wrapsLines = UserDefaults.standard.object(forKey: Self.wrapsLinesDefaultsKey) as? Bool ?? true
        self.isOutlineVisible = UserDefaults.standard.object(forKey: Self.outlineDefaultsKey) as? Bool ?? false
        self.isFocusModeEnabled = UserDefaults.standard.object(forKey: Self.focusModeDefaultsKey) as? Bool ?? false
        self.isTypewriterModeEnabled = UserDefaults.standard.object(forKey: Self.typewriterModeDefaultsKey) as? Bool ?? false
        self.isMiniMapVisible = UserDefaults.standard.object(forKey: Self.miniMapDefaultsKey) as? Bool ?? true
        self.isWysiwygModeEnabled = UserDefaults.standard.object(forKey: Self.wysiwygModeDefaultsKey) as? Bool ?? false
        self.isDocumentCatalogVisible = UserDefaults.standard.object(forKey: Self.documentCatalogVisibleDefaultsKey) as? Bool ?? false
        self.documentCatalogRootPath = UserDefaults.standard.string(forKey: Self.documentCatalogRootDefaultsKey)
        let loaded: (buffers: [EditorBuffer], selectedID: UUID?)

        if let initialBuffers {
            loaded = (initialBuffers, selectedID)
        } else {
            loaded = persistence?.load() ?? ([], nil)
        }

        if loaded.buffers.isEmpty {
            let initial = EditorBuffer.scratch(index: 1)
            buffers = [initial]
            selectedBufferID = initial.id
        } else {
            buffers = loaded.buffers
            selectedBufferID = loaded.selectedID ?? loaded.buffers.first?.id
        }

        normalizeLoadedEditorModeState()

        if registerNetworkReceiver {
            networkShare.onReceivedNote = { [weak self] note in
                self?.importSharedNote(note)
            }
        }

        if autoPersistOnInit {
            persistSoon()
        }

        if documentCatalogRootPath != nil {
            refreshDocumentCatalog()
        }
    }

    deinit {
        pendingSaveTask?.cancel()
        aiClients.values.forEach { $0.stop() }
    }

    var selectedBuffer: EditorBuffer? {
        guard let selectedBufferID else { return nil }
        return buffers.first { $0.id == selectedBufferID }
    }

    var selectedIndex: Int? {
        guard let selectedBufferID else { return nil }
        return buffers.firstIndex { $0.id == selectedBufferID }
    }

    var globalSearchResults: [SearchResult] {
        searchAllSources(query: findQuery)
    }

    var findStatusText: String {
        if let error = findValidationError {
            return error
        }

        guard !findQuery.isEmpty, let selectedBuffer else {
            return ""
        }

        let matches = allMatches(in: selectedBuffer.text)
        guard !matches.isEmpty else {
            return "No matches"
        }

        let selected = normalizedRanges(selectedBuffer.selectionRanges, in: selectedBuffer.text).first
        let currentIndex = selected.flatMap { selection in
            matches.firstIndex { NSEqualRanges($0.range, selection.nsRange) }
        } ?? 0

        return "\(currentIndex + 1) of \(matches.count)"
    }

    var findValidationError: String? {
        guard findUsesRegex, !findQuery.isEmpty else { return nil }
        do {
            _ = try makeFindRegex()
            return nil
        } catch {
            return "Invalid regex"
        }
    }

    var selectedBufferLanguage: EditorLanguage {
        selectedBuffer?.language ?? .plain
    }

    var selectedAIChatSession: AIChatSession? {
        guard let selectedBuffer else { return nil }
        return selectedAIChatSession(in: selectedBuffer.id)
    }

    func select(_ id: UUID?) {
        selectedBufferID = id
        persistSoon()
    }

    func toggleAIPanel() {
        isAIPanelVisible.toggle()
    }

    func showAIPanel() {
        isAIPanelVisible = true
    }

    func toggleNetworkPanel() {
        isNetworkPanelVisible.toggle()
    }

    func showNetworkPanel() {
        isNetworkPanelVisible = true
    }

    func selectedAIChatSession(in bufferID: UUID) -> AIChatSession? {
        guard let buffer = buffers.first(where: { $0.id == bufferID }) else { return nil }

        if let selectedID = buffer.selectedAIChatSessionID,
           let session = buffer.aiSessions.first(where: { $0.id == selectedID }) {
            return session
        }

        return buffer.aiSessions.first
    }

    func createAIChat(provider: AIAgentProvider) {
        guard let selectedIndex else { return }

        let index = buffers[selectedIndex].aiSessions.filter { $0.provider == provider }.count + 1
        let session = AIChatSession.new(provider: provider, index: index)
        buffers[selectedIndex].aiSessions.append(session)
        buffers[selectedIndex].selectedAIChatSessionID = session.id
        isAIPanelVisible = true
        persistSoon()
    }

    func selectAIChat(_ sessionID: UUID?, in bufferID: UUID) {
        guard let index = buffers.firstIndex(where: { $0.id == bufferID }) else { return }
        buffers[index].selectedAIChatSessionID = sessionID
        persistSoon()
    }

    func deleteAIChat(_ sessionID: UUID, in bufferID: UUID) {
        guard let bufferIndex = buffers.firstIndex(where: { $0.id == bufferID }),
              let sessionIndex = buffers[bufferIndex].aiSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        aiClients.removeValue(forKey: sessionID)?.stop()
        aiRunningSessions.remove(sessionID)
        aiSessionStatuses.removeValue(forKey: sessionID)
        aiStreamingMessageIDs.removeValue(forKey: sessionID)
        buffers[bufferIndex].aiSessions.remove(at: sessionIndex)
        buffers[bufferIndex].selectedAIChatSessionID = buffers[bufferIndex].aiSessions.first?.id
        persistSoon()
    }

    func isAIRunning(_ sessionID: UUID) -> Bool {
        aiRunningSessions.contains(sessionID)
    }

    func aiStatus(for sessionID: UUID) -> String? {
        aiSessionStatuses[sessionID]
    }

    func sendAIMessage(_ text: String, in bufferID: UUID, sessionID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let location = aiChatLocation(sessionID),
              buffers[location.bufferIndex].id == bufferID else {
            return
        }

        buffers[location.bufferIndex].aiSessions[location.sessionIndex].messages.append(.user(trimmed))
        buffers[location.bufferIndex].aiSessions[location.sessionIndex].updatedAt = Date()
        aiRunningSessions.insert(sessionID)
        aiSessionStatuses[sessionID] = "Starting \(buffers[location.bufferIndex].aiSessions[location.sessionIndex].provider.displayName)..."
        aiStreamingMessageIDs.removeValue(forKey: sessionID)
        persistSoon()

        Task { [weak self] in
            await self?.runAIPrompt(bufferID: bufferID, chatID: sessionID, userText: trimmed)
        }
    }

    func cancelAIChat(_ sessionID: UUID) {
        guard let agentSessionID = aiChatIDsByAgentSession.first(where: { $0.value == sessionID })?.key else {
            return
        }

        aiClients[sessionID]?.cancel(sessionID: agentSessionID)
        aiSessionStatuses[sessionID] = "Cancelling..."
    }

    func selectNextTab() {
        guard !buffers.isEmpty else { return }
        let currentIndex = selectedIndex ?? -1
        let nextIndex = (currentIndex + 1) % buffers.count
        selectedBufferID = buffers[nextIndex].id
        persistSoon()
    }

    func selectPreviousTab() {
        guard !buffers.isEmpty else { return }
        let currentIndex = selectedIndex ?? 0
        let previousIndex = (currentIndex - 1 + buffers.count) % buffers.count
        selectedBufferID = buffers[previousIndex].id
        persistSoon()
    }

    func registerEditorCommandHandler(_ handler: @escaping (EditorCommand) -> Bool) {
        editorCommandHandler = handler
    }

    func newScratch() {
        let nextIndex = buffers.filter { $0.kind == .scratch }.count + 1
        let buffer = EditorBuffer.scratch(index: nextIndex)
        buffers.append(buffer)
        selectedBufferID = buffer.id
        persistSoon()
    }

    func closeSelected() {
        guard let selectedBufferID else { return }
        closeBuffer(id: selectedBufferID)
    }

    func closeBuffer(id: UUID) {
        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return }
        let buffer = buffers[index]

        if !buffer.text.isEmpty || buffer.isDirty {
            pendingCloseBuffer = buffer
            return
        }

        forceCloseBuffer(id: id)
    }

    func detachSelectedBufferForNewWindow() -> EditorBuffer? {
        guard let selectedBufferID else { return nil }
        return detachBuffer(id: selectedBufferID)
    }

    func copySelectedBufferForNewWindow() -> EditorBuffer? {
        guard var buffer = selectedBuffer else { return nil }
        let now = Date()
        buffer.id = UUID()
        buffer.createdAt = now
        buffer.updatedAt = now
        buffer.aiSessions = []
        buffer.selectedAIChatSessionID = nil
        return buffer
    }

    func detachBuffer(id: UUID) -> EditorBuffer? {
        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return nil }
        let buffer = buffers[index]
        stopAIClients(for: buffer)
        let wasSelected = selectedBufferID == id
        buffers.remove(at: index)

        if buffers.isEmpty {
            let replacement = EditorBuffer.scratch(index: 1)
            buffers = [replacement]
            selectedBufferID = replacement.id
        } else if wasSelected {
            let nextIndex = min(index, buffers.count - 1)
            selectedBufferID = buffers[nextIndex].id
        }

        persistSoon()
        return buffer
    }

    func appendMovedBuffer(_ buffer: EditorBuffer) {
        if buffers.count == 1, let only = buffers.first, only.kind == .scratch, only.text.isEmpty, !only.isDirty {
            buffers = [buffer]
        } else {
            buffers.append(buffer)
        }

        selectedBufferID = buffer.id
        persistSoon()
    }

    func moveTabFromGroup(_ sourceGroupID: UUID, bufferID: UUID) {
        guard sourceGroupID != windowGroupID else { return }
        onMoveTabBetweenGroups?(sourceGroupID, windowGroupID, bufferID)
    }

    func confirmPendingClose() {
        guard let pendingCloseBuffer else { return }
        let id = pendingCloseBuffer.id
        self.pendingCloseBuffer = nil
        forceCloseBuffer(id: id)
    }

    func cancelPendingClose() {
        pendingCloseBuffer = nil
    }

    private func forceCloseBuffer(id: UUID) {
        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedBufferID == id
        buffers.remove(at: index)

        if buffers.isEmpty {
            let buffer = EditorBuffer.scratch(index: 1)
            buffers = [buffer]
            selectedBufferID = buffer.id
        } else if wasSelected {
            let nextIndex = min(index, buffers.count - 1)
            selectedBufferID = buffers[nextIndex].id
        }

        persistSoon()
    }

    func updateSelectedText(_ text: String) {
        guard let selectedBufferID else { return }
        updateText(text, in: selectedBufferID)
    }

    func updateText(_ text: String, in id: UUID) {
        guard let index = buffers.firstIndex(where: { $0.id == id }),
              buffers[index].text != text else {
            return
        }

        buffers[index].text = text
        buffers[index].updatedAt = Date()
        buffers[index].isDirty = buffers[index].kind == .scratch ? !text.isEmpty : true
        persistSoon()
    }

    func updateSelectedSelection(_ ranges: [TextRange]) {
        guard let selectedBufferID else { return }
        updateSelection(ranges, in: selectedBufferID)
    }

    func updateSelection(_ ranges: [TextRange], in id: UUID) {
        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return }
        let normalized = ranges.isEmpty ? [.zero] : ranges

        guard buffers[index].selectionRanges != normalized else { return }
        buffers[index].selectionRanges = normalized
        buffers[index].updatedAt = Date()
        persistSoon()
    }

    func setLanguage(_ language: EditorLanguage) {
        guard let selectedIndex else { return }
        buffers[selectedIndex].language = language
        buffers[selectedIndex].updatedAt = Date()
        persistSoon()
    }

    func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            openFile(at: url)
        }
    }

    func openFiles(at urls: [URL]) {
        for url in urls {
            if Self.isDirectoryURL(url) {
                openFolder(at: url)
            } else {
                openFile(at: url)
            }
        }
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        openFolder(at: url)
    }

    func openFolder(at url: URL) {
        documentCatalogRootPath = url.path
        documentCatalogQuery = ""
        isDocumentCatalogVisible = true
        refreshDocumentCatalog()
    }

    func closeFolder() {
        documentCatalogRootPath = nil
        documentCatalogNodes = []
        documentCatalogQuery = ""
    }

    func toggleDocumentCatalog() {
        isDocumentCatalogVisible.toggle()
    }

    func refreshDocumentCatalog() {
        guard let rootPath = documentCatalogRootPath else {
            documentCatalogNodes = []
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        Task { [weak self, rootPath, rootURL] in
            let nodes = await Task.detached(priority: .userInitiated) {
                Self.buildDocumentCatalogNodes(rootURL: rootURL)
            }.value

            guard self?.documentCatalogRootPath == rootPath else { return }
            self?.documentCatalogNodes = nodes
        }
    }

    func documentCatalogFileMatches(for query: String, limit: Int = 30) -> [DocumentCatalogFileMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = documentCatalogFileNodes(documentCatalogNodes)

        if trimmed.isEmpty {
            return files.prefix(limit).map {
                DocumentCatalogFileMatch(
                    url: $0.url,
                    displayPath: documentCatalogDisplayPath(for: $0.url),
                    score: 0
                )
            }
        }

        return files.compactMap { node -> DocumentCatalogFileMatch? in
            let displayPath = documentCatalogDisplayPath(for: node.url)
            let candidate = "\(displayPath) \(node.name)"
            guard let score = Self.fuzzyScore(candidate: candidate, query: trimmed) else {
                return nil
            }

            return DocumentCatalogFileMatch(url: node.url, displayPath: displayPath, score: score)
        }
        .sorted {
            if $0.score == $1.score {
                return $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
            }
            return $0.score > $1.score
        }
        .prefix(limit)
        .map(\.self)
    }

    func openFile(at url: URL) {
        if let existing = buffers.first(where: { $0.filePath == url.path }) {
            selectedBufferID = existing.id
            return
        }

        let now = Date()
        let bufferID = UUID()
        let buffer = EditorBuffer(
            id: bufferID,
            title: url.lastPathComponent,
            kind: .file,
            filePath: url.path,
            text: "",
            language: EditorLanguage.detect(fileName: url.lastPathComponent, text: ""),
            createdAt: now,
            updatedAt: now,
            isDirty: false,
            selectionRanges: [.zero]
        )

        buffers.append(buffer)
        selectedBufferID = buffer.id
        pendingFileLoadIDs.insert(bufferID)

        Task.detached(priority: .userInitiated) { [weak self, bufferID, url] in
            do {
                var encoding = String.Encoding.utf8
                let text = try String(contentsOf: url, usedEncoding: &encoding)
                let language = EditorLanguage.detect(fileName: url.lastPathComponent, text: text)
                await self?.completeOpenFile(bufferID: bufferID, url: url, result: .success((text, language)))
            } catch {
                await self?.completeOpenFile(bufferID: bufferID, url: url, result: .failure(error))
            }
        }
    }

    private func completeOpenFile(
        bufferID: UUID,
        url: URL,
        result: Result<(String, EditorLanguage), Error>
    ) {
        guard pendingFileLoadIDs.remove(bufferID) != nil,
              let index = buffers.firstIndex(where: { $0.id == bufferID }) else {
            return
        }

        switch result {
        case .success(let payload):
            guard buffers[index].filePath == url.path, !buffers[index].isDirty else { return }
            buffers[index].text = payload.0
            buffers[index].language = payload.1
            buffers[index].updatedAt = Date()
            buffers[index].selectionRanges = [.zero]
        case .failure(let error):
            let wasSelected = selectedBufferID == bufferID
            buffers.remove(at: index)
            if wasSelected {
                if buffers.isEmpty {
                    let buffer = EditorBuffer.scratch(index: 1)
                    buffers.append(buffer)
                    selectedBufferID = buffer.id
                } else {
                    selectedBufferID = buffers[min(index, buffers.count - 1)].id
                }
            }
            lastError = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }

        persistSoon()
    }

    func pairNetworkPeer(_ deviceID: String) {
        networkShare.pair(with: deviceID)
    }

    func sendSelectedBuffer(to deviceID: String) {
        guard let selectedBuffer else {
            return
        }

        let note = SharedNotePayload(
            id: UUID(),
            title: selectedBuffer.displayTitle,
            text: selectedBuffer.text,
            language: selectedBuffer.language,
            sentAt: Date(),
            sourceDeviceID: networkShare.localDeviceID,
            sourceDeviceName: networkShare.localDisplayName,
            sourceToken: nil
        )
        networkShare.send(note: note, to: deviceID)
    }

    func removeTrustedNetworkDevice(_ deviceID: String) {
        networkShare.removeTrustedDevice(deviceID)
    }

    func importSharedNote(_ note: SharedNotePayload) {
        let now = Date()
        let baseTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Shared Note"
            : note.title
        let buffer = EditorBuffer(
            id: UUID(),
            title: uniqueSharedTitle(baseTitle),
            kind: .scratch,
            filePath: nil,
            text: note.text,
            language: note.language,
            createdAt: now,
            updatedAt: now,
            isDirty: !note.text.isEmpty,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil
        )

        buffers.append(buffer)
        selectedBufferID = buffer.id
        persistSoon()
    }

    private func uniqueSharedTitle(_ title: String) -> String {
        guard buffers.contains(where: { $0.title == title }) else {
            return title
        }

        var index = 2
        while buffers.contains(where: { $0.title == "\(title) \(index)" }) {
            index += 1
        }

        return "\(title) \(index)"
    }

    func saveSelected() {
        guard let selectedIndex else { return }

        if buffers[selectedIndex].kind == .scratch || buffers[selectedIndex].filePath == nil {
            saveSelectedAs()
            return
        }

        guard let path = buffers[selectedIndex].filePath else { return }
        saveBuffer(at: selectedIndex, to: URL(fileURLWithPath: path))
    }

    func saveSelectedAs() {
        guard let selectedIndex else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = buffers[selectedIndex].displayTitle

        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveBuffer(at: selectedIndex, to: url)
    }

    func persistNow() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil

        if let onPersistRequested {
            onPersistRequested()
            return
        }

        guard let persistence else { return }

        do {
            try persistence.save(buffers: buffers, selectedID: selectedBufferID)
        } catch {
            lastError = "Could not persist session: \(error.localizedDescription)"
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

    func showFind() {
        findPanelMode = .find
    }

    func showReplace() {
        findPanelMode = .replace
    }

    func showGlobalFind() {
        findPanelMode = .global
    }

    func hideFindPanel() {
        findPanelMode = .hidden
    }

    func escape() {
        if findPanelMode != .hidden {
            hideFindPanel()
        } else {
            clearAdditionalCursors()
        }
    }

    func increaseFontSize() {
        fontSize = min(32, fontSize + 1)
    }

    func decreaseFontSize() {
        fontSize = max(10, fontSize - 1)
    }

    func toggleWrapLines() {
        wrapsLines.toggle()
    }

    func toggleMarkdownPreview() {
        if isPreviewVisible {
            showSourceMode()
        } else {
            showMarkdownPreviewMode()
        }
    }

    func toggleMarkdownOutline() {
        isOutlineVisible.toggle()
    }

    func toggleFocusMode() {
        if isWysiwygModeEnabled {
            isWysiwygModeEnabled = false
        }
        isFocusModeEnabled.toggle()
    }

    func toggleTypewriterMode() {
        isTypewriterModeEnabled.toggle()
    }

    func toggleMiniMap() {
        if isWysiwygModeEnabled {
            isWysiwygModeEnabled = false
        }
        isMiniMapVisible.toggle()
    }

    func toggleWysiwygMode() {
        if isWysiwygModeEnabled {
            showSourceMode()
        } else {
            showMarkdownWysiwygMode()
        }
    }

    func showSourceMode() {
        isPreviewVisible = false
        isWysiwygModeEnabled = false
    }

    func showMarkdownPreviewMode() {
        isPreviewVisible = true
        isWysiwygModeEnabled = false
    }

    func showMarkdownWysiwygMode() {
        isPreviewVisible = false
        isWysiwygModeEnabled = true
        isMiniMapVisible = false
        isFocusModeEnabled = false
    }

    private func normalizeLoadedEditorModeState() {
        guard isWysiwygModeEnabled else { return }

        isPreviewVisible = false
        if isMiniMapVisible {
            isMiniMapVisible = false
            UserDefaults.standard.set(false, forKey: Self.miniMapDefaultsKey)
        }
        if isFocusModeEnabled {
            isFocusModeEnabled = false
            UserDefaults.standard.set(false, forKey: Self.focusModeDefaultsKey)
        }
    }

    func showCommandPalette() {
        findPanelMode = .hidden
        isCommandPaletteVisible = true
    }

    func hideCommandPalette() {
        isCommandPaletteVisible = false
    }

    func toggleCommandPalette() {
        if isCommandPaletteVisible {
            hideCommandPalette()
        } else {
            showCommandPalette()
        }
    }

    func jumpToHeading(_ heading: MarkdownHeading) {
        guard let selectedIndex else { return }

        buffers[selectedIndex].selectionRanges = [TextRange(location: heading.location, length: 0)]
        persistSoon()
    }

    func jumpToLine(_ lineNumber: Int) {
        guard let selectedIndex else { return }

        let lineNumber = max(1, lineNumber)
        let nsText = buffers[selectedIndex].text as NSString
        var currentLine = 1
        var location = 0

        while location < nsText.length, currentLine < lineNumber {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let nextLocation = lineRange.location + max(lineRange.length, 1)
            guard nextLocation > location else { break }
            location = nextLocation
            currentLine += 1
        }

        buffers[selectedIndex].selectionRanges = [TextRange(location: min(location, nsText.length), length: 0)]
        persistSoon()
    }

    func findNext() {
        if findQuery.isEmpty {
            showFind()
            return
        }

        find(direction: .next)
    }

    func findPrevious() {
        if findQuery.isEmpty {
            showFind()
            return
        }

        find(direction: .previous)
    }

    func replaceCurrent() {
        guard let selectedIndex,
              !findQuery.isEmpty else {
            return
        }

        let buffer = buffers[selectedIndex]
        guard let selected = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text).first else {
            findNext()
            return
        }

        guard let match = firstMatch(in: buffer.text, range: selected.nsRange),
              match.range.location == selected.location,
              match.range.length == selected.length else {
            findNext()
            return
        }

        let replacement = replacementString(for: match, in: buffer.text)
        replaceRanges([selected]) { _ in replacement }
    }

    func replaceAll() {
        guard let selectedIndex,
              !findQuery.isEmpty else {
            return
        }

        let buffer = buffers[selectedIndex]
        guard let replacement = replacingAllMatches(in: buffer.text) else { return }

        buffers[selectedIndex].text = replacement.text
        buffers[selectedIndex].isDirty = true
        buffers[selectedIndex].updatedAt = Date()
        buffers[selectedIndex].selectionRanges = [replacement.firstSelection]
        persistSoon()
    }

    @discardableResult
    func replaceAllGlobalMatches() -> Int {
        guard !findQuery.isEmpty else {
            showGlobalFind()
            return 0
        }

        if let findValidationError {
            globalReplaceStatusText = findValidationError
            return 0
        }

        var replacementCount = 0
        var changedDocumentCount = 0
        var firstOpenChange: (index: Int, selection: TextRange)?
        var openFileIdentities = Set<String>()

        for index in buffers.indices {
            if let path = buffers[index].filePath {
                openFileIdentities.insert(fileIdentity(forPath: path))
            }

            guard let replacement = replacingAllMatches(in: buffers[index].text) else {
                continue
            }

            buffers[index].text = replacement.text
            buffers[index].isDirty = true
            buffers[index].updatedAt = Date()
            buffers[index].selectionRanges = [replacement.firstSelection]
            replacementCount += replacement.count
            changedDocumentCount += 1

            if firstOpenChange == nil {
                firstOpenChange = (index, replacement.firstSelection)
            }
        }

        var failedNames: [String] = []

        for node in documentCatalogFileNodes(documentCatalogNodes) {
            let identity = fileIdentity(forURL: node.url)
            guard !openFileIdentities.contains(identity) else { continue }

            do {
                var encoding = String.Encoding.utf8
                let text = try String(contentsOf: node.url, usedEncoding: &encoding)
                guard let replacement = replacingAllMatches(in: text) else {
                    continue
                }

                try replacement.text.write(to: node.url, atomically: true, encoding: encoding)
                replacementCount += replacement.count
                changedDocumentCount += 1
            } catch {
                failedNames.append(node.name)
            }
        }

        if let firstOpenChange {
            selectedBufferID = buffers[firstOpenChange.index].id
            buffers[firstOpenChange.index].selectionRanges = [firstOpenChange.selection]
        }

        if replacementCount > 0 {
            persistSoon()
        }

        globalReplaceStatusText = replacementCount == 0
            ? "No replacements"
            : "Replaced \(replacementCount) \(replacementCount == 1 ? "match" : "matches") in \(changedDocumentCount) \(changedDocumentCount == 1 ? "document" : "documents")"

        if !failedNames.isEmpty {
            lastError = "Could not replace in \(failedNames.prefix(3).joined(separator: ", "))"
        }

        return replacementCount
    }

    func addNextOccurrence() {
        addOccurrence(direction: .next)
    }

    func addPreviousOccurrence() {
        addOccurrence(direction: .previous)
    }

    private func addOccurrence(direction: FindDirection) {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let selections = normalizedRanges(buffer.selectionRanges, in: buffer.text)
        let primarySelection = selections.first(where: { $0.length > 0 })

        let query: String
        if let primarySelection {
            query = nsText.substring(with: primarySelection.nsRange)
        } else if !findQuery.isEmpty {
            query = findQuery
        } else if let word = wordRange(at: selections.first?.location ?? 0, in: nsText) {
            buffers[selectedIndex].selectionRanges = [word]
            persistSoon()
            return
        } else {
            return
        }

        guard !query.isEmpty else { return }

        let start: Int
        switch direction {
        case .next:
            start = selections.map { $0.location + $0.length }.max() ?? 0
        case .previous:
            start = selections.map(\.location).min() ?? 0
        }

        if let occurrence = findRange(query: query, in: buffer.text, from: start, direction: direction, forceLiteral: true),
           !selections.contains(occurrence) {
            let updated = (selections + [occurrence]).sorted { first, second in
                first.location == second.location ? first.length < second.length : first.location < second.location
            }
            buffers[selectedIndex].selectionRanges = updated
            persistSoon()
        }
    }

    private func wordRange(at location: Int, in nsText: NSString) -> TextRange? {
        guard nsText.length > 0 else { return nil }

        let characterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        func isWordCharacter(_ index: Int) -> Bool {
            guard index >= 0, index < nsText.length,
                  let scalar = UnicodeScalar(nsText.character(at: index)) else {
                return false
            }
            return characterSet.contains(scalar)
        }

        var index = min(max(0, location), nsText.length - 1)
        if !isWordCharacter(index) {
            if location > 0, isWordCharacter(location - 1) {
                index = location - 1
            } else {
                return nil
            }
        }

        var start = index
        while start > 0, isWordCharacter(start - 1) {
            start -= 1
        }

        var end = index + 1
        while end < nsText.length, isWordCharacter(end) {
            end += 1
        }

        guard end > start else { return nil }
        return TextRange(location: start, length: end - start)
    }

    func clearAdditionalCursors() {
        guard let selectedIndex else { return }
        let first = buffers[selectedIndex].selectionRanges.first ?? .zero
        buffers[selectedIndex].selectionRanges = [first]
        persistSoon()
    }

    func selectSearchResult(_ result: SearchResult) {
        if let bufferID = result.bufferID {
            selectedBufferID = bufferID

            if let index = buffers.firstIndex(where: { $0.id == bufferID }) {
                buffers[index].selectionRanges = [result.range]
                persistSoon()
            }
            return
        }

        guard let filePath = result.filePath else { return }
        if let index = buffers.firstIndex(where: { $0.filePath == filePath }) {
            selectedBufferID = buffers[index].id
            buffers[index].selectionRanges = [result.range]
            persistSoon()
            return
        }

        do {
            let url = URL(fileURLWithPath: filePath)
            var encoding = String.Encoding.utf8
            let text = try String(contentsOf: url, usedEncoding: &encoding)
            let now = Date()
            let buffer = EditorBuffer(
                id: UUID(),
                title: url.lastPathComponent,
                kind: .file,
                filePath: filePath,
                text: text,
                language: EditorLanguage.detect(fileName: url.lastPathComponent, text: text),
                createdAt: now,
                updatedAt: now,
                isDirty: false,
                selectionRanges: [result.range]
            )
            buffers.append(buffer)
            selectedBufferID = buffer.id
            persistSoon()
        } catch {
            lastError = "Could not open \(URL(fileURLWithPath: filePath).lastPathComponent): \(error.localizedDescription)"
        }
    }

    func selectAllMatches() {
        guard let selectedIndex,
              !findQuery.isEmpty else {
            showFind()
            return
        }

        let ranges = allMatches(in: buffers[selectedIndex].text).map { TextRange($0.range) }
        guard !ranges.isEmpty else { return }
        buffers[selectedIndex].selectionRanges = ranges
        persistSoon()
    }

    func performTextTransform(_ transform: TextTransform) {
        if editorCommandHandler?(.transform(transform)) == true {
            return
        }

        transformSelection(transform)
    }

    func performEditorCommand(_ command: EditorCommand) {
        _ = editorCommandHandler?(command)
    }

    func performMarkdownCommand(_ command: MarkdownCommand) {
        _ = editorCommandHandler?(.markdown(command))
    }

    func transformSelection(_ transform: TextTransform) {
        switch transform {
        case .uppercase:
            replaceTargetText { $0.uppercased() }
        case .lowercase:
            replaceTargetText { $0.lowercased() }
        case .titlecase:
            replaceTargetText { $0.capitalized }
        case .swapCase:
            replaceTargetText { $0.swappingCase() }
        case .reverseSelection:
            replaceTargetText { String($0.reversed()) }
        case .sortLines:
            replaceTargetLines { text in
                preserveTrailingNewline(text) { lines in
                    lines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                }
            }
        case .uniqueLines:
            replaceTargetLines { text in
                preserveTrailingNewline(text) { lines in
                    var seen = Set<String>()
                    return lines.filter { seen.insert($0).inserted }
                }
            }
        case .trimTrailingWhitespace:
            replaceTargetLines { text in
                text.components(separatedBy: .newlines)
                    .map { $0.trimmingTrailingWhitespace() }
                    .joined(separator: "\n")
            }
        case .duplicateLine:
            duplicateSelectedLinesOrCurrentLine()
        case .joinLines:
            replaceTargetLines { text in
                text.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
        }
    }

    private func runAIPrompt(bufferID: UUID, chatID: UUID, userText: String) async {
        do {
            guard let buffer = buffers.first(where: { $0.id == bufferID }),
                  let chatLocation = aiChatLocation(chatID) else {
                finishAIChat(chatID, status: "Chat is no longer available.")
                return
            }

            try aiFileBridge.mirror(buffer)

            let hadClient = aiClients[chatID] != nil
            let client = configuredAIClient(for: buffers[chatLocation.bufferIndex].aiSessions[chatLocation.sessionIndex], buffer: buffer)
            let agentSessionID: String

            if let existingAgentSessionID = buffers[chatLocation.bufferIndex].aiSessions[chatLocation.sessionIndex].agentSessionID,
               hadClient {
                agentSessionID = existingAgentSessionID
            } else {
                aiChatIDsByAgentSession = aiChatIDsByAgentSession.filter { $0.value != chatID }
                agentSessionID = try await client.newSession(cwd: aiWorkingDirectory(for: buffer).path)
                if let updatedLocation = aiChatLocation(chatID) {
                    buffers[updatedLocation.bufferIndex].aiSessions[updatedLocation.sessionIndex].agentSessionID = agentSessionID
                    buffers[updatedLocation.bufferIndex].aiSessions[updatedLocation.sessionIndex].updatedAt = Date()
                    persistSoon()
                }
                aiChatIDsByAgentSession[agentSessionID] = chatID
            }

            let editableURL = aiFileBridge.editableURL(for: buffer)
            let prompt = aiPromptBlocks(userText: userText, buffer: buffer, editableURL: editableURL, client: client)
            let stopReason = try await client.prompt(sessionID: agentSessionID, prompt: prompt)
            let didApplyEdits = applyAIMirroredFileIfNeeded(bufferID: bufferID, chatID: chatID)
            aiStreamingMessageIDs.removeValue(forKey: chatID)
            let status = didApplyEdits
                ? "Applied edits to the current tab"
                : (stopReason == "end_turn" ? "Done" : "Stopped: \(stopReason)")
            finishAIChat(chatID, status: status)
        } catch {
            appendAISystemMessage("AI error: \(error.localizedDescription)", to: chatID)
            finishAIChat(chatID, status: "Failed")
        }
    }

    private func configuredAIClient(for session: AIChatSession, buffer: EditorBuffer) -> ACPAgentClient {
        if let client = aiClients[session.id] {
            return client
        }

        let executable = configuredExecutable(for: session.provider)
        let arguments = ShellArguments.split(configuredArguments(for: session.provider))
        let client = ACPAgentClient(
            provider: session.provider,
            executable: executable,
            arguments: arguments,
            workingDirectory: aiWorkingDirectory(for: buffer)
        )

        client.onAssistantText = { [weak self] agentSessionID, text in
            Task { @MainActor in
                self?.appendAIAssistantText(text, agentSessionID: agentSessionID)
            }
        }

        client.onStatus = { [weak self] agentSessionID, status in
            Task { @MainActor in
                self?.updateAIStatus(status, agentSessionID: agentSessionID, fallbackChatID: session.id)
            }
        }

        client.onReadTextFile = { [weak self] path, line, limit in
            await MainActor.run {
                self?.readAITextFile(path: path, line: line, limit: limit)
            }
        }

        client.onWriteTextFile = { [weak self] path, content in
            await MainActor.run {
                self?.writeAITextFile(path: path, content: content) ?? false
            }
        }

        aiClients[session.id] = client
        return client
    }

    private func aiPromptBlocks(userText: String, buffer: EditorBuffer, editableURL: URL, client: ACPAgentClient) -> [ACPJSON] {
        let path = editableURL.path
        let originalPath = buffer.filePath ?? "Scratch buffer, not saved to disk"
        let instruction = """
        You are assisting inside SimpleLime, a macOS text editor.
        The current open buffer has been mirrored into a temporary editable file.
        Editable buffer path: \(path)
        Original document path: \(originalPath)
        Language: \(buffer.language.displayName)

        To change the editor text, rewrite the full corrected content into the editable buffer path above. You may use fs/write_text_file if available. If your environment exposes shell/file tools instead, modify only that editable buffer file. Do not edit the original document path directly and do not edit unrelated files.
        If the user asks to check grammar, punctuation, wording, or rewrite text, apply the corrected version to the editable buffer file instead of only describing the fixes.

        User task:
        \(userText)
        """

        var blocks: [ACPJSON] = [
            [
                "type": "text",
                "text": instruction
            ]
        ]

        if client.supportsEmbeddedContext {
            blocks.append([
                "type": "resource",
                "resource": [
                    "uri": editableURL.absoluteString,
                    "mimeType": aiFileBridge.mimeType(for: buffer),
                    "text": buffer.text
                ]
            ])
        } else {
            blocks.append([
                "type": "resource_link",
                "uri": editableURL.absoluteString,
                "name": buffer.displayTitle,
                "title": buffer.displayTitle,
                "mimeType": aiFileBridge.mimeType(for: buffer),
                "size": buffer.text.utf8.count
            ])
        }

        return blocks
    }

    private func appendAIAssistantText(_ text: String, agentSessionID: String) {
        guard !text.isEmpty,
              let chatID = aiChatIDsByAgentSession[agentSessionID],
              let location = aiChatLocation(chatID) else {
            return
        }

        if let messageID = aiStreamingMessageIDs[chatID],
           let messageIndex = buffers[location.bufferIndex].aiSessions[location.sessionIndex].messages.firstIndex(where: { $0.id == messageID }) {
            buffers[location.bufferIndex].aiSessions[location.sessionIndex].messages[messageIndex].text += text
        } else {
            let message = AIChatMessage.assistant(text)
            buffers[location.bufferIndex].aiSessions[location.sessionIndex].messages.append(message)
            aiStreamingMessageIDs[chatID] = message.id
        }

        buffers[location.bufferIndex].aiSessions[location.sessionIndex].updatedAt = Date()
        persistSoon()
    }

    private func appendAISystemMessage(_ text: String, to chatID: UUID) {
        guard let location = aiChatLocation(chatID) else { return }
        buffers[location.bufferIndex].aiSessions[location.sessionIndex].messages.append(.system(text))
        buffers[location.bufferIndex].aiSessions[location.sessionIndex].updatedAt = Date()
        persistSoon()
    }

    private func updateAIStatus(_ status: String, agentSessionID: String, fallbackChatID: UUID) {
        let chatID = aiChatIDsByAgentSession[agentSessionID] ?? fallbackChatID
        guard aiChatLocation(chatID) != nil else { return }
        aiSessionStatuses[chatID] = status
    }

    private func finishAIChat(_ chatID: UUID, status: String) {
        aiRunningSessions.remove(chatID)
        aiSessionStatuses[chatID] = status
        persistSoon()
    }

    private func readAITextFile(path: String, line: Int?, limit: Int?) -> String? {
        guard let index = bufferIndexForAIPath(path) else { return nil }
        return slicedText(buffers[index].text, line: line, limit: limit)
    }

    private func writeAITextFile(path: String, content: String) -> Bool {
        guard let index = bufferIndexForAIPath(path) else { return false }

        buffers[index].text = content
        buffers[index].updatedAt = Date()
        buffers[index].isDirty = buffers[index].kind == .scratch ? !content.isEmpty : true

        try? aiFileBridge.mirror(buffers[index])

        persistSoon()
        return true
    }

    @discardableResult
    private func applyAIMirroredFileIfNeeded(bufferID: UUID, chatID: UUID) -> Bool {
        guard let index = buffers.firstIndex(where: { $0.id == bufferID }),
              let mirroredText = aiFileBridge.readMirroredText(for: buffers[index]),
              mirroredText != buffers[index].text else {
            return false
        }

        buffers[index].text = mirroredText
        buffers[index].updatedAt = Date()
        buffers[index].isDirty = buffers[index].kind == .scratch ? !mirroredText.isEmpty : true
        aiSessionStatuses[chatID] = "Applied edits to the current tab"
        persistSoon()
        return true
    }

    private func bufferIndexForAIPath(_ path: String) -> Int? {
        let normalizedPath = normalizedPath(path)

        for index in buffers.indices {
            if aiFileBridge.editableURL(for: buffers[index]).path == normalizedPath {
                return index
            }

            if let filePath = buffers[index].filePath,
               URL(fileURLWithPath: filePath, isDirectory: false).standardizedFileURL.path == normalizedPath {
                return index
            }
        }

        return nil
    }

    private func normalizedPath(_ path: String) -> String {
        if path.hasPrefix("file://"),
           let url = URL(string: path) {
            return url.standardizedFileURL.path
        }

        return URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL.path
    }

    private static func isDirectoryURL(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func slicedText(_ text: String, line: Int?, limit: Int?) -> String {
        guard line != nil || limit != nil else {
            return text
        }

        let lines = text.components(separatedBy: "\n")
        let start = min(max(0, (line ?? 1) - 1), lines.count)
        guard start < lines.count else { return "" }

        if let limit {
            let end = min(lines.count, start + max(0, limit))
            return lines[start..<end].joined(separator: "\n")
        }

        return lines[start...].joined(separator: "\n")
    }

    private func aiWorkingDirectory(for buffer: EditorBuffer) -> URL {
        return aiFileBridge.editableURL(for: buffer)
            .deletingLastPathComponent()
            .standardizedFileURL
    }

    private func configuredExecutable(for provider: AIAgentProvider) -> String {
        let configured = UserDefaults.standard.string(forKey: provider.settingsExecutableKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        return provider.defaultExecutable
    }

    private func configuredArguments(for provider: AIAgentProvider) -> String {
        let configured = UserDefaults.standard.string(forKey: provider.settingsArgumentsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        return provider.defaultArguments
    }

    private func aiChatLocation(_ chatID: UUID) -> (bufferIndex: Int, sessionIndex: Int)? {
        for bufferIndex in buffers.indices {
            if let sessionIndex = buffers[bufferIndex].aiSessions.firstIndex(where: { $0.id == chatID }) {
                return (bufferIndex, sessionIndex)
            }
        }

        return nil
    }

    private func stopAIClients(for buffer: EditorBuffer) {
        for session in buffer.aiSessions {
            aiClients.removeValue(forKey: session.id)?.stop()
            aiRunningSessions.remove(session.id)
            aiSessionStatuses.removeValue(forKey: session.id)
            aiStreamingMessageIDs.removeValue(forKey: session.id)
            aiChatIDsByAgentSession = aiChatIDsByAgentSession.filter { $0.value != session.id }
        }
    }

    private func saveBuffer(at index: Int, to url: URL) {
        do {
            try buffers[index].text.write(to: url, atomically: true, encoding: .utf8)
            buffers[index].kind = .file
            buffers[index].filePath = url.path
            buffers[index].title = url.lastPathComponent
            buffers[index].language = EditorLanguage.detect(fileName: url.lastPathComponent, text: buffers[index].text)
            buffers[index].updatedAt = Date()
            buffers[index].isDirty = false
            persistSoon()
        } catch {
            lastError = "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private nonisolated static func buildDocumentCatalogNodes(rootURL: URL) -> [DocumentCatalogNode] {
        var remainingItems = 3000
        return documentCatalogChildren(in: rootURL, remainingItems: &remainingItems)
    }

    private nonisolated static func documentCatalogChildren(in directoryURL: URL, remainingItems: inout Int) -> [DocumentCatalogNode] {
        guard remainingItems > 0,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var nodes: [DocumentCatalogNode] = []

        for url in urls where remainingItems > 0 {
            let name = url.lastPathComponent
            guard !name.hasPrefix(".") else { continue }

            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if resourceValues?.isDirectory == true {
                guard shouldIncludeDocumentCatalogDirectory(name) else { continue }

                var childRemaining = remainingItems - 1
                let children = documentCatalogChildren(in: url, remainingItems: &childRemaining)
                remainingItems = childRemaining

                if !children.isEmpty {
                    nodes.append(DocumentCatalogNode(url: url, isDirectory: true, children: children))
                    remainingItems -= 1
                }
            } else if resourceValues?.isRegularFile == true, shouldIncludeDocumentCatalogFile(url) {
                nodes.append(DocumentCatalogNode(url: url, isDirectory: false))
                remainingItems -= 1
            }
        }

        return nodes.sorted { first, second in
            if first.isDirectory != second.isDirectory {
                return first.isDirectory && !second.isDirectory
            }

            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }

    private nonisolated static func shouldIncludeDocumentCatalogDirectory(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        let excluded = [
            ".build",
            "build",
            "deriveddata",
            "dist",
            "node_modules",
            "packages",
            "vendor"
        ]

        return !excluded.contains(lowercased)
    }

    private nonisolated static func shouldIncludeDocumentCatalogFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        let allowedExtensions: Set<String> = [
            "bash",
            "c",
            "cc",
            "conf",
            "cpp",
            "css",
            "csv",
            "env",
            "fish",
            "go",
            "h",
            "hpp",
            "htm",
            "html",
            "ini",
            "js",
            "json",
            "jsonl",
            "log",
            "markdown",
            "md",
            "mdown",
            "mjs",
            "plist",
            "py",
            "rb",
            "rs",
            "sass",
            "scss",
            "sh",
            "swift",
            "text",
            "toml",
            "ts",
            "tsx",
            "txt",
            "xml",
            "yaml",
            "yml",
            "zsh"
        ]

        if allowedExtensions.contains(ext) {
            return true
        }

        return [
            "changelog",
            "dockerfile",
            "gemfile",
            "license",
            "makefile",
            "rakefile",
            "readme"
        ].contains(name)
    }

    private func searchAllSources(query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        var results = searchAllTabs(query: query, limit: 500)
        guard results.count < 500 else { return results }

        let openFilePaths = Set(buffers.compactMap(\.filePath))
        for node in documentCatalogFileNodes(documentCatalogNodes) where results.count < 500 {
            let path = node.url.path
            guard !openFilePaths.contains(path),
                  let text = try? String(contentsOf: node.url) else {
                continue
            }

            results.append(
                contentsOf: searchResults(
                    in: text,
                    title: documentCatalogDisplayPath(for: node.url),
                    bufferID: nil,
                    filePath: path,
                    limit: 500 - results.count
                )
            )
        }

        return results
    }

    private func searchAllTabs(query: String, limit: Int) -> [SearchResult] {
        guard !query.isEmpty, limit > 0 else { return [] }

        var results: [SearchResult] = []

        for buffer in buffers {
            results.append(
                contentsOf: searchResults(
                    in: buffer.text,
                    title: buffer.displayTitle,
                    bufferID: buffer.id,
                    filePath: buffer.filePath,
                    limit: limit - results.count
                )
            )
            if results.count >= limit { break }
        }

        return results
    }

    private func searchResults(
        in text: String,
        title: String,
        bufferID: UUID?,
        filePath: String?,
        limit: Int
    ) -> [SearchResult] {
        guard limit > 0 else { return [] }

        let nsText = text as NSString
        return allMatches(in: text)
            .prefix(limit)
            .map { match in
                let lineRange = nsText.lineRange(for: match.range)
                let excerpt = nsText.substring(with: lineRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                return SearchResult(
                    bufferID: bufferID,
                    filePath: filePath,
                    bufferTitle: title,
                    lineNumber: lineNumber(at: match.range.location, in: text),
                    excerpt: excerpt.isEmpty ? " " : excerpt,
                    range: TextRange(match.range)
                )
            }
    }

    private func documentCatalogFileNodes(_ nodes: [DocumentCatalogNode]) -> [DocumentCatalogNode] {
        nodes.flatMap { node -> [DocumentCatalogNode] in
            node.isDirectory ? documentCatalogFileNodes(node.children) : [node]
        }
    }

    private func documentCatalogDisplayPath(for url: URL) -> String {
        guard let rootPath = documentCatalogRootPath else {
            return url.lastPathComponent
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let fileURL = url.standardizedFileURL
        let root = rootURL.path
        let path = fileURL.path
        if path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }

        return url.lastPathComponent
    }

    private nonisolated static func fuzzyScore(candidate: String, query: String) -> Int? {
        let candidate = Array(candidate.lowercased())
        let query = Array(query.lowercased())
        guard !query.isEmpty else { return 0 }

        var candidateIndex = 0
        var score = 0
        var previousMatchIndex: Int?

        for queryCharacter in query {
            var foundIndex: Int?
            while candidateIndex < candidate.count {
                if candidate[candidateIndex] == queryCharacter {
                    foundIndex = candidateIndex
                    break
                }
                candidateIndex += 1
            }

            guard let matchIndex = foundIndex else { return nil }

            score += 10
            if let previousMatchIndex, matchIndex == previousMatchIndex + 1 {
                score += 14
            }
            if matchIndex == 0 || Self.isFuzzyWordBoundary(candidate[matchIndex - 1]) {
                score += 10
            }

            previousMatchIndex = matchIndex
            candidateIndex = matchIndex + 1
        }

        if String(candidate).contains(String(query)) {
            score += 30
        }

        return score - candidate.count / 20
    }

    private nonisolated static func isFuzzyWordBoundary(_ character: Character) -> Bool {
        character == "/" || character == "-" || character == "_" || character == "." || character == " "
    }

    private func fileIdentity(forURL url: URL) -> String {
        fileIdentity(forPath: url.path)
    }

    private func fileIdentity(forPath path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private struct FindMatch {
        let range: NSRange
        let regexResult: NSTextCheckingResult?
    }

    private struct ReplacementResult {
        let text: String
        let count: Int
        let firstSelection: TextRange
    }

    private func makeFindRegex() throws -> NSRegularExpression {
        let options: NSRegularExpression.Options = findMatchesCase ? [] : [.caseInsensitive]
        return try NSRegularExpression(pattern: findQuery, options: options)
    }

    private func replacingAllMatches(in text: String) -> ReplacementResult? {
        let matches = allMatches(in: text)
        guard !matches.isEmpty else { return nil }

        let replacements = matches.map { replacementString(for: $0, in: text) }
        let mutable = NSMutableString(string: text)

        for (match, replacement) in zip(matches, replacements).reversed() {
            mutable.replaceCharacters(in: match.range, with: replacement)
        }

        return ReplacementResult(
            text: mutable as String,
            count: matches.count,
            firstSelection: TextRange(location: matches[0].range.location, length: replacements[0].utf16.count)
        )
    }

    private func allMatches(in text: String) -> [FindMatch] {
        guard !findQuery.isEmpty else { return [] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if findUsesRegex {
            guard let regex = try? makeFindRegex() else {
                return []
            }

            return regex.matches(in: text, range: fullRange)
                .filter { $0.range.location != NSNotFound && $0.range.length > 0 }
                .filter { !findWholeWord || isWholeWordMatch($0.range, in: nsText) }
                .map { FindMatch(range: $0.range, regexResult: $0) }
        }

        var matches: [FindMatch] = []
        var searchLocation = 0
        let options: NSString.CompareOptions = findMatchesCase ? [] : [.caseInsensitive]

        while searchLocation < nsText.length {
            let searchRange = NSRange(location: searchLocation, length: nsText.length - searchLocation)
            let found = nsText.range(of: findQuery, options: options, range: searchRange)
            if found.location == NSNotFound { break }
            if !findWholeWord || isWholeWordMatch(found, in: nsText) {
                matches.append(FindMatch(range: found, regexResult: nil))
            }
            searchLocation = found.location + max(found.length, 1)
        }

        return matches
    }

    private func isWholeWordMatch(_ range: NSRange, in nsText: NSString) -> Bool {
        let beforeIndex = range.location - 1
        let afterIndex = range.location + range.length
        let beforeIsWord = beforeIndex >= 0 && isFindWordCharacter(nsText.character(at: beforeIndex))
        let afterIsWord = afterIndex < nsText.length && isFindWordCharacter(nsText.character(at: afterIndex))
        return !beforeIsWord && !afterIsWord
    }

    private func isFindWordCharacter(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(value) else { return false }
        return CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains(scalar)
    }

    private func firstMatch(in text: String, range: NSRange) -> FindMatch? {
        allMatches(in: text).first { NSEqualRanges($0.range, range) }
    }

    private func replacementString(for match: FindMatch, in text: String) -> String {
        guard findUsesRegex,
              let regexResult = match.regexResult,
              let regex = try? makeFindRegex() else {
            return replaceText
        }

        return regex.replacementString(for: regexResult, in: text, offset: 0, template: replaceText)
    }

    private func lineNumber(at location: Int, in text: String) -> Int {
        let nsText = text as NSString
        let location = min(max(0, location), nsText.length)
        guard location > 0 else { return 1 }

        let prefix = nsText.substring(to: location)
        return prefix.reduce(1) { count, character in
            character == "\n" ? count + 1 : count
        }
    }

    private enum FindDirection {
        case next
        case previous
    }

    private func find(direction: FindDirection) {
        guard let selectedIndex,
              !findQuery.isEmpty else {
            return
        }

        let buffer = buffers[selectedIndex]
        let selected = normalizedRanges(buffer.selectionRanges, in: buffer.text).first ?? .zero
        let start: Int

        switch direction {
        case .next:
            start = selected.location + selected.length
        case .previous:
            start = selected.location
        }

        guard let found = findRange(query: findQuery, in: buffer.text, from: start, direction: direction) else {
            return
        }

        buffers[selectedIndex].selectionRanges = [found]
        persistSoon()
    }

    private func findRange(
        query: String,
        in text: String,
        from rawStart: Int,
        direction: FindDirection,
        forceLiteral: Bool = false
    ) -> TextRange? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let start = min(max(0, rawStart), nsText.length)

        if findUsesRegex, !forceLiteral, query == findQuery {
            let matches = allMatches(in: text)
            guard !matches.isEmpty else { return nil }

            switch direction {
            case .next:
                return TextRange(matches.first { $0.range.location >= start }?.range ?? matches[0].range)
            case .previous:
                return TextRange(matches.last { $0.range.location < start }?.range ?? matches[matches.count - 1].range)
            }
        }

        var options: NSString.CompareOptions = findMatchesCase ? [] : [.caseInsensitive]
        if direction == .previous {
            options.insert(.backwards)
        }

        switch direction {
        case .next:
            let firstRange = NSRange(location: start, length: nsText.length - start)
            let found = nsText.range(of: query, options: options, range: firstRange)
            if found.location != NSNotFound {
                return TextRange(found)
            }

            let wrapRange = NSRange(location: 0, length: start)
            let wrapped = nsText.range(of: query, options: options, range: wrapRange)
            return wrapped.location == NSNotFound ? nil : TextRange(wrapped)

        case .previous:
            let firstRange = NSRange(location: 0, length: start)
            let found = nsText.range(of: query, options: options, range: firstRange)
            if found.location != NSNotFound {
                return TextRange(found)
            }

            let wrapRange = NSRange(location: start, length: nsText.length - start)
            let wrapped = nsText.range(of: query, options: options, range: wrapRange)
            return wrapped.location == NSNotFound ? nil : TextRange(wrapped)
        }
    }

    private func replaceTargetText(_ transform: (String) -> String) {
        guard let selectedIndex else { return }
        let buffer = buffers[selectedIndex]
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        let targetRanges = ranges.isEmpty ? [TextRange(location: 0, length: (buffer.text as NSString).length)] : ranges
        replaceRanges(targetRanges, transform: transform)
    }

    private func replaceTargetLines(_ transform: (String) -> String) {
        guard let selectedIndex else { return }
        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        let targetRanges = ranges.isEmpty ? [TextRange(location: 0, length: nsText.length)] : mergedLineRanges(for: ranges, in: buffer.text)
        replaceRanges(targetRanges, transform: transform)
    }

    private func replaceRanges(_ ranges: [TextRange], transform: (String) -> String) {
        guard let selectedIndex else { return }
        let text = buffers[selectedIndex].text
        let nsText = text as NSString
        let mutable = NSMutableString(string: text)
        let ranges = normalizedRanges(ranges, in: text).sorted { $0.location > $1.location }
        var newSelections: [TextRange] = []

        for range in ranges {
            let original = nsText.substring(with: range.nsRange)
            let replacement = transform(original)
            mutable.replaceCharacters(in: range.nsRange, with: replacement)
            newSelections.append(TextRange(location: range.location, length: replacement.utf16.count))
        }

        buffers[selectedIndex].text = mutable as String
        buffers[selectedIndex].selectionRanges = newSelections.reversed()
        buffers[selectedIndex].isDirty = true
        buffers[selectedIndex].updatedAt = Date()
        persistSoon()
    }

    private func duplicateSelectedLinesOrCurrentLine() {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)

        if !ranges.isEmpty {
            replaceRanges(ranges) { "\($0)\($0)" }
            return
        }

        let cursor = normalizedRanges(buffer.selectionRanges, in: buffer.text).first ?? .zero
        let lineRange = nsText.lineRange(for: NSRange(location: min(cursor.location, nsText.length), length: 0))
        let line = nsText.substring(with: lineRange)
        let insertion = line.hasSuffix("\n") ? line : "\n\(line)"

        let mutable = NSMutableString(string: buffer.text)
        mutable.insert(insertion, at: lineRange.location + lineRange.length)

        buffers[selectedIndex].text = mutable as String
        buffers[selectedIndex].selectionRanges = [TextRange(location: lineRange.location + lineRange.length, length: insertion.utf16.count)]
        buffers[selectedIndex].isDirty = true
        buffers[selectedIndex].updatedAt = Date()
        persistSoon()
    }

    private func normalizedRanges(_ ranges: [TextRange], in text: String) -> [TextRange] {
        let length = (text as NSString).length
        return ranges.map { range in
            let location = min(max(0, range.location), length)
            return TextRange(location: location, length: min(max(0, range.length), length - location))
        }
    }

    private func normalizedNonEmptyRanges(_ ranges: [TextRange], in text: String) -> [TextRange] {
        normalizedRanges(ranges, in: text)
            .filter { $0.length > 0 }
            .sorted { $0.location < $1.location }
    }

    private func mergedLineRanges(for ranges: [TextRange], in text: String) -> [TextRange] {
        let nsText = text as NSString
        let lineRanges = ranges.map { TextRange(nsText.lineRange(for: $0.nsRange)) }
            .sorted { $0.location < $1.location }

        var merged: [TextRange] = []
        for range in lineRanges {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            let lastEnd = last.location + last.length
            let rangeEnd = range.location + range.length
            if range.location <= lastEnd {
                merged[merged.count - 1] = TextRange(location: last.location, length: max(lastEnd, rangeEnd) - last.location)
            } else {
                merged.append(range)
            }
        }

        return merged
    }

    private func preserveTrailingNewline(_ text: String, transform: ([String]) -> [String]) -> String {
        let hasTrailingNewline = text.hasSuffix("\n") || text.hasSuffix("\r")
        var lines = text.components(separatedBy: .newlines)
        if hasTrailingNewline, lines.last == "" {
            lines.removeLast()
        }

        let output = transform(lines).joined(separator: "\n")
        return hasTrailingNewline ? "\(output)\n" : output
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last == " " || last == "\t" {
            result.removeLast()
        }
        return result
    }

    func swappingCase() -> String {
        map { character in
            let value = String(character)
            let uppercased = value.uppercased()
            let lowercased = value.lowercased()

            if value == uppercased, value != lowercased {
                return lowercased
            }

            if value == lowercased, value != uppercased {
                return uppercased
            }

            return value
        }
        .joined()
    }
}
