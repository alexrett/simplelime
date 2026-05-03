import AppKit
import Foundation

@MainActor
final class EditorStore: ObservableObject {
    @Published var buffers: [EditorBuffer]
    @Published var selectedBufferID: UUID?
    @Published var findQuery = ""
    @Published var replaceText = ""
    @Published var findUsesRegex = false
    @Published var findPanelMode: FindPanelMode = .hidden
    @Published var isPreviewVisible = false
    @Published var fontSize: Double = 14
    @Published var lastError: String?
    @Published var pendingCloseBuffer: EditorBuffer?
    @Published var isAIPanelVisible = false
    @Published var aiRunningSessions = Set<UUID>()
    @Published var aiSessionStatuses: [UUID: String] = [:]

    private let persistence: SessionPersistence
    private let aiFileBridge = AIBufferFileBridge()
    private var pendingSaveTask: Task<Void, Never>?
    private var editorCommandHandler: ((EditorCommand) -> Bool)?
    private var aiClients: [UUID: ACPAgentClient] = [:]
    private var aiChatIDsByAgentSession: [String: UUID] = [:]
    private var aiStreamingMessageIDs: [UUID: UUID] = [:]

    init(persistence: SessionPersistence = SessionPersistence()) {
        self.persistence = persistence
        let loaded = persistence.load()

        if loaded.buffers.isEmpty {
            let initial = EditorBuffer.scratch(index: 1)
            buffers = [initial]
            selectedBufferID = initial.id
        } else {
            buffers = loaded.buffers
            selectedBufferID = loaded.selectedID ?? loaded.buffers.first?.id
        }

        persistSoon()
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
        searchAllTabs(query: findQuery)
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

    func openFile(at url: URL) {
        if let existing = buffers.first(where: { $0.filePath == url.path }) {
            selectedBufferID = existing.id
            return
        }

        do {
            var encoding = String.Encoding.utf8
            let text = try String(contentsOf: url, usedEncoding: &encoding)
            let now = Date()
            let buffer = EditorBuffer(
                id: UUID(),
                title: url.lastPathComponent,
                kind: .file,
                filePath: url.path,
                text: text,
                language: EditorLanguage.detect(fileName: url.lastPathComponent, text: text),
                createdAt: now,
                updatedAt: now,
                isDirty: false,
                selectionRanges: [.zero]
            )

            buffers.append(buffer)
            selectedBufferID = buffer.id
            persistSoon()
        } catch {
            lastError = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
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
        let mutable = NSMutableString(string: buffers[selectedIndex].text)
        let matches = allMatches(in: buffer.text)

        for match in matches.reversed() {
            mutable.replaceCharacters(in: match.range, with: replacementString(for: match, in: buffer.text))
        }

        buffers[selectedIndex].text = mutable as String
        buffers[selectedIndex].isDirty = true
        buffers[selectedIndex].updatedAt = Date()
        buffers[selectedIndex].selectionRanges = matches.isEmpty
            ? buffers[selectedIndex].selectionRanges
            : [TextRange(location: matches[0].range.location, length: replaceText.utf16.count)]
        persistSoon()
    }

    func addNextOccurrence() {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let selections = normalizedRanges(buffer.selectionRanges, in: buffer.text)
        let primarySelection = selections.first(where: { $0.length > 0 })

        let query: String
        if let primarySelection {
            query = nsText.substring(with: primarySelection.nsRange)
        } else {
            query = findQuery
        }

        guard !query.isEmpty else { return }

        let start = selections.map { $0.location + $0.length }.max() ?? 0
        if let next = findRange(query: query, in: buffer.text, from: start, direction: .next, forceLiteral: true) {
            buffers[selectedIndex].selectionRanges = selections + [next]
            persistSoon()
        }
    }

    func clearAdditionalCursors() {
        guard let selectedIndex else { return }
        let first = buffers[selectedIndex].selectionRanges.first ?? .zero
        buffers[selectedIndex].selectionRanges = [first]
        persistSoon()
    }

    func selectSearchResult(_ result: SearchResult) {
        selectedBufferID = result.bufferID

        if let index = buffers.firstIndex(where: { $0.id == result.bufferID }) {
            buffers[index].selectionRanges = [result.range]
            persistSoon()
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

    func transformSelection(_ transform: TextTransform) {
        switch transform {
        case .uppercase:
            replaceTargetText { $0.uppercased() }
        case .lowercase:
            replaceTargetText { $0.lowercased() }
        case .titlecase:
            replaceTargetText { $0.capitalized }
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

    private func searchAllTabs(query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        var results: [SearchResult] = []

        for buffer in buffers {
            let nsText = buffer.text as NSString
            for match in allMatches(in: buffer.text) where results.count < 500 {
                let lineRange = nsText.lineRange(for: match.range)
                let excerpt = nsText.substring(with: lineRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                results.append(
                    SearchResult(
                        bufferID: buffer.id,
                        bufferTitle: buffer.displayTitle,
                        lineNumber: lineNumber(at: match.range.location, in: buffer.text),
                        excerpt: excerpt.isEmpty ? " " : excerpt,
                        range: TextRange(match.range)
                    )
                )
            }
        }

        return results
    }

    private struct FindMatch {
        let range: NSRange
        let regexResult: NSTextCheckingResult?
    }

    private func allMatches(in text: String) -> [FindMatch] {
        guard !findQuery.isEmpty else { return [] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if findUsesRegex {
            guard let regex = try? NSRegularExpression(pattern: findQuery, options: [.caseInsensitive]) else {
                return []
            }

            return regex.matches(in: text, range: fullRange)
                .filter { $0.range.location != NSNotFound && $0.range.length > 0 }
                .map { FindMatch(range: $0.range, regexResult: $0) }
        }

        var matches: [FindMatch] = []
        var searchLocation = 0

        while searchLocation < nsText.length {
            let searchRange = NSRange(location: searchLocation, length: nsText.length - searchLocation)
            let found = nsText.range(of: findQuery, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound { break }
            matches.append(FindMatch(range: found, regexResult: nil))
            searchLocation = found.location + max(found.length, 1)
        }

        return matches
    }

    private func firstMatch(in text: String, range: NSRange) -> FindMatch? {
        allMatches(in: text).first { NSEqualRanges($0.range, range) }
    }

    private func replacementString(for match: FindMatch, in text: String) -> String {
        guard findUsesRegex,
              let regexResult = match.regexResult,
              let regex = try? NSRegularExpression(pattern: findQuery, options: [.caseInsensitive]) else {
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

        let options: NSString.CompareOptions = direction == .previous ? [.caseInsensitive, .backwards] : [.caseInsensitive]

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

enum TextTransform: String, CaseIterable, Identifiable {
    case uppercase
    case lowercase
    case titlecase
    case sortLines
    case uniqueLines
    case trimTrailingWhitespace
    case duplicateLine
    case joinLines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uppercase: "Uppercase"
        case .lowercase: "Lowercase"
        case .titlecase: "Title Case"
        case .sortLines: "Sort Lines"
        case .uniqueLines: "Unique Lines"
        case .trimTrailingWhitespace: "Trim Trailing Whitespace"
        case .duplicateLine: "Duplicate Line"
        case .joinLines: "Join Lines"
        }
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
}
