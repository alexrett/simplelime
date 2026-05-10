import SwiftUI

struct EditorWorkspaceView: View {
    @ObservedObject var store: EditorStore
    let buffer: EditorBuffer
    @State private var sourceVisibleLineRange: ClosedRange<Int> = 1...1

    var body: some View {
        VStack(spacing: 0) {
            if store.isAIPanelVisible {
                HSplitView {
                    mainEditorContent
                        .frame(minWidth: 180)
                    AIChatPanelView(store: store, buffer: buffer)
                }
            } else {
                mainEditorContent
            }

            StatusBarView(store: store, buffer: buffer)
        }
        .clipped()
    }

    private var mainEditorContent: some View {
        Group {
            if store.isOutlineVisible, buffer.language.isMarkdown {
                HSplitView {
                    MarkdownOutlineView(
                        text: buffer.text,
                        selectionRanges: buffer.selectionRanges,
                        onSelect: { heading in
                            store.jumpToHeading(heading)
                        }
                    )
                    .frame(minWidth: 170, idealWidth: 220, maxWidth: 320)

                    editorContent
                        .frame(minWidth: 180)
                }
            } else {
                editorContent
            }
        }
    }

    private var editorContent: some View {
        Group {
            if store.isPreviewVisible, buffer.language.isMarkdown {
                HSplitView {
                    editorPane
                        .frame(minWidth: 180)
                    MarkdownPreviewView(
                        text: buffer.text,
                        baseURL: buffer.filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
                    )
                        .frame(minWidth: 200)
                }
            } else {
                editorPane
            }
        }
    }

    private var editorPane: some View {
        HStack(spacing: 0) {
            editor
            if store.isMiniMapVisible, !store.isWysiwygModeEnabled {
                EditorMiniMapView(
                    text: buffer.text,
                    selectionRanges: buffer.selectionRanges,
                    visibleLineRange: sourceVisibleLineRange,
                    onSelectLine: { lineNumber in
                        store.jumpToLine(lineNumber)
                    }
                )
                .frame(width: 86)
            }
        }
    }

    private var editor: some View {
        Group {
            if buffer.language.isMarkdown, store.isWysiwygModeEnabled {
                MarkdownWYSIWYGEditorView(
                    text: textBinding,
                    selectionRanges: selectionBinding,
                    baseURL: buffer.filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() },
                    fontSize: store.fontSize,
                    typewriterModeEnabled: store.isTypewriterModeEnabled,
                    onShortcut: handleShortcut,
                    onRegisterEditorCommandHandler: { handler in
                        store.registerEditorCommandHandler(handler)
                    }
                )
            } else {
                CodeEditorView(
                    text: textBinding,
                    selectionRanges: selectionBinding,
                    language: store.buffers.first(where: { $0.id == buffer.id })?.language ?? buffer.language,
                    fontSize: store.fontSize,
                    wrapsLines: store.wrapsLines,
                    focusModeEnabled: store.isFocusModeEnabled,
                    typewriterModeEnabled: store.isTypewriterModeEnabled,
                    onShortcut: handleShortcut,
                    onVisibleLineRangeChange: { lineRange in
                        sourceVisibleLineRange = lineRange
                    },
                    onRegisterEditorCommandHandler: { handler in
                        store.registerEditorCommandHandler(handler)
                    }
                )
            }
        }
        .clipped()
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
        max(0, (height - contentHeight) / 2)
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

private struct MarkdownOutlineView: View {
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
        HStack(spacing: style.spacing) {
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
                        isActive: store.isPreviewVisible,
                        help: "Source with rendered preview"
                    ) {
                        store.showMarkdownPreviewMode()
                    }

                    StatusIconButton(
                        systemName: "doc.richtext",
                        isActive: store.isWysiwygModeEnabled,
                        help: "WYSIWYG Markdown mode"
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
            }

            StatusIconButton(
                systemName: "scope",
                isActive: store.isFocusModeEnabled,
                isEnabled: !store.isWysiwygModeEnabled,
                help: "Focus mode"
            ) {
                store.toggleFocusMode()
            }

            StatusIconButton(
                systemName: "map",
                isActive: store.isMiniMapVisible,
                isEnabled: !store.isWysiwygModeEnabled,
                help: store.isWysiwygModeEnabled ? "Minimap is available in source mode" : "Minimap (⌘⌥4)"
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

            if style.showsStats {
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

    var showsStats: Bool {
        self == .regular
    }

    var showsSaveText: Bool {
        self != .minimal
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
