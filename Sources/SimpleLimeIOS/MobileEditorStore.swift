import Foundation
import SwiftUI

@MainActor
final class MobileEditorStore: ObservableObject {
    @Published private(set) var buffers: [EditorBuffer]
    @Published var selectedBufferID: UUID?
    @Published var findPanelMode: FindPanelMode = .hidden
    @Published var findQuery = ""
    @Published var replaceText = ""
    @Published var findUsesRegex = false
    @Published var wrapsLines = true
    @Published var fontSize: CGFloat = 16
    @Published var pendingCloseBuffer: EditorBuffer?
    @Published var isNetworkPanelVisible = false
    @Published var lastError: String?

    let networkShare: NetworkShareService

    private let persistence = SessionPersistence()
    private var persistTask: Task<Void, Never>?

    var selectedBuffer: EditorBuffer? {
        guard let selectedBufferID else { return buffers.first }
        return buffers.first { $0.id == selectedBufferID }
    }

    var selectedBufferIndex: Int? {
        guard let selectedBufferID else { return buffers.indices.first }
        return buffers.firstIndex { $0.id == selectedBufferID }
    }

    init(networkShare: NetworkShareService = NetworkShareService()) {
        self.networkShare = networkShare
        let loaded = persistence.load()
        if loaded.buffers.isEmpty {
            buffers = [EditorBuffer.scratch(index: 1)]
            selectedBufferID = buffers.first?.id
        } else {
            buffers = loaded.buffers
            selectedBufferID = loaded.selectedID ?? loaded.buffers.first?.id
        }

        networkShare.onReceivedNote = { [weak self] note in
            self?.importSharedNote(note)
        }
    }

    deinit {
        persistTask?.cancel()
    }

    func buffer(id: UUID) -> EditorBuffer? {
        buffers.first { $0.id == id }
    }

    func select(_ id: UUID) {
        selectedBufferID = id
        schedulePersist()
    }

    func newScratch() {
        let index = nextScratchIndex()
        let buffer = EditorBuffer.scratch(index: index)
        buffers.append(buffer)
        selectedBufferID = buffer.id
        schedulePersist()
    }

    func requestClose(_ id: UUID) {
        guard let buffer = buffer(id: id) else { return }
        if shouldConfirmClose(buffer) {
            pendingCloseBuffer = buffer
        } else {
            closeBuffer(id, force: true)
        }
    }

    func closePendingBuffer() {
        guard let id = pendingCloseBuffer?.id else { return }
        pendingCloseBuffer = nil
        closeBuffer(id, force: true)
    }

    func cancelPendingClose() {
        pendingCloseBuffer = nil
    }

    func updateText(_ text: String, in id: UUID) {
        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return }
        guard buffers[index].text != text else { return }
        buffers[index].text = text
        buffers[index].updatedAt = Date()
        buffers[index].isDirty = true
        if buffers[index].kind == .scratch, buffers[index].title.hasPrefix("Scratch") {
            buffers[index].language = EditorLanguage.detect(fileName: nil, text: text)
        }
        schedulePersist()
    }

    func updateSelection(_ selectionRanges: [TextRange], in id: UUID) {
        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return }
        let normalized = selectionRanges.isEmpty ? [.zero] : selectionRanges
        guard buffers[index].selectionRanges != normalized else { return }
        buffers[index].selectionRanges = normalized
        schedulePersist()
    }

    func setLanguage(_ language: EditorLanguage) {
        guard let index = selectedBufferIndex else { return }
        buffers[index].language = language
        buffers[index].updatedAt = Date()
        schedulePersist()
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

    func toggleNetworkPanel() {
        isNetworkPanelVisible.toggle()
    }

    func showNetworkPanel() {
        isNetworkPanelVisible = true
    }

    func hideNetworkPanel() {
        isNetworkPanelVisible = false
    }

    func selectNextTab() {
        guard !buffers.isEmpty else { return }
        let currentIndex = selectedBufferIndex ?? 0
        selectedBufferID = buffers[(currentIndex + 1) % buffers.count].id
        schedulePersist()
    }

    func selectPreviousTab() {
        guard !buffers.isEmpty else { return }
        let currentIndex = selectedBufferIndex ?? 0
        selectedBufferID = buffers[(currentIndex - 1 + buffers.count) % buffers.count].id
        schedulePersist()
    }

    func showFind() {
        findPanelMode = .find
    }

    func showReplace() {
        findPanelMode = .replace
    }

    func hideFindPanel() {
        findPanelMode = .hidden
    }

    func openImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            urls.forEach(openImportedFile)
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    func pairNetworkPeer(_ deviceID: String) {
        networkShare.pair(with: deviceID)
    }

    func acceptPendingNetworkPair() {
        networkShare.acceptPendingPair()
    }

    func rejectPendingNetworkPair() {
        networkShare.rejectPendingPair()
    }

    func removeTrustedNetworkDevice(_ deviceID: String) {
        networkShare.removeTrustedDevice(deviceID)
    }

    func sendSelectedBuffer(to deviceID: String) {
        guard let selectedBuffer else { return }
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
        schedulePersist()
    }

    func findNext() {
        guard let buffer = selectedBuffer, !findQuery.isEmpty else { return }
        let matches = ranges(for: findQuery, in: buffer.text)
        guard !matches.isEmpty else { return }

        let selectedRange = buffer.selectionRanges.first ?? .zero
        let start = selectedRange.location + max(selectedRange.length, 1)
        let next = matches.first { $0.location >= start } ?? matches[0]
        updateSelection([next], in: buffer.id)
    }

    func findPrevious() {
        guard let buffer = selectedBuffer, !findQuery.isEmpty else { return }
        let matches = ranges(for: findQuery, in: buffer.text)
        guard !matches.isEmpty else { return }

        let selectedRange = buffer.selectionRanges.first ?? .zero
        let previous = matches.last { $0.location < selectedRange.location } ?? matches[matches.count - 1]
        updateSelection([previous], in: buffer.id)
    }

    func selectAllMatches() {
        guard let buffer = selectedBuffer, !findQuery.isEmpty else { return }
        let matches = ranges(for: findQuery, in: buffer.text)
        if !matches.isEmpty {
            updateSelection(matches, in: buffer.id)
        }
    }

    func replaceCurrent() {
        guard let buffer = selectedBuffer, let selection = buffer.selectionRanges.first else { return }
        if selection.length == 0 {
            findNext()
            return
        }

        replace(ranges: [selection], in: buffer, with: replaceText)
        findNext()
    }

    func replaceAll() {
        guard let buffer = selectedBuffer, !findQuery.isEmpty else { return }
        let matches = ranges(for: findQuery, in: buffer.text)
        replace(ranges: matches, in: buffer, with: replaceText)
    }

    func performTextTransform(_ transform: TextTransform) {
        guard let buffer = selectedBuffer else { return }
        let selections = buffer.selectionRanges.isEmpty ? [.zero] : buffer.selectionRanges
        let lineTransforms: Set<TextTransform> = [.sortLines, .uniqueLines, .trimTrailingWhitespace, .duplicateLine, .joinLines]
        let ranges = lineTransforms.contains(transform) ? lineRanges(for: selections, in: buffer.text) : selections

        var newText = buffer.text
        var newSelections: [TextRange] = []
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            let safeRange = safeNSRange(range.nsRange, in: newText)
            let selected = (newText as NSString).substring(with: safeRange)
            let transformed = transformText(selected, transform: transform)
            newText = (newText as NSString).replacingCharacters(in: safeRange, with: transformed)
            newSelections.append(TextRange(location: safeRange.location, length: (transformed as NSString).length))
        }

        updateText(newText, in: buffer.id)
        updateSelection(newSelections.reversed(), in: buffer.id)
    }

    private func closeBuffer(_ id: UUID, force: Bool) {
        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return }
        let buffer = buffers[index]
        guard force || !shouldConfirmClose(buffer) else {
            pendingCloseBuffer = buffer
            return
        }

        buffers.remove(at: index)
        if buffers.isEmpty {
            let scratch = EditorBuffer.scratch(index: 1)
            buffers = [scratch]
            selectedBufferID = scratch.id
        } else if selectedBufferID == id {
            selectedBufferID = buffers[min(index, buffers.count - 1)].id
        }
        schedulePersist()
    }

    private func shouldConfirmClose(_ buffer: EditorBuffer) -> Bool {
        buffer.isDirty || !buffer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func openImportedFile(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
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
                selectionRanges: [.zero],
                aiSessions: [],
                selectedAIChatSessionID: nil
            )
            buffers.append(buffer)
            selectedBufferID = buffer.id
            schedulePersist()
        } catch {
            lastError = error.localizedDescription
        }
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

    private func nextScratchIndex() -> Int {
        let scratchNumbers = buffers.compactMap { buffer -> Int? in
            guard buffer.title.hasPrefix("Scratch ") else { return nil }
            return Int(buffer.title.replacingOccurrences(of: "Scratch ", with: ""))
        }
        return (scratchNumbers.max() ?? 0) + 1
    }

    private func ranges(for query: String, in text: String) -> [TextRange] {
        guard !query.isEmpty else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if findUsesRegex {
            do {
                let regex = try NSRegularExpression(pattern: query)
                return regex.matches(in: text, range: fullRange).map { TextRange($0.range) }
            } catch {
                lastError = error.localizedDescription
                return []
            }
        }

        var results: [TextRange] = []
        var searchRange = fullRange
        while searchRange.location < nsText.length {
            let range = nsText.range(of: query, options: [], range: searchRange)
            if range.location == NSNotFound { break }
            results.append(TextRange(range))
            let nextLocation = range.location + max(range.length, 1)
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }
        return results
    }

    private func replace(ranges: [TextRange], in buffer: EditorBuffer, with replacement: String) {
        guard !ranges.isEmpty else { return }
        var text = buffer.text
        var insertedRanges: [TextRange] = []
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            let nsRange = safeNSRange(range.nsRange, in: text)
            let finalReplacement = replacementFor(range: nsRange, in: text, replacement: replacement)
            text = (text as NSString).replacingCharacters(in: nsRange, with: finalReplacement)
            insertedRanges.append(TextRange(location: nsRange.location, length: (finalReplacement as NSString).length))
        }
        updateText(text, in: buffer.id)
        updateSelection(insertedRanges.reversed(), in: buffer.id)
    }

    private func replacementFor(range: NSRange, in text: String, replacement: String) -> String {
        guard findUsesRegex else { return replacement }
        do {
            let regex = try NSRegularExpression(pattern: findQuery)
            let selected = (text as NSString).substring(with: range)
            return regex.stringByReplacingMatches(
                in: selected,
                range: NSRange(location: 0, length: (selected as NSString).length),
                withTemplate: replacement
            )
        } catch {
            return replacement
        }
    }

    private func lineRanges(for ranges: [TextRange], in text: String) -> [TextRange] {
        let nsText = text as NSString
        let resolved = ranges.map { TextRange(nsText.lineRange(for: safeNSRange($0.nsRange, in: text))) }
            .sorted { $0.location < $1.location }

        var merged: [TextRange] = []
        for range in resolved {
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

    private func transformText(_ text: String, transform: TextTransform) -> String {
        switch transform {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titlecase:
            return text.localizedCapitalized
        case .sortLines:
            return preserveTrailingNewline(text) { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
        case .uniqueLines:
            return preserveTrailingNewline(text) { lines in
                var seen = Set<String>()
                return lines.filter { seen.insert($0).inserted }
            }
        case .trimTrailingWhitespace:
            return preserveTrailingNewline(text) { $0.map { $0.trimmingTrailingWhitespace() } }
        case .duplicateLine:
            return text + text
        case .joinLines:
            return text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
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

    private func safeNSRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = max(0, min(range.location, length))
        let upper = max(location, min(range.location + range.length, length))
        return NSRange(location: location, length: upper - location)
    }

    private func schedulePersist() {
        persistTask?.cancel()
        let buffersSnapshot = buffers
        let selectedID = selectedBufferID
        persistTask = Task { [persistence] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            try? persistence.save(buffers: buffersSnapshot, selectedID: selectedID)
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
