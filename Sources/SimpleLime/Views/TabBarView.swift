import AppKit
import SwiftUI

struct TabBarView: NSViewRepresentable {
    @ObservedObject var store: EditorStore
    let isFullScreen: Bool

    func makeNSView(context: Context) -> TabBarControl {
        TabBarControl()
    }

    func updateNSView(_ nsView: TabBarControl, context: Context) {
        nsView.configure(store: store, isFullScreen: isFullScreen)
    }
}

@MainActor
final class TabBarControl: NSView, NSDraggingSource {
    private static let tabPasteboardType = NSPasteboard.PasteboardType("com.whitehappypony.simplelime.tab")
    private static let tabPayloadPrefix = "simplelime-tab"

    private weak var store: EditorStore?
    private var buffers: [EditorBuffer] = []
    private var selectedBufferID: UUID?
    private var windowGroupID: UUID?
    private var leadingInset: CGFloat = 80
    private var scrollOffset: CGFloat = 0
    private var tabLayouts: [TabLayout] = []
    private var mouseDownState: MouseDownState?
    private var closeHoverID: UUID?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([Self.tabPasteboardType])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        registerForDraggedTypes([Self.tabPasteboardType])
    }

    func configure(store: EditorStore, isFullScreen: Bool) {
        self.store = store
        buffers = store.buffers
        selectedBufferID = store.selectedBufferID
        windowGroupID = store.windowGroupID
        leadingInset = isFullScreen ? 0 : 80
        clampScrollOffset()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        drawLeadingArea()
        drawTabs()
        drawPlusButton()
        drawBottomDivider()
    }

    override func layout() {
        super.layout()
        clampScrollOffset()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()

        let point = convert(event.locationInWindow, from: nil)
        switch hit(at: point) {
        case .leadingArea, .empty:
            window?.performDrag(with: event)
        case .plus:
            mouseDownState = MouseDownState(hit: .plus, startPoint: point, event: event)
        case .close(let id):
            mouseDownState = MouseDownState(hit: .close(id), startPoint: point, event: event)
        case .tab(let id):
            store?.select(id)
            mouseDownState = MouseDownState(hit: .tab(id), startPoint: point, event: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state = mouseDownState,
              case .tab(let id) = state.hit,
              let layout = tabLayouts.first(where: { $0.id == id }),
              dragDistance(from: state.startPoint, to: convert(event.locationInWindow, from: nil)) > 4 else {
            return
        }

        mouseDownState = nil
        beginTabDrag(id: id, layout: layout, event: state.event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let state = mouseDownState else { return }
        mouseDownState = nil

        let point = convert(event.locationInWindow, from: nil)
        switch state.hit {
        case .plus where hit(at: point) == .plus:
            store?.newScratch()
        case .plus:
            break
        case .close(let id):
            if hit(at: point) == .close(id) {
                store?.closeBuffer(id: id)
            }
        case .tab(let id):
            store?.select(id)
        case .leadingArea, .empty:
            break
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateCloseHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        if closeHoverID != nil {
            closeHoverID = nil
            needsDisplay = true
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY
        let delta = horizontal != 0 ? horizontal : vertical

        guard delta != 0, maxScrollOffset > 0 else {
            super.scrollWheel(with: event)
            return
        }

        scrollOffset = min(max(scrollOffset + delta, 0), maxScrollOffset)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
                owner: self
            )
        )
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let parsed = parseTabPayload(from: sender.draggingPasteboard),
              parsed.groupID != windowGroupID else {
            return false
        }

        store?.moveTabFromGroup(parsed.groupID, bufferID: parsed.bufferID)
        return true
    }

    private func beginTabDrag(id: UUID, layout: TabLayout, event: NSEvent) {
        guard let payload = tabPayload(bufferID: id) else { return }

        let item = NSPasteboardItem()
        item.setString(payload, forType: Self.tabPasteboardType)

        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(layout.frame, contents: dragImage(for: layout))

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard let parsed = parseTabPayload(from: sender.draggingPasteboard),
              parsed.groupID != windowGroupID else {
            return []
        }

        return .move
    }

    private func tabPayload(bufferID: UUID) -> String? {
        guard let windowGroupID else { return nil }
        return "\(Self.tabPayloadPrefix):\(windowGroupID.uuidString):\(bufferID.uuidString)"
    }

    private func parseTabPayload(from pasteboard: NSPasteboard) -> (groupID: UUID, bufferID: UUID)? {
        guard let payload = pasteboard.string(forType: Self.tabPasteboardType) else {
            return nil
        }

        let parts = payload.split(separator: ":").map(String.init)
        guard parts.count == 3,
              parts[0] == Self.tabPayloadPrefix,
              let groupID = UUID(uuidString: parts[1]),
              let bufferID = UUID(uuidString: parts[2]) else {
            return nil
        }

        return (groupID, bufferID)
    }

    private func dragImage(for layout: TabLayout) -> NSImage {
        let image = NSImage(size: layout.frame.size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        drawTab(layout: layout, in: NSRect(origin: .zero, size: layout.frame.size), isDragging: true)
        image.unlockFocus()
        return image
    }

    private func drawLeadingArea() {
        guard leadingInset > 0 else { return }

        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: leadingInset, height: bounds.height).fill()
        drawVerticalDivider(at: leadingInset)
    }

    private func drawTabs() {
        rebuildLayouts()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: tabsClipRect).addClip()

        for layout in tabLayouts where layout.frame.intersects(tabsClipRect) {
            drawTab(layout: layout, in: layout.frame, isDragging: false)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawTab(layout: TabLayout, in frame: NSRect, isDragging: Bool) {
        guard let buffer = buffers.first(where: { $0.id == layout.id }) else { return }

        let selected = buffer.id == selectedBufferID
        if selected || isDragging {
            NSColor.windowBackgroundColor.blended(withFraction: 0.18, of: .selectedControlColor)?.setFill()
            frame.fill()
        }

        if selected {
            NSColor.controlAccentColor.setFill()
            NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: 2).fill()
        }

        let titleFont = NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let titleRect = NSRect(
            x: frame.minX + 12,
            y: frame.minY + 11,
            width: max(0, frame.width - 52 - (buffer.isDirty ? 11 : 0)),
            height: 17
        )
        let titleColor: NSColor = selected ? .labelColor : .secondaryLabelColor
        buffer.displayTitle.draw(
            in: titleRect,
            withAttributes: [
                .font: titleFont,
                .foregroundColor: titleColor,
                .paragraphStyle: paragraph
            ]
        )

        if buffer.isDirty {
            NSColor.secondaryLabelColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: titleRect.maxX + 8, y: frame.minY + 16, width: 5, height: 5)).fill()
        }

        drawCloseIcon(in: closeRect(in: frame), highlighted: closeHoverID == buffer.id)
        drawVerticalDivider(at: frame.maxX)
    }

    private func drawCloseIcon(in rect: NSRect, highlighted: Bool) {
        if highlighted {
            NSColor.controlColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        }

        NSColor.secondaryLabelColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: rect.minX + 5.5, y: rect.minY + 5.5))
        path.line(to: NSPoint(x: rect.maxX - 5.5, y: rect.maxY - 5.5))
        path.move(to: NSPoint(x: rect.maxX - 5.5, y: rect.minY + 5.5))
        path.line(to: NSPoint(x: rect.minX + 5.5, y: rect.maxY - 5.5))
        path.stroke()
    }

    private func drawPlusButton() {
        drawVerticalDivider(at: plusRect.minX)

        NSColor.secondaryLabelColor.setStroke()
        let center = NSPoint(x: plusRect.midX, y: plusRect.midY)
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: center.x - 6, y: center.y))
        path.line(to: NSPoint(x: center.x + 6, y: center.y))
        path.move(to: NSPoint(x: center.x, y: center.y - 6))
        path.line(to: NSPoint(x: center.x, y: center.y + 6))
        path.stroke()
    }

    private func drawBottomDivider() {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    private func drawVerticalDivider(at x: CGFloat) {
        NSColor.separatorColor.setFill()
        NSRect(x: floor(x), y: 0, width: 1, height: bounds.height).fill()
    }

    private func updateCloseHover(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let nextID: UUID?
        if case .close(let id) = hit(at: point) {
            nextID = id
        } else {
            nextID = nil
        }

        if nextID != closeHoverID {
            closeHoverID = nextID
            needsDisplay = true
        }
    }

    private func hit(at point: NSPoint) -> Hit {
        rebuildLayouts()

        if plusRect.contains(point) {
            return .plus
        }

        if leadingInset > 0, point.x < leadingInset {
            return .leadingArea
        }

        for layout in tabLayouts where layout.frame.contains(point) {
            if layout.closeRect.contains(point) {
                return .close(layout.id)
            }
            return .tab(layout.id)
        }

        return .empty
    }

    private func rebuildLayouts() {
        clampScrollOffset()

        var x = tabsClipRect.minX - scrollOffset
        tabLayouts = buffers.map { buffer in
            let width = tabWidth(for: buffer)
            let frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
            x += width
            return TabLayout(
                id: buffer.id,
                frame: frame,
                closeRect: closeRect(in: frame)
            )
        }
    }

    private func closeRect(in frame: NSRect) -> NSRect {
        NSRect(x: frame.maxX - 29, y: 10, width: 18, height: 18)
    }

    private func tabWidth(for buffer: EditorBuffer) -> CGFloat {
        let titleWidth = ceil(
            buffer.displayTitle.size(
                withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .regular)]
            ).width
        )
        let dirtyWidth: CGFloat = buffer.isDirty ? 11 : 0
        return min(max(titleWidth + dirtyWidth + 58, 130), 230)
    }

    private func clampScrollOffset() {
        scrollOffset = min(max(scrollOffset, 0), maxScrollOffset)
    }

    private var plusRect: NSRect {
        NSRect(x: max(0, bounds.width - 31), y: 0, width: 31, height: bounds.height)
    }

    private var tabsClipRect: NSRect {
        let minX = leadingInset + (leadingInset > 0 ? 1 : 0)
        return NSRect(
            x: minX,
            y: 0,
            width: max(0, plusRect.minX - minX),
            height: bounds.height
        )
    }

    private var maxScrollOffset: CGFloat {
        max(0, buffers.reduce(CGFloat(0)) { $0 + tabWidth(for: $1) } - tabsClipRect.width)
    }

    private func dragDistance(from start: NSPoint, to end: NSPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}

private struct TabLayout {
    let id: UUID
    let frame: NSRect
    let closeRect: NSRect
}

private struct MouseDownState {
    let hit: Hit
    let startPoint: NSPoint
    let event: NSEvent
}

private enum Hit: Equatable {
    case leadingArea
    case empty
    case plus
    case tab(UUID)
    case close(UUID)
}
