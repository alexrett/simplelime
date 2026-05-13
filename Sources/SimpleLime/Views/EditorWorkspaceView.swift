import SwiftUI

struct EditorWorkspaceView: View {
    @ObservedObject var store: EditorStore
    let buffer: EditorBuffer
    @State private var sourceVisibleLineRange: ClosedRange<Int> = 1...1

    var body: some View {
        VStack(spacing: 0) {
            workspaceContent
            StatusBarView(store: store, buffer: buffer, visibleLineRange: sourceVisibleLineRange)
        }
        .clipped()
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if store.isTerminalPanelVisible {
            VSplitView {
                editorContent
                    .frame(minHeight: 160)
                TerminalPanelView(store: store)
            }
        } else {
            editorContent
        }
    }

    private var editorContent: some View {
        Group {
            if buffer.language.isBinaryPreview, let filePath = buffer.filePath {
                BinaryFilePreviewView(fileURL: URL(fileURLWithPath: filePath), language: buffer.language)
            } else if store.isPreviewVisible, buffer.language.supportsRenderedPreview, canShowRenderedPreview {
                HSplitView {
                    editorPane
                        .frame(minWidth: 180)
                    renderedPreview
                        .frame(minWidth: 200)
                }
            } else {
                editorPane
            }
        }
    }

    @ViewBuilder
    private var renderedPreview: some View {
        if buffer.language.isMarkdown {
            MarkdownPreviewView(
                text: buffer.text,
                baseURL: buffer.filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            )
        } else if buffer.language.isDelimitedTable {
            if buffer.isLargeFileMode, let filePath = buffer.filePath {
                DelimitedVirtualTablePreviewView(
                    fileURL: URL(fileURLWithPath: filePath),
                    language: buffer.language
                )
            } else {
                DelimitedTablePreviewView(
                    text: buffer.text,
                    language: buffer.language,
                    isLargeFilePreview: buffer.isLargeFileMode
                )
            }
        }
    }

    private var canShowRenderedPreview: Bool {
        !buffer.isLargeFileMode || buffer.language.isDelimitedTable
    }

    private var editorPane: some View {
        HStack(alignment: .top, spacing: 0) {
            editor
            if store.isMiniMapVisible, !store.isWysiwygModeEnabled, !buffer.isLargeFileMode, !buffer.language.isWhiteboard {
                EditorMiniMapView(
                    text: buffer.text,
                    selectionRanges: buffer.selectionRanges,
                    visibleLineRange: sourceVisibleLineRange,
                    onSelectLine: { lineNumber in
                        store.jumpToLine(lineNumber)
                    }
                )
                .frame(width: 86)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var editor: some View {
        Group {
            if buffer.language.isMarkdown, store.isWysiwygModeEnabled, !buffer.isLargeFileMode {
                MarkdownWYSIWYGEditorView(
                    text: textBinding,
                    selectionRanges: selectionBinding,
                    baseURL: buffer.filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() },
                    fontSize: store.fontSize,
                    typewriterModeEnabled: store.isTypewriterModeEnabled,
                    comments: store.comments(for: buffer),
                    activeCommentID: store.selectedCommentID,
                    collaborators: store.collaborators(for: buffer),
                    onSelectComment: { commentID in
                        store.selectComment(commentID)
                    },
                    onShortcut: handleShortcut,
                    onRegisterEditorCommandHandler: { handler in
                        store.registerEditorCommandHandler(handler)
                    }
                )
            } else if buffer.language.isWhiteboard {
                WhiteboardView(text: textBinding)
            } else if buffer.isLargeFileMode,
                      store.buffers.first(where: { $0.id == buffer.id }).map({ !store.bufferCanEditLargeFileChunk($0) }) != false,
                      let filePath = buffer.filePath {
                let liveBuffer = store.buffers.first(where: { $0.id == buffer.id }) ?? buffer
                LargeFileVirtualTextView(
                    fileURL: URL(fileURLWithPath: filePath),
                    language: liveBuffer.language,
                    fileSizeBytes: liveBuffer.fileSizeBytes,
                    fontSize: store.fontSize,
                    targetByteOffset: liveBuffer.largeFilePreviewStartOffsetBytes,
                    contentRevision: liveBuffer.updatedAt.timeIntervalSinceReferenceDate,
                    onLineActivation: { lineNumber in
                        store.editSelectedLargeFileChunk(containingLine: lineNumber)
                    },
                    onLineReplacementRequest: { lineNumber, replacementText in
                        store.replaceSelectedLargeFileLine(lineNumber, with: replacementText)
                    },
                    onLineInsertionRequest: { lineNumber, insertedText in
                        store.insertSelectedLargeFileLine(lineNumber, text: insertedText)
                    },
                    onLineDeletionRequest: { lineNumber in
                        store.deleteSelectedLargeFileLine(lineNumber)
                    },
                    onVisibleLineRangeChange: { lineRange in
                        sourceVisibleLineRange = lineRange
                        store.updateLargeFileVisibleLineRange(lineRange, for: buffer.id)
                    }
                )
                .help("Click a line to edit it inline. Double-click a line to open a bounded editable chunk; Cmd-S saves the chunk back to the source file.")
            } else {
                SourceEditorView(
                    text: textBinding,
                    selectionRanges: selectionBinding,
                    configuration: sourceEditorConfiguration(for: buffer),
                    decorations: sourceEditorDecorations(for: buffer),
                    callbacks: sourceEditorCallbacks(for: buffer)
                )
            }
        }
        .clipped()
    }

    private func sourceEditorConfiguration(for buffer: EditorBuffer) -> SourceEditorConfiguration {
        let liveBuffer = store.buffers.first(where: { $0.id == buffer.id }) ?? buffer
        let largeFileEditingCapability = store.largeFileEditingCapability(for: liveBuffer)
        return SourceEditorConfiguration(
            engine: store.sourceEditorEngine,
            language: liveBuffer.language,
            fontSize: store.fontSize,
            wrapsLines: store.wrapsLines,
            columnGuide: store.columnGuide,
            foldedRanges: store.foldedRanges(for: buffer),
            syntaxHighlightingEnabled: !buffer.isLargeFileMode || largeFileEditingCapability.canEditLoadedText,
            isEditable: !buffer.isLargeFileMode || largeFileEditingCapability.canEditLoadedText,
            focusModeEnabled: store.isFocusModeEnabled,
            typewriterModeEnabled: store.isTypewriterModeEnabled
        )
    }

    private func sourceEditorDecorations(for buffer: EditorBuffer) -> SourceEditorDecorations {
        SourceEditorDecorations(
            comments: store.comments(for: buffer),
            activeCommentID: store.selectedCommentID,
            collaborators: store.collaborators(for: buffer)
        )
    }

    private func sourceEditorCallbacks(for buffer: EditorBuffer) -> SourceEditorCallbacks {
        SourceEditorCallbacks(
            onShortcut: handleShortcut,
            onVisibleLineRangeChange: { lineRange in
                sourceVisibleLineRange = lineRange
            },
            onToggleFoldAtLine: { lineNumber in
                store.toggleStructuredFold(containingLine: lineNumber, in: buffer.id)
            },
            onRegisterEditorCommandHandler: { handler in
                store.registerEditorCommandHandler(handler)
            }
        )
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { store.buffers.first(where: { $0.id == buffer.id })?.text ?? "" },
            set: { store.updateText($0, in: buffer.id) }
        )
    }

    private var selectionBinding: Binding<[TextRange]> {
        Binding(
            get: { store.buffers.first(where: { $0.id == buffer.id })?.selectionRanges ?? [.zero] },
            set: { store.updateSelection($0, in: buffer.id) }
        )
    }

    private func handleShortcut(_ shortcut: EditorShortcut) {
        switch shortcut {
        case .showCommandPalette:
            store.showCommandPalette()
        case .openFolder:
            store.openFolder()
        case .showFind:
            store.showFind()
        case .showReplace:
            store.showReplace()
        case .showGlobalFind:
            store.showGlobalFind()
        case .findNext:
            store.findNext()
        case .findPrevious:
            store.findPrevious()
        case .selectAllMatches:
            store.selectAllMatches()
        case .addNextOccurrence:
            store.addNextOccurrence()
        case .addPreviousOccurrence:
            store.addPreviousOccurrence()
        case .toggleWrapLines:
            store.toggleWrapLines()
        case .showSourceMode:
            store.showSourceMode()
        case .showMarkdownPreviewMode:
            store.showMarkdownPreviewMode()
        case .showMarkdownWysiwygMode:
            store.showMarkdownWysiwygMode()
        case .toggleMarkdownPreview:
            store.toggleMarkdownPreview()
        case .toggleMarkdownOutline:
            store.toggleMarkdownOutline()
        case .toggleDocumentCatalog:
            store.toggleDocumentCatalog()
        case .toggleWysiwygMode:
            store.toggleWysiwygMode()
        case .toggleFocusMode:
            store.toggleFocusMode()
        case .toggleTypewriterMode:
            store.toggleTypewriterMode()
        case .toggleMiniMap:
            store.toggleMiniMap()
        case .toggleCommentsPanel:
            store.toggleCommentsPanel()
        case .addComment:
            store.addCommentToSelection()
        case .transform(let transform):
            store.performTextTransform(transform)
        case .editorCommand(let command):
            store.performEditorCommand(command)
        case .markdown(let command):
            store.performMarkdownCommand(command)
        case .increaseFontSize:
            store.increaseFontSize()
        case .decreaseFontSize:
            store.decreaseFontSize()
        case .nextTab:
            store.selectNextTab()
        case .previousTab:
            store.selectPreviousTab()
        case .toggleAI:
            store.toggleAIPanel()
        case .toggleTerminal:
            store.toggleTerminalPanel()
        case .escape:
            store.escape()
        }
    }
}

struct EditorMiniMapLayout: Equatable {
    let lineCount: Int
    let height: CGFloat

    init(lineCount: Int, height: CGFloat) {
        self.lineCount = max(1, lineCount)
        self.height = max(1, height)
    }

    var rowHeight: CGFloat {
        min(4, height / CGFloat(lineCount))
    }

    var contentHeight: CGFloat {
        CGFloat(lineCount) * rowHeight
    }

    var top: CGFloat {
        0
    }

    func lineNumber(at y: CGFloat) -> Int {
        guard y > top else { return 1 }
        guard y < top + contentHeight else { return lineCount }

        let raw = Int(((y - top) / rowHeight).rounded(.down)) + 1
        return min(max(1, raw), lineCount)
    }

    func y(forLine lineNumber: Int) -> CGFloat {
        let clamped = min(max(1, lineNumber), lineCount)
        return top + CGFloat(clamped - 1) * rowHeight
    }

    func clampedRange(_ range: ClosedRange<Int>?) -> ClosedRange<Int>? {
        guard let range else { return nil }
        let lower = min(max(1, range.lowerBound), lineCount)
        let upper = min(max(lower, range.upperBound), lineCount)
        return lower...upper
    }

    func viewportRect(for range: ClosedRange<Int>, width: CGFloat) -> CGRect {
        let clamped = clampedRange(range) ?? 1...1
        let startY = y(forLine: clamped.lowerBound)
        let bottom = y(forLine: clamped.upperBound) + rowHeight
        let viewportHeight = max(12, bottom - startY)
        let rectY = min(max(0, startY - 1), max(0, height - viewportHeight))

        return CGRect(
            x: 3,
            y: rectY,
            width: max(1, width - 6),
            height: min(height, viewportHeight)
        )
    }
}

private struct EditorMiniMapView: View {
    let text: String
    let selectionRanges: [TextRange]
    let visibleLineRange: ClosedRange<Int>?
    let onSelectLine: (Int) -> Void

    @State private var dragLine: Int?
    @State private var lastDispatchedLine: Int?

    private var lines: [String] {
        text.components(separatedBy: .newlines)
    }

    private var activeLine: Int {
        let location = selectionRanges.last?.location ?? 0
        return MarkdownDocumentInfo.lineNumber(at: location, in: text)
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let lineCount = max(lines.count, 1)
                let layout = EditorMiniMapLayout(lineCount: lineCount, height: size.height)

                if let viewportRange = layout.clampedRange(visibleLineRange) {
                    let viewportRect = layout.viewportRect(for: viewportRange, width: size.width)
                    context.fill(
                        Path(roundedRect: viewportRect, cornerRadius: 4),
                        with: .color(Color.accentColor.opacity(0.10))
                    )
                    context.stroke(
                        Path(roundedRect: viewportRect, cornerRadius: 4),
                        with: .color(Color.accentColor.opacity(0.28)),
                        lineWidth: 1
                    )
                }

                if (1...lineCount).contains(activeLine) {
                    let y = layout.y(forLine: activeLine)
                    let rect = CGRect(x: 4, y: y - 2, width: size.width - 8, height: max(5, layout.rowHeight + 4))
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .color(Color.accentColor.opacity(0.22))
                    )
                }

                if let dragLine {
                    let y = layout.y(forLine: dragLine)
                    let rect = CGRect(x: 3, y: y, width: size.width - 6, height: max(2, layout.rowHeight))
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(Color.accentColor.opacity(0.55))
                    )
                }

                for (index, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    let intensity = trimmed.isEmpty ? 0.16 : 0.34
                    let width = max(12, min(size.width - 18, CGFloat(trimmed.utf16.count) * 1.25))
                    let y = layout.y(forLine: index + 1)
                    let rect = CGRect(x: 9, y: y, width: width, height: max(1, layout.rowHeight * 0.55))
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(Color.secondary.opacity(intensity))
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectLine(at: value.location.y, height: proxy.size.height)
                    }
                    .onEnded { value in
                        selectLine(at: value.location.y, height: proxy.size.height)
                        dragLine = nil
                        lastDispatchedLine = nil
                    }
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
    }

    private func selectLine(at y: CGFloat, height: CGFloat) {
        let lineNumber = lineNumber(at: y, height: height)
        dragLine = lineNumber
        guard lastDispatchedLine != lineNumber else { return }

        lastDispatchedLine = lineNumber
        onSelectLine(lineNumber)
    }

    private func lineNumber(at y: CGFloat, height: CGFloat) -> Int {
        EditorMiniMapLayout(lineCount: lines.count, height: height).lineNumber(at: y)
    }
}

struct CommentsPanelView: View {
    @ObservedObject var store: EditorStore
    let buffer: EditorBuffer

    private var comments: [DocumentComment] {
        store.comments(for: buffer)
    }

    private var canAddComment: Bool {
        buffer.selectionRanges.contains { $0.length > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if comments.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No comments")
                        .font(.headline)
                    Text("Select text and add a comment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(comments) { comment in
                                commentCard(comment)
                                    .id(comment.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: store.selectedCommentID) { _, commentID in
                        guard let commentID else { return }
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(commentID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
            Text("Comments")
                .font(.headline)
            Spacer()
            Button {
                store.addCommentToSelection()
            } label: {
                Image(systemName: "plus.bubble")
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(!canAddComment)
            .help(canAddComment ? "Add comment to selected text" : "Select text to add a comment")

            Button {
                store.hideCommentsPanel()
            } label: {
                Image(systemName: "sidebar.right")
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .help("Hide comments")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func commentCard(_ comment: DocumentComment) -> some View {
        let isActive = store.selectedCommentID == comment.id

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                store.jumpToComment(comment.id)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(comment.displayQuote)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TextEditor(text: bodyBinding(for: comment.id))
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 58, maxHeight: 110)
                .padding(5)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }

            HStack(spacing: 8) {
                if let reminderAt = comment.reminderAt {
                    Label(reminderAt.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Menu {
                    ForEach(CommentReminderPreset.allCases) { preset in
                        Button(preset.title) {
                            store.scheduleCommentReminder(comment.id, after: preset.interval)
                        }
                    }
                    if comment.reminderAt != nil {
                        Divider()
                        Button("Clear Reminder") {
                            store.clearCommentReminder(comment.id)
                        }
                    }
                } label: {
                    Image(systemName: comment.reminderAt == nil ? "bell" : "bell.fill")
                        .frame(width: 22, height: 20)
                }
                .menuStyle(.borderlessButton)
                .help("Remind later")

                Button {
                    store.resolveComment(comment.id)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .help("Resolve")

                Button {
                    store.deleteComment(comment.id)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete")
            }
        }
        .padding(10)
        .background(isActive ? Color.accentColor.opacity(0.14) : Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.46) : Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private func bodyBinding(for commentID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.documentComments.first(where: { $0.id == commentID })?.body ?? ""
            },
            set: { body in
                store.updateCommentBody(commentID, body: body)
            }
        )
    }
}

struct MarkdownOutlineView: View {
    let text: String
    let selectionRanges: [TextRange]
    let onSelect: (MarkdownHeading) -> Void

    @State private var query = ""

    private var headings: [MarkdownHeading] {
        MarkdownDocumentInfo.headings(in: text)
    }

    private var currentHeading: MarkdownHeading? {
        MarkdownDocumentInfo.currentHeading(in: text, selectionRanges: selectionRanges)
    }

    private var filteredHeadings: [MarkdownHeading] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return headings }

        return headings.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.indent")
                    .foregroundStyle(.secondary)
                Text("Outline")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            TextField("Filter", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            if filteredHeadings.isEmpty {
                VStack {
                    Spacer()
                    Text("No headings")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredHeadings) { heading in
                            outlineRow(for: heading)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
    }

    private func outlineRow(for heading: MarkdownHeading) -> some View {
        let isCurrent = currentHeading?.id == heading.id

        return Button {
            onSelect(heading)
        } label: {
            HStack(spacing: 8) {
                Text(heading.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(heading.lineNumber)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 12 + CGFloat(max(0, heading.level - 1)) * 12)
            .padding(.trailing, 12)
            .frame(minHeight: 32)
            .foregroundStyle(isCurrent ? .primary : .secondary)
            .background(isCurrent ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.22) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StatusBarView: View {
    @ObservedObject var store: EditorStore
    let buffer: EditorBuffer
    let visibleLineRange: ClosedRange<Int>

    private var stats: TextDocumentStats {
        MarkdownDocumentInfo.stats(for: buffer.text)
    }

    var body: some View {
        GeometryReader { proxy in
            statusContent(style: StatusBarDensity(width: proxy.size.width))
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 30)
        .background(.bar)
    }

    private func statusContent(style: StatusBarDensity) -> some View {
        let finderTags = store.selectedFinderTags
        let pinnedMacroButtons = Array(store.pinnedMacroButtons.prefix(style.pinnedMacroButtonLimit))
        let liveBuffer = store.buffers.first(where: { $0.id == buffer.id }) ?? buffer
        let largeFileEditingCapability = store.largeFileEditingCapability(for: liveBuffer)
        let canOpenVisibleLargeFileChunk = store.selectedLargeFileCanOpenVisibleChunkForEditing

        return HStack(spacing: style.spacing) {
            Menu {
                ForEach(EditorLanguage.allCases) { language in
                    Button(language.displayName) {
                        store.setLanguage(language)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "textformat")
                    if style.showsLanguageText {
                        Text(buffer.language.displayName)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: style.languageWidth, alignment: .leading)
            .clipped()

            StatusIconButton(
                systemName: "arrow.left.and.right.text.vertical",
                isActive: store.wrapsLines,
                isEnabled: !store.isWysiwygModeEnabled,
                help: store.wrapsLines ? "Word wrap enabled" : "Word wrap disabled"
            ) {
                store.toggleWrapLines()
            }

            StatusIconButton(
                systemName: "arrow.down.right.and.arrow.up.left",
                isActive: store.hasStructuredFolds(for: buffer),
                isEnabled: store.selectedBufferSupportsStructuredFolding && !store.isWysiwygModeEnabled,
                help: store.hasStructuredFolds(for: buffer)
                    ? "Structured folding active"
                    : "Toggle structured fold"
            ) {
                store.toggleStructuredFoldAtSelection()
            }

            if buffer.language.isMarkdown {
                HStack(spacing: 2) {
                    StatusIconButton(
                        systemName: "chevron.left.forwardslash.chevron.right",
                        isActive: !store.isPreviewVisible && !store.isWysiwygModeEnabled,
                        help: "Source mode"
                    ) {
                        store.showSourceMode()
                    }

                    StatusIconButton(
                        systemName: "rectangle.split.2x1",
                        isActive: store.isPreviewVisible && !buffer.isLargeFileMode,
                        isEnabled: !buffer.isLargeFileMode,
                        help: buffer.isLargeFileMode ? "Preview is disabled in large-file mode" : "Source with rendered preview"
                    ) {
                        store.showMarkdownPreviewMode()
                    }

                    StatusIconButton(
                        systemName: "doc.richtext",
                        isActive: store.isWysiwygModeEnabled && !buffer.isLargeFileMode,
                        isEnabled: !buffer.isLargeFileMode,
                        help: buffer.isLargeFileMode ? "WYSIWYG is disabled in large-file mode" : "WYSIWYG Markdown mode"
                    ) {
                        store.showMarkdownWysiwygMode()
                    }
                }

                StatusIconButton(
                    systemName: "list.bullet.rectangle",
                    isActive: store.isOutlineVisible,
                    help: "Markdown outline"
                ) {
                    store.toggleMarkdownOutline()
                }
            } else if buffer.language.isDelimitedTable {
                HStack(spacing: 2) {
                    StatusIconButton(
                        systemName: "chevron.left.forwardslash.chevron.right",
                        isActive: !store.isPreviewVisible,
                        help: "Source mode"
                    ) {
                        store.showSourceMode()
                    }

                    StatusIconButton(
                        systemName: "tablecells",
                        isActive: store.isPreviewVisible,
                        help: buffer.isLargeFileMode ? "Table preview for current large-file chunk" : "Table preview"
                    ) {
                        store.showDelimitedTablePreviewMode()
                    }
                }
            }

            StatusIconButton(
                systemName: "scope",
                isActive: store.isFocusModeEnabled && !buffer.isLargeFileMode,
                isEnabled: !store.isWysiwygModeEnabled && !buffer.isLargeFileMode,
                help: buffer.isLargeFileMode ? "Focus mode is disabled in large-file mode" : "Focus mode"
            ) {
                store.toggleFocusMode()
            }

            StatusIconButton(
                systemName: "map",
                isActive: store.isMiniMapVisible && !buffer.isLargeFileMode,
                isEnabled: !store.isWysiwygModeEnabled && !buffer.isLargeFileMode,
                help: buffer.isLargeFileMode
                    ? "Minimap is disabled in large-file mode"
                    : (store.isWysiwygModeEnabled ? "Minimap is available in source mode" : "Minimap (⌘⌥4)")
            ) {
                store.toggleMiniMap()
            }

            StatusIconButton(
                systemName: "keyboard",
                isActive: store.isTypewriterModeEnabled,
                help: "Typewriter mode"
            ) {
                store.toggleTypewriterMode()
            }

            StatusIconButton(
                systemName: "terminal",
                isActive: store.isTerminalPanelVisible,
                help: "Terminal"
            ) {
                store.toggleTerminalPanel()
            }

            StatusIconButton(
                systemName: "text.bubble",
                isActive: store.isCommentsPanelVisible,
                help: "Comments"
            ) {
                store.toggleCommentsPanel()
            }

            StatusIconButton(
                systemName: "eye",
                isActive: store.isCompanionPanelVisible,
                help: "Companion"
            ) {
                store.toggleCompanionPanel()
            }

            StatusIconButton(
                systemName: "checklist",
                isActive: store.isTasksPanelVisible,
                help: "Tasks"
            ) {
                store.toggleTasksPanel()
            }

            StatusIconButton(
                systemName: "point.3.connected.trianglepath.dotted",
                isActive: store.isPOModePanelVisible,
                help: "PO mode"
            ) {
                store.togglePOModePanel()
            }

            StatusIconButton(
                systemName: store.isVoiceScribeRunning ? "waveform.circle.fill" : "waveform.circle",
                isActive: store.isScribePanelVisible || store.isVoiceScribeRunning,
                help: "Scribe"
            ) {
                store.toggleScribePanel()
            }

            StatusIconButton(
                systemName: "text.badge.plus",
                isActive: store.isMacrosPanelVisible,
                help: "Macros"
            ) {
                store.toggleMacrosPanel()
            }

            ForEach(pinnedMacroButtons) { button in
                StatusMacroButton(
                    button: button,
                    showsTitle: style.showsPinnedMacroTitles
                ) {
                    store.applyPinnedMacro(button.reference)
                }
            }

            StatusIconButton(
                systemName: "chart.bar.xaxis",
                isActive: store.isStatsPanelVisible,
                help: "Usage stats"
            ) {
                store.toggleStatsPanel()
            }

            StatusIconButton(
                systemName: "person.2",
                isActive: store.collaborationSession?.bufferID == buffer.id,
                help: store.collaborationSession?.statusText ?? "Collaboration"
            ) {
                store.showNetworkPanel()
            }

            if style.showsPath {
                Text(buffer.filePath ?? "Scratch")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .allowsTightening(true)
                    .help(buffer.filePath ?? "Scratch")
                    .frame(minWidth: style.pathMinWidth, maxWidth: style.pathMaxWidth, maxHeight: 16, alignment: .leading)
                    .clipped()
                    .layoutPriority(-1)
            }

            if buffer.savePolicy != .normal {
                HStack(spacing: 4) {
                    Image(systemName: buffer.savePolicy.systemImage)
                    Text(buffer.savePolicy.displayName)
                }
                .foregroundStyle(.secondary)
                .fixedSize()
                .help(buffer.savePolicy.blockedSaveMessage(for: buffer.displayTitle))
            }

            if store.selectedBufferCanSaveLargeFileChunkBack {
                StatusIconButton(
                    systemName: "square.and.arrow.down",
                    isActive: false,
                    help: "Save this edited chunk back to its source large file"
                ) {
                    store.saveSelectedLargeFileChunkBackToSource()
                }
            }

            if buffer.isEncrypted {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                    Text("Encrypted")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .help("This file is saved as a password-protected SimpleLime encrypted document.")
            }

            if buffer.isLargeFileMode {
                if style.showsLargeFileControls {
                    HStack(spacing: 1) {
                        StatusIconButton(
                            systemName: "backward.end",
                            isActive: false,
                            isEnabled: store.selectedLargeFileCanPageBackward,
                            help: "Show first large-file chunk"
                        ) {
                            store.showLargeFileFirstChunk()
                        }

                        StatusIconButton(
                            systemName: "chevron.left",
                            isActive: false,
                            isEnabled: store.selectedLargeFileCanPageBackward,
                            help: "Show previous large-file chunk"
                        ) {
                            store.showLargeFilePreviousChunk()
                        }

                        StatusIconButton(
                            systemName: "chevron.right",
                            isActive: false,
                            isEnabled: store.selectedLargeFileCanPageForward,
                            help: "Show next large-file chunk"
                        ) {
                            store.showLargeFileNextChunk()
                        }

                        StatusIconButton(
                            systemName: "forward.end",
                            isActive: false,
                            isEnabled: store.selectedLargeFileCanPageForward,
                            help: "Show last large-file chunk"
                        ) {
                            store.showLargeFileLastChunk()
                        }

                        StatusIconButton(
                            systemName: "number",
                            isActive: false,
                            help: "Jump to a line in the full large file"
                        ) {
                            store.jumpSelectedLargeFileToLineWithPrompt()
                        }

                        StatusIconButton(
                            systemName: "magnifyingglass",
                            isActive: false,
                            help: "Search the full large file"
                        ) {
                            store.searchSelectedLargeFileWithPrompt()
                        }

                        StatusIconButton(
                            systemName: "pencil.line",
                            isActive: largeFileEditingCapability.canEditLoadedText,
                            isEnabled: largeFileEditingCapability.canEnableInPlaceChunkEditing || canOpenVisibleLargeFileChunk,
                            help: canOpenVisibleLargeFileChunk
                                ? "Edit the chunk containing the first visible large-file line"
                                : largeFileEditingCapability.canEnableInPlaceChunkEditing
                                    ? "Edit the current loaded chunk in place"
                                    : largeFileEditingCapability.editUnavailableMessage
                        ) {
                            if canOpenVisibleLargeFileChunk {
                                store.editSelectedLargeFileChunk(containingVisibleLineRange: visibleLineRange)
                            } else {
                                store.enableSelectedLargeFileChunkEditing()
                            }
                        }

                        StatusIconButton(
                            systemName: "doc.on.doc",
                            isActive: false,
                            isEnabled: largeFileEditingCapability.canEnableInPlaceChunkEditing || canOpenVisibleLargeFileChunk,
                            help: canOpenVisibleLargeFileChunk
                                ? "Open the chunk containing the first visible large-file line as editable scratch"
                                : "Open current chunk as editable scratch"
                        ) {
                            if canOpenVisibleLargeFileChunk {
                                store.openSelectedLargeFileChunkAsScratch(containingVisibleLineRange: visibleLineRange)
                            } else {
                                store.openSelectedLargeFileChunkAsScratch()
                            }
                        }
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                    Text(largeFileStatusText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
                .fixedSize()
                .help(largeFileEditingCapability.detail)

                if let searchStatus = store.largeFileSearchStatus, style != .minimal {
                    Text(searchStatus)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: style.largeFileSearchStatusWidth, alignment: .leading)
                        .clipped()
                        .help(searchStatus)
                }
            }

            if !finderTags.isEmpty, style.showsPath {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                    Text(finderTags.joined(separator: ", "))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: style.tagMaxWidth, alignment: .leading)
                .clipped()
                .help(finderTags.joined(separator: ", "))
            }

            if style.showsStats, !buffer.isLargeFileMode {
                Text("\(stats.characters) chars")
                    .fixedSize()
                Text("\(stats.words) words")
                    .fixedSize()
                Text("\(stats.lines) lines")
                    .fixedSize()
                if stats.readingMinutes > 0 {
                    Text("\(stats.readingMinutes) min")
                        .fixedSize()
                }
                if buffer.selectionRanges.count > 1 {
                    Text("\(buffer.selectionRanges.count) cursors")
                        .fixedSize()
                }
            }

            Spacer()

            if style.showsSaveText {
                Text(buffer.isDirty ? "Modified" : "Saved")
                    .fixedSize()
            } else {
                Image(systemName: buffer.isDirty ? "circle.fill" : "checkmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .help(buffer.isDirty ? "Modified" : "Saved")
                    .fixedSize()
            }
        }
    }

    private var largeFileStatusText: String {
        let liveBuffer = store.buffers.first(where: { $0.id == buffer.id }) ?? buffer
        let editingCapability = store.largeFileEditingCapability(for: liveBuffer)
        guard let fileSizeBytes = liveBuffer.fileSizeBytes else {
            return editingCapability.status
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let total = formatter.string(fromByteCount: fileSizeBytes)
        let start = liveBuffer.largeFilePreviewStartOffsetBytes ?? 0
        let count = Int64(liveBuffer.largeFilePreviewByteCount ?? EditorStore.largeFilePreviewByteLimit(for: liveBuffer.language))
        let end = min(fileSizeBytes, start + count)
        guard fileSizeBytes > 0 else {
            return "\(editingCapability.status), \(total)"
        }

        return "\(editingCapability.status), virtual \(total), chunk \(formatter.string(fromByteCount: start))-\(formatter.string(fromByteCount: end))"
    }
}

enum StatusBarDensity {
    case regular
    case compact
    case minimal

    init(width: CGFloat) {
        if width < 430 {
            self = .minimal
        } else if width < 760 {
            self = .compact
        } else {
            self = .regular
        }
    }

    var spacing: CGFloat {
        switch self {
        case .regular: 9
        case .compact: 6
        case .minimal: 4
        }
    }

    var languageWidth: CGFloat {
        switch self {
        case .regular: 118
        case .compact: 82
        case .minimal: 24
        }
    }

    var showsLanguageText: Bool {
        self != .minimal
    }

    var showsPath: Bool {
        self != .minimal
    }

    var pathMinWidth: CGFloat {
        self == .regular ? 60 : 44
    }

    var pathMaxWidth: CGFloat {
        self == .regular ? 340 : 150
    }

    var tagMaxWidth: CGFloat {
        self == .regular ? 180 : 90
    }

    var showsStats: Bool {
        self == .regular
    }

    var showsSaveText: Bool {
        self != .minimal
    }

    var showsLargeFileControls: Bool {
        self != .minimal
    }

    var largeFileSearchStatusWidth: CGFloat {
        switch self {
        case .regular: 220
        case .compact: 120
        case .minimal: 0
        }
    }

    var pinnedMacroButtonLimit: Int {
        switch self {
        case .regular: 3
        case .compact: 1
        case .minimal: 0
        }
    }

    var showsPinnedMacroTitles: Bool {
        self == .regular
    }
}

private struct StatusIconButton: View {
    let systemName: String
    let isActive: Bool
    var isEnabled = true
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 20)
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundStyle)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(isActive ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        }
        .help(help)
        .disabled(!isEnabled)
        .fixedSize()
    }

    private var foregroundStyle: Color {
        if !isEnabled {
            return Color(nsColor: .tertiaryLabelColor)
        }

        return isActive ? .accentColor : Color(nsColor: .secondaryLabelColor)
    }
}

private struct StatusMacroButton: View {
    let button: PinnedMacroButton
    let showsTitle: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: button.systemName)
                    .font(.system(size: 11, weight: .semibold))
                if showsTitle {
                    Text(button.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: showsTitle ? 86 : 22, height: 20)
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.accentColor.opacity(0.30), lineWidth: 1)
        }
        .help(button.help)
        .fixedSize()
    }
}
