import AppKit
import SwiftUI

struct WhiteboardView: View {
    @Binding var text: String
    @State private var selectedTool: WhiteboardTool = .pen
    @State private var selectedInk: WhiteboardInk = .blue
    @AppStorage(WhiteboardConfiguration.stickyFillDefaultsKey) private var selectedFillRawValue = WhiteboardConfiguration.defaultStickyFill.rawValue
    @State private var selectedShape: WhiteboardShapeKind = .rectangle
    @State private var lineWidth: Double = 4
    @AppStorage(WhiteboardConfiguration.connectorArrowsDefaultsKey) private var connectorHasArrow = WhiteboardConfiguration.defaultConnectorArrows
    @AppStorage(WhiteboardConfiguration.connectorRoutingDefaultsKey) private var connectorRoutingRawValue = WhiteboardConfiguration.defaultConnectorRouting.rawValue
    @AppStorage(WhiteboardConfiguration.showsGridDefaultsKey) private var showsGrid = WhiteboardConfiguration.defaultShowsGrid
    @AppStorage(WhiteboardConfiguration.gridSpacingDefaultsKey) private var gridSpacing = WhiteboardConfiguration.defaultGridSpacing
    @State private var zoom: CGFloat = 1
    @State private var activeStroke: WhiteboardStroke?
    @State private var activeItem: WhiteboardItem?
    @State private var dragStart: WhiteboardPoint?
    @State private var dragStartConnection: WhiteboardConnectionEndpoint?
    @State private var moveDragStart: WhiteboardPoint?
    @State private var moveDragDocument: WhiteboardDocument?
    @State private var moveDragSelectionIDs: Set<UUID> = []
    @State private var selectionDragStart: WhiteboardPoint?
    @State private var activeSelectionRect: WhiteboardRect?
    @State private var selectedItemID: UUID?
    @State private var selectedItemIDs: Set<UUID> = []

    private let canvasSize = WhiteboardExportService.defaultCanvasSize

    private var document: WhiteboardDocument {
        WhiteboardDocument.decode(from: text)
    }

    private var selectedFill: WhiteboardFill {
        WhiteboardConfiguration.stickyFill(rawValue: selectedFillRawValue)
    }

    private var connectorRouting: WhiteboardConnectorRouting {
        WhiteboardConfiguration.connectorRouting(rawValue: connectorRoutingRawValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            drawingSurface
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(WhiteboardTool.primaryTools) { tool in
                toolButton(tool)
            }

            Divider()
                .frame(height: 22)

            ForEach(WhiteboardInk.allCases) { ink in
                Button {
                    selectedInk = ink
                } label: {
                    Circle()
                        .fill(color(for: ink))
                        .frame(width: 16, height: 16)
                        .overlay {
                            Circle()
                                .stroke(
                                    selectedInk == ink ? Color.accentColor : Color.secondary.opacity(0.35),
                                    lineWidth: selectedInk == ink ? 3 : 1
                                )
                        }
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(ink.displayName)
            }

            Menu {
                ForEach(WhiteboardFill.allCases) { fill in
                    Button(fill.rawValue.capitalized) {
                        selectedFillRawValue = fill.rawValue
                    }
                }
            } label: {
                RoundedRectangle(cornerRadius: 5)
                    .fill(fillColor(for: selectedFill))
                    .frame(width: 24, height: 20)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    }
            }
            .menuStyle(.borderlessButton)
            .help("Fill color")

            Divider()
                .frame(height: 22)

            Image(systemName: "line.diagonal")
                .foregroundStyle(.secondary)
            Slider(value: $lineWidth, in: 1...18, step: 1)
                .frame(width: 100)
                .help("Stroke width")

            Toggle(isOn: $connectorHasArrow) {
                Image(systemName: "arrow.right")
            }
            .toggleStyle(.button)
            .help(connectorHasArrow ? "Connector arrows enabled" : "Connector arrows disabled")

            Menu {
                ForEach(WhiteboardConnectorRouting.allCases) { routing in
                    Button(routing.displayName) {
                        connectorRoutingRawValue = routing.rawValue
                    }
                }
            } label: {
                Image(systemName: connectorRouting.systemName)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .help("Connector routing")

            Spacer()

            Button {
                groupSelectedItems()
            } label: {
                Image(systemName: "rectangle.3.group")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(selectedGroupableIDs.count < 2)
            .help("Group selected items")

            Button {
                ungroupSelectedItem()
            } label: {
                Image(systemName: "rectangle.stack.badge.minus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(selectedGroupItem == nil)
            .help("Ungroup selected group")

            Menu {
                ForEach(WhiteboardGroupAlignment.allCases) { alignment in
                    Button {
                        alignSelectedGroupMembers(alignment)
                    } label: {
                        Label(alignment.displayName, systemImage: alignment.systemName)
                    }
                }
            } label: {
                Image(systemName: "align.horizontal.left")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .disabled(selectedGroupItem == nil)
            .help("Align selected group members")

            Button {
                editSelectedText()
            } label: {
                Image(systemName: "character.cursor.ibeam")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(selectedTextItem == nil)
            .help("Edit selected text")

            Button {
                duplicateSelectedItem()
            } label: {
                Image(systemName: "plus.square.on.square")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(selectedItemID == nil)
            .help("Duplicate selected item")

            Button {
                zoom = max(0.5, zoom - 0.1)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Zoom out")

            Text("\(Int((zoom * 100).rounded()))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 42)

            Button {
                zoom = min(2.5, zoom + 0.1)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Zoom in")

            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(document.renderItems.isEmpty)
            .help("Undo item")

            Button {
                clear()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(document.renderItems.isEmpty)
            .help("Clear board")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var drawingSurface: some View {
        ScrollView([.horizontal, .vertical]) {
            GeometryReader { proxy in
                Canvas { context, size in
                    if showsGrid {
                        drawGrid(in: &context, size: size)
                    }
                    for item in document.renderItems {
                        draw(item, in: &context, size: size, allItems: document.renderItems)
                    }
                    if let activeStroke {
                        draw(.stroke(activeStroke), in: &context, size: size, allItems: document.renderItems)
                    }
                    if let activeItem {
                        draw(activeItem, in: &context, size: size, allItems: document.renderItems)
                    }
                    if let activeSelectionRect {
                        drawSelectionMarquee(activeSelectionRect, in: &context, size: size)
                    }
                    drawConnectionAnchors(in: &context, size: size)
                    drawSelection(in: &context, size: size, allItems: document.renderItems)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDragChanged(value, canvasSize: proxy.size)
                        }
                        .onEnded { value in
                            handleDragEnded(value, canvasSize: proxy.size)
                        }
                )
            }
            .frame(width: canvasSize.width * zoom, height: canvasSize.height * zoom)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                Rectangle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .padding(24)
        }
    }

    private var selectedTextItem: WhiteboardItem? {
        guard let selectedItemID else { return nil }
        return document.renderItems.first {
            $0.id == selectedItemID && [.sticky, .shape, .text, .group].contains($0.kind)
        }
    }

    private var selectedGroupItem: WhiteboardItem? {
        guard let selectedItemID else { return nil }
        return document.renderItems.first {
            $0.id == selectedItemID && $0.kind == .group
        }
    }

    private var selectedIDs: Set<UUID> {
        var ids = selectedItemIDs
        if let selectedItemID {
            ids.insert(selectedItemID)
        }
        return ids
    }

    private var selectedGroupableIDs: Set<UUID> {
        let itemIDs = Set(document.renderItems.filter { $0.kind != .group }.map(\.id))
        return selectedIDs.intersection(itemIDs)
    }

    private func toolButton(_ tool: WhiteboardTool) -> some View {
        Button {
            selectedTool = tool
            if let shape = tool.shape {
                selectedShape = shape
            }
        } label: {
            Image(systemName: tool.systemName)
                .frame(width: 24, height: 24)
                .foregroundStyle(selectedTool == tool ? Color.accentColor : Color.secondary)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selectedTool == tool ? Color.accentColor.opacity(0.14) : Color.clear)
                }
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }

    private func handleDragChanged(_ value: DragGesture.Value, canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let point = normalizedPoint(value.location, canvasSize: canvasSize)

        switch selectedTool {
        case .select:
            handleMoveChanged(to: point)
        case .pen:
            appendPoint(point)
        case .sticky, .text, .rectangle, .ellipse, .diamond, .connector:
            if dragStart == nil {
                dragStart = point
                dragStartConnection = selectedTool == .connector ? connectionEndpoint(at: point, canvasSize: canvasSize) : nil
            }
            activeItem = previewItem(from: dragStart ?? point, to: point, canvasSize: canvasSize)
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, canvasSize: CGSize) {
        let point = normalizedPoint(value.location, canvasSize: canvasSize)
        switch selectedTool {
        case .select:
            handleMoveEnded(at: point)
        case .pen:
            appendPoint(point)
            commitActiveStroke()
        case .sticky, .text, .rectangle, .ellipse, .diamond, .connector:
            if dragStart == nil {
                dragStart = point
                dragStartConnection = selectedTool == .connector ? connectionEndpoint(at: point, canvasSize: canvasSize) : nil
            }
            activeItem = previewItem(from: dragStart ?? point, to: point, canvasSize: canvasSize)
            commitActiveItem()
        }
    }

    private func handleMoveChanged(to point: WhiteboardPoint) {
        if moveDragStart == nil {
            guard let itemID = hitTest(point) else {
                if selectionDragStart == nil {
                    selectionDragStart = point
                    moveDragDocument = document
                    clearSelection()
                }
                activeSelectionRect = selectionRect(from: selectionDragStart ?? point, to: point)
                return
            }
            if !selectedIDs.contains(itemID) {
                setSelection([itemID], primary: itemID)
            }
            moveDragStart = point
            moveDragDocument = document
            moveDragSelectionIDs = selectedIDs.isEmpty ? [itemID] : selectedIDs
        }

        guard !moveDragSelectionIDs.isEmpty,
              let moveDragStart,
              let moveDragDocument else {
            return
        }

        let delta = WhiteboardPoint(x: point.x - moveDragStart.x, y: point.y - moveDragStart.y)
        text = moveDragDocument.movingItems(ids: moveDragSelectionIDs, by: delta).encodedText()
    }

    private func handleMoveEnded(at point: WhiteboardPoint) {
        if let selectionDragStart {
            let rect = selectionRect(from: selectionDragStart, to: point)
            let ids = selectableItemIDs(intersecting: rect)
            setSelection(ids, primary: ids.first)
            self.selectionDragStart = nil
            activeSelectionRect = nil
            moveDragDocument = nil
            moveDragSelectionIDs = []
            return
        }

        if moveDragStart == nil {
            if let hitID = hitTest(point) {
                setSelection([hitID], primary: hitID)
            } else {
                clearSelection()
            }
        }
        moveDragStart = nil
        moveDragDocument = nil
        moveDragSelectionIDs = []
    }

    private func previewItem(from start: WhiteboardPoint, to end: WhiteboardPoint, canvasSize: CGSize) -> WhiteboardItem {
        if selectedTool == .connector {
            return .connector(
                from: start,
                to: end,
                ink: selectedInk,
                endArrow: connectorHasArrow,
                routing: connectorRouting,
                startConnection: dragStartConnection,
                endConnection: connectionEndpoint(at: end, canvasSize: canvasSize)
            )
        }

        let rect = rect(from: start, to: end)
        switch selectedTool {
        case .sticky:
            return .sticky(rect: rect, text: "", fill: selectedFill == .clear ? .yellow : selectedFill)
        case .text:
            return .text(rect: rect, text: "Text", ink: selectedInk)
        case .rectangle, .ellipse, .diamond:
            return .shape(selectedShape, rect: rect, text: "", fill: selectedFill, ink: selectedInk)
        case .select, .pen, .connector:
            return .sticky(rect: rect, text: "")
        }
    }

    private func appendPoint(_ point: WhiteboardPoint) {
        if activeStroke == nil {
            activeStroke = WhiteboardStroke(
                ink: selectedInk,
                lineWidth: lineWidth,
                points: [point]
            )
        } else if activeStroke?.points.last != point {
            activeStroke?.points.append(point)
        }
    }

    private func commitActiveStroke() {
        guard let stroke = activeStroke?.normalized(),
              !stroke.points.isEmpty else {
            activeStroke = nil
            return
        }

        text = document.appending(stroke).encodedText()
        activeStroke = nil
    }

    private func commitActiveItem() {
        guard var item = activeItem?.normalized(),
              item.isRenderable else {
            activeItem = nil
            dragStart = nil
            dragStartConnection = nil
            return
        }

        if item.kind == .text {
            guard let next = promptText(title: "Text", defaultValue: item.text) else {
                activeItem = nil
                dragStart = nil
                dragStartConnection = nil
                return
            }
            item.text = next
        }

        text = document.appending(item).encodedText()
        setSelection([item.id], primary: item.id)
        selectedTool = .select
        activeItem = nil
        dragStart = nil
        dragStartConnection = nil
    }

    private func undo() {
        clearSelection()
        text = document.removingLastItem().encodedText()
    }

    private func clear() {
        clearSelection()
        text = WhiteboardDocument.empty.encodedText()
    }

    private func groupSelectedItems() {
        let ids = selectedGroupableIDs
        guard ids.count > 1 else { return }
        let grouped = document.groupingItems(ids: ids)
        text = grouped.encodedText()
        if let group = grouped.renderItems.last(where: { $0.kind == .group }) {
            setSelection([group.id], primary: group.id)
        } else {
            clearSelection()
        }
        selectedTool = .select
    }

    private func editSelectedText() {
        guard let selected = selectedTextItem else { return }
        guard let next = promptText(title: "Edit Text", defaultValue: selected.text) else { return }
        var copy = document
        copy.items = copy.renderItems.map { item in
            guard item.id == selected.id else { return item }
            var edited = item
            edited.text = next
            return edited
        }
        text = copy.encodedText()
    }

    private func duplicateSelectedItem() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        let result = document.duplicatingItems(ids: ids)
        text = result.document.encodedText()
        let duplicatedIDs = Set(result.duplicatedIDs.values)
        if duplicatedIDs.isEmpty {
            setSelection(ids, primary: selectedItemID)
        } else {
            setSelection(duplicatedIDs, primary: result.duplicatedIDs[selectedItemID ?? ids.first!])
        }
        selectedTool = .select
    }

    private func ungroupSelectedItem() {
        guard let selectedGroupItem else { return }
        text = document.ungroupingItem(id: selectedGroupItem.id).encodedText()
        clearSelection()
        selectedTool = .select
    }

    private func alignSelectedGroupMembers(_ alignment: WhiteboardGroupAlignment) {
        guard let selectedGroupItem else { return }
        text = document.aligningGroupMembers(groupID: selectedGroupItem.id, alignment: alignment).encodedText()
        setSelection([selectedGroupItem.id], primary: selectedGroupItem.id)
        selectedTool = .select
    }

    private func connectionEndpoint(at point: WhiteboardPoint, canvasSize: CGSize) -> WhiteboardConnectionEndpoint? {
        let hitRadius = max(0.008, 16 / Double(max(min(canvasSize.width, canvasSize.height), 1)))
        return document.renderItems.reversed().compactMap { item in
            guard [.sticky, .shape, .text, .group].contains(item.kind),
                  let bounds = item.rect?.clamped() else {
                return nil
            }

            if let anchor = connectorAnchorHit(at: point, on: bounds, hitRadius: hitRadius) {
                return WhiteboardConnectionEndpoint(itemID: item.id, anchor: anchor)
            }

            let hitBounds = bounds.insetBy(dx: -0.012, dy: -0.012).clamped()
            let insideBounds = point.x >= bounds.x && point.x <= bounds.maxX && point.y >= bounds.y && point.y <= bounds.maxY
            let insideExpandedBounds = point.x >= hitBounds.x && point.x <= hitBounds.maxX && point.y >= hitBounds.y && point.y <= hitBounds.maxY
            guard insideBounds || insideExpandedBounds else { return nil }

            return WhiteboardConnectionEndpoint(itemID: item.id, anchor: WhiteboardGeometry.nearestAnchor(to: point, on: bounds))
        }.first
    }

    private func connectorAnchorHit(at point: WhiteboardPoint, on bounds: WhiteboardRect, hitRadius: Double) -> WhiteboardConnectorAnchor? {
        WhiteboardGeometry.connectorAnchors
            .map { anchor in
                (anchor: anchor, distance: point.distanceSquared(to: WhiteboardGeometry.anchorPoint(anchor, on: bounds)))
            }
            .filter { $0.distance <= hitRadius * hitRadius }
            .min { $0.distance < $1.distance }?
            .anchor
    }

    private func hitTest(_ point: WhiteboardPoint) -> UUID? {
        document.renderItems.reversed().first { item in
            guard let bounds = WhiteboardGeometry.itemBounds(item)?.insetBy(dx: -0.015, dy: -0.015).clamped() else {
                return false
            }
            return point.x >= bounds.x && point.x <= bounds.maxX && point.y >= bounds.y && point.y <= bounds.maxY
        }?.id
    }

    private func setSelection(_ ids: Set<UUID>, primary: UUID?) {
        selectedItemIDs = ids
        selectedItemID = primary.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
    }

    private func clearSelection() {
        selectedItemID = nil
        selectedItemIDs = []
    }

    private func selectableItemIDs(intersecting rect: WhiteboardRect) -> Set<UUID> {
        let normalizedRect = rect.clamped()
        return Set(document.renderItems.compactMap { item in
            guard item.kind != .group,
                  let bounds = WhiteboardGeometry.itemBounds(item),
                  normalizedRect.intersects(bounds) else {
                return nil
            }
            return item.id
        })
    }

    private func promptText(title: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedPoint(_ location: CGPoint, canvasSize: CGSize) -> WhiteboardPoint {
        WhiteboardPoint(
            x: Double(location.x / max(canvasSize.width, 1)),
            y: Double(location.y / max(canvasSize.height, 1))
        ).clamped()
    }

    private func rect(from start: WhiteboardPoint, to end: WhiteboardPoint) -> WhiteboardRect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = max(abs(end.x - start.x), 0.08)
        let height = max(abs(end.y - start.y), selectedTool == .text ? 0.05 : 0.08)
        return WhiteboardRect(x: minX, y: minY, width: width, height: height).clamped()
    }

    private func selectionRect(from start: WhiteboardPoint, to end: WhiteboardPoint) -> WhiteboardRect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        return WhiteboardRect(x: minX, y: minY, width: width, height: height).clamped()
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let minorStep = CGFloat(WhiteboardConfiguration.clampedGridSpacing(gridSpacing)) * zoom
        let majorStep = minorStep * 5
        var minorGrid = Path()
        var x: CGFloat = 0
        while x <= size.width {
            minorGrid.move(to: CGPoint(x: x, y: 0))
            minorGrid.addLine(to: CGPoint(x: x, y: size.height))
            x += minorStep
        }
        var y: CGFloat = 0
        while y <= size.height {
            minorGrid.move(to: CGPoint(x: 0, y: y))
            minorGrid.addLine(to: CGPoint(x: size.width, y: y))
            y += minorStep
        }
        context.stroke(minorGrid, with: .color(Color(nsColor: .gridColor).opacity(0.32)), lineWidth: 1)

        var majorGrid = Path()
        x = 0
        while x <= size.width {
            majorGrid.move(to: CGPoint(x: x, y: 0))
            majorGrid.addLine(to: CGPoint(x: x, y: size.height))
            x += majorStep
        }
        y = 0
        while y <= size.height {
            majorGrid.move(to: CGPoint(x: 0, y: y))
            majorGrid.addLine(to: CGPoint(x: size.width, y: y))
            y += majorStep
        }
        context.stroke(majorGrid, with: .color(Color(nsColor: .gridColor).opacity(0.55)), lineWidth: 1)
    }

    private func draw(_ item: WhiteboardItem, in context: inout GraphicsContext, size: CGSize, allItems: [WhiteboardItem]) {
        switch item.kind {
        case .stroke:
            drawStroke(item, in: &context, size: size)
        case .connector:
            drawConnector(item, in: &context, size: size, allItems: allItems)
        case .sticky:
            drawBox(item, in: &context, size: size, sticky: true)
        case .shape:
            drawShape(item, in: &context, size: size)
        case .text:
            drawText(item.text, in: rect(item.rect, size: size), color: color(for: item.ink), fontSize: 18 * zoom, context: &context)
        case .group:
            drawGroup(item, in: &context, size: size)
        }
    }

    private func drawStroke(_ item: WhiteboardItem, in context: inout GraphicsContext, size: CGSize) {
        guard let first = item.points.first else { return }
        var path = Path()
        path.move(to: point(first, size: size))

        if item.points.count == 1 {
            let center = point(first, size: size)
            let diameter = CGFloat(item.lineWidth)
            path.addEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
            context.fill(path, with: .color(color(for: item.ink)))
            return
        }

        item.points.dropFirst().forEach { path.addLine(to: point($0, size: size)) }
        context.stroke(path, with: .color(color(for: item.ink)), style: StrokeStyle(lineWidth: CGFloat(item.lineWidth) * zoom, lineCap: .round, lineJoin: .round))
    }

    private func drawConnector(_ item: WhiteboardItem, in context: inout GraphicsContext, size: CGSize, allItems: [WhiteboardItem]) {
        let points = WhiteboardConnectorRouter.routedPoints(for: item, in: allItems, size: size)
        guard let start = points.first,
              let end = points.last,
              points.count >= 2 else {
            return
        }
        let bridges = WhiteboardConnectorRouter.bridges(for: item, routedPoints: points, in: allItems, size: size)
        let path = connectorPath(points: points, bridges: bridges)
        context.stroke(path, with: .color(color(for: item.ink)), style: StrokeStyle(lineWidth: CGFloat(item.lineWidth) * zoom, lineCap: .round))
        if item.startArrow, points.count > 1 {
            drawArrowHead(tip: start, tail: points[1], color: color(for: item.ink), in: &context)
        }
        if item.endArrow, points.count > 1 {
            drawArrowHead(tip: end, tail: points[points.count - 2], color: color(for: item.ink), in: &context)
        }
    }

    private func connectorPath(points: [CGPoint], bridges: [WhiteboardConnectorRouter.Bridge]) -> Path {
        var path = Path()
        let bridgeRadius = max(8, 9 * zoom)
        let cornerRadius = max(10, 14 * zoom)
        for command in WhiteboardConnectorRouter.pathCommands(
            points: points,
            bridges: bridges,
            bridgeRadius: bridgeRadius,
            cornerRadius: cornerRadius
        ) {
            switch command {
            case let .move(point):
                path.move(to: point)
            case let .line(point):
                path.addLine(to: point)
            case let .quadCurve(point, control):
                path.addQuadCurve(to: point, control: control)
            }
        }

        return path
    }

    private func drawBox(_ item: WhiteboardItem, in context: inout GraphicsContext, size: CGSize, sticky: Bool) {
        let frame = rect(item.rect, size: size)
        let path = Path(roundedRect: frame, cornerRadius: (sticky ? CGFloat(8) : CGFloat(6)) * zoom)
        context.fill(path, with: .color(fillColor(for: item.fill)))
        context.stroke(path, with: .color(.black.opacity(0.14)), lineWidth: 1)
        if !item.text.isEmpty {
            drawText(item.text, in: frame.insetBy(dx: CGFloat(12) * zoom, dy: CGFloat(10) * zoom), color: .black, fontSize: CGFloat(16) * zoom, context: &context)
        }
    }

    private func drawShape(_ item: WhiteboardItem, in context: inout GraphicsContext, size: CGSize) {
        let frame = rect(item.rect, size: size)
        let path = shapePath(item.shape ?? .rectangle, rect: frame)
        context.fill(path, with: .color(fillColor(for: item.fill)))
        context.stroke(path, with: .color(color(for: item.ink)), style: StrokeStyle(lineWidth: CGFloat(item.lineWidth) * zoom))
        if !item.text.isEmpty {
            drawText(item.text, in: frame.insetBy(dx: CGFloat(10) * zoom, dy: CGFloat(10) * zoom), color: color(for: item.ink), fontSize: CGFloat(15) * zoom, context: &context)
        }
    }

    private func drawGroup(_ item: WhiteboardItem, in context: inout GraphicsContext, size: CGSize) {
        let frame = rect(item.rect, size: size)
        let path = Path(roundedRect: frame, cornerRadius: CGFloat(10) * zoom)
        context.stroke(
            path,
            with: .color(color(for: item.ink).opacity(0.78)),
            style: StrokeStyle(lineWidth: CGFloat(item.lineWidth) * zoom, dash: [CGFloat(8) * zoom, CGFloat(6) * zoom])
        )
        if !item.text.isEmpty {
            drawText(item.text, in: CGRect(x: frame.minX + CGFloat(10) * zoom, y: frame.minY + CGFloat(6) * zoom, width: frame.width - CGFloat(20) * zoom, height: CGFloat(24) * zoom), color: color(for: item.ink), fontSize: CGFloat(12) * zoom, context: &context)
        }
    }

    private func drawConnectionAnchors(in context: inout GraphicsContext, size: CGSize) {
        let selectedKind = selectedItemID.flatMap { id in
            document.renderItems.first(where: { $0.id == id })?.kind
        }
        let showsAnchorsForSelectedObject = selectedKind.map { [.sticky, .shape, .text, .group].contains($0) } ?? false
        guard selectedTool == .connector || showsAnchorsForSelectedObject else { return }

        for item in document.renderItems where [.sticky, .shape, .text, .group].contains(item.kind) {
            guard let bounds = item.rect?.clamped() else { continue }
            for anchor in WhiteboardGeometry.connectorAnchors {
                let anchorPoint = point(WhiteboardGeometry.anchorPoint(anchor, on: bounds), size: size)
                let radius = max(5, 5.5 * zoom)
                let rect = CGRect(
                    x: anchorPoint.x - radius,
                    y: anchorPoint.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                let circle = Path(ellipseIn: rect)
                context.fill(circle, with: .color(Color(nsColor: .textBackgroundColor)))
                context.stroke(
                    circle,
                    with: .color(selectedIDs.contains(item.id) ? .accentColor : .secondary.opacity(0.72)),
                    lineWidth: selectedIDs.contains(item.id) ? 2.2 : 1.6
                )
            }
        }
    }

    private func drawSelection(in context: inout GraphicsContext, size: CGSize, allItems: [WhiteboardItem]) {
        for item in document.renderItems where selectedIDs.contains(item.id) {
            guard let bounds = WhiteboardGeometry.itemBounds(item) else {
                continue
            }

            if item.kind == .connector {
                drawConnectorSelection(item, in: &context, size: size, allItems: allItems)
                continue
            }

            let frame = rect(bounds, size: size).insetBy(dx: -5, dy: -5)
            context.stroke(
                Path(roundedRect: frame, cornerRadius: CGFloat(8) * zoom),
                with: .color(.accentColor),
                style: StrokeStyle(lineWidth: 2, dash: [5, 4])
            )
        }
    }

    private func drawSelectionMarquee(_ rect: WhiteboardRect, in context: inout GraphicsContext, size: CGSize) {
        let frame = self.rect(rect, size: size)
        guard frame.width >= 2 || frame.height >= 2 else { return }
        let path = Path(roundedRect: frame, cornerRadius: CGFloat(6) * zoom)
        context.fill(path, with: .color(Color.accentColor.opacity(0.08)))
        context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    }

    private func drawConnectorSelection(_ item: WhiteboardItem, in context: inout GraphicsContext, size: CGSize, allItems: [WhiteboardItem]) {
        let points = WhiteboardConnectorRouter.routedPoints(for: item, in: allItems, size: size)
        guard let start = points.first,
              let end = points.last,
              points.count >= 2 else {
            return
        }

        let bridges = WhiteboardConnectorRouter.bridges(for: item, routedPoints: points, in: allItems, size: size)
        let path = connectorPath(points: points, bridges: bridges)
        context.stroke(
            path,
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: max(2.6, CGFloat(item.lineWidth) * zoom + 1.4), lineCap: .round, lineJoin: .round)
        )

        if item.startArrow, points.count > 1 {
            drawArrowHead(tip: start, tail: points[1], color: .accentColor, in: &context)
        }
        if item.endArrow, points.count > 1 {
            drawArrowHead(tip: end, tail: points[points.count - 2], color: .accentColor, in: &context)
        }

        drawConnectorHandle(at: start, endpoint: true, in: &context)
        drawConnectorHandle(at: end, endpoint: true, in: &context)

        for point in points.dropFirst().dropLast() {
            drawConnectorHandle(at: point, endpoint: false, in: &context)
        }

        if let midpoint = longestSegmentMidpoint(in: points) {
            drawConnectorHandle(at: midpoint, endpoint: false, in: &context)
        }
    }

    private func drawConnectorHandle(at point: CGPoint, endpoint: Bool, in context: inout GraphicsContext) {
        let radius = max(endpoint ? 5.5 : 4.0, (endpoint ? 5.5 : 4.0) * zoom)
        let frame = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let circle = Path(ellipseIn: frame)

        if endpoint {
            context.fill(circle, with: .color(Color(nsColor: .textBackgroundColor)))
            context.stroke(circle, with: .color(.accentColor), lineWidth: 2.2)
        } else {
            context.fill(circle, with: .color(.accentColor))
            context.stroke(circle, with: .color(Color(nsColor: .textBackgroundColor).opacity(0.95)), lineWidth: 1.2)
        }
    }

    private func longestSegmentMidpoint(in points: [CGPoint]) -> CGPoint? {
        zip(points, points.dropFirst())
            .map { start, end in
                (
                    length: hypot(end.x - start.x, end.y - start.y),
                    midpoint: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                )
            }
            .filter { $0.length >= 96 * zoom }
            .max { $0.length < $1.length }?
            .midpoint
    }

    private func drawArrowHead(tip: CGPoint, tail: CGPoint, color: Color, in context: inout GraphicsContext) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let length = CGFloat(14) * zoom
        let spread = CGFloat.pi / 7
        let left = CGPoint(x: tip.x - cos(angle - spread) * length, y: tip.y - sin(angle - spread) * length)
        let right = CGPoint(x: tip.x - cos(angle + spread) * length, y: tip.y - sin(angle + spread) * length)
        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    private func drawText(_ value: String, in rect: CGRect, color: Color, fontSize: CGFloat, context: inout GraphicsContext) {
        guard !value.isEmpty else { return }
        var resolved = context.resolve(Text(value).font(.system(size: max(9, fontSize), weight: .medium)))
        resolved.shading = .color(color)
        context.draw(resolved, in: rect)
    }

    private func shapePath(_ shape: WhiteboardShapeKind, rect: CGRect) -> Path {
        switch shape {
        case .rectangle:
            return Path(roundedRect: rect, cornerRadius: CGFloat(7) * zoom)
        case .ellipse:
            return Path(ellipseIn: rect)
        case .diamond:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        }
    }

    private func rect(_ rect: WhiteboardRect?, size: CGSize) -> CGRect {
        let resolved = (rect ?? .defaultBox).clamped()
        return CGRect(
            x: resolved.x * size.width,
            y: resolved.y * size.height,
            width: resolved.width * size.width,
            height: resolved.height * size.height
        )
    }

    private func point(_ point: WhiteboardPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func color(for ink: WhiteboardInk) -> Color {
        switch ink {
        case .black: .primary
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        }
    }

    private func fillColor(for fill: WhiteboardFill) -> Color {
        switch fill {
        case .clear: .clear
        case .white: .white
        case .yellow: Color(nsColor: .systemYellow).opacity(0.85)
        case .blue: .blue.opacity(0.16)
        case .green: .green.opacity(0.18)
        case .orange: .orange.opacity(0.22)
        case .red: .red.opacity(0.16)
        case .purple: .purple.opacity(0.16)
        }
    }
}

private enum WhiteboardTool: String, CaseIterable, Identifiable {
    case select
    case pen
    case sticky
    case text
    case rectangle
    case ellipse
    case diamond
    case connector

    static let primaryTools: [WhiteboardTool] = [
        .select, .pen, .sticky, .text, .rectangle, .ellipse, .diamond, .connector
    ]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .select: "Select"
        case .pen: "Pen"
        case .sticky: "Sticker"
        case .text: "Text"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .diamond: "Diamond"
        case .connector: "Connector"
        }
    }

    var systemName: String {
        switch self {
        case .select: "cursorarrow"
        case .pen: "pencil.tip"
        case .sticky: "note.text"
        case .text: "textformat"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .diamond: "diamond"
        case .connector: "arrow.right"
        }
    }

    var shape: WhiteboardShapeKind? {
        switch self {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .diamond: .diamond
        default: nil
        }
    }
}
