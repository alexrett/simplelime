import CoreGraphics
import Foundation

struct WhiteboardDocument: Codable, Equatable {
    static let fileExtension = "sldraw"

    var version: Int
    var strokes: [WhiteboardStroke]
    var items: [WhiteboardItem]

    init(version: Int = 2, strokes: [WhiteboardStroke] = [], items: [WhiteboardItem] = []) {
        self.version = version
        self.strokes = strokes
        self.items = items
    }

    var isEmpty: Bool {
        strokes.isEmpty && items.isEmpty
    }

    var renderItems: [WhiteboardItem] {
        items.isEmpty ? strokes.map { WhiteboardItem.stroke($0) } : items
    }

    static var empty: WhiteboardDocument {
        WhiteboardDocument()
    }

    static func decode(from text: String) -> WhiteboardDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let document = try? JSONDecoder().decode(WhiteboardDocument.self, from: data) else {
            return .empty
        }

        return document.normalized()
    }

    func encodedText() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(normalized()),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"items":[],"strokes":[],"version":2}"#
        }

        return text + "\n"
    }

    func appending(_ stroke: WhiteboardStroke) -> WhiteboardDocument {
        var copy = self
        let normalizedStroke = stroke.normalized()
        copy.strokes.append(normalizedStroke)
        copy.items.append(.stroke(normalizedStroke))
        return copy.normalized()
    }

    func appending(_ item: WhiteboardItem) -> WhiteboardDocument {
        var copy = self
        let normalizedItem = item.normalized()
        if case .stroke = normalizedItem.kind,
           let stroke = normalizedItem.strokeValue {
            copy.strokes.append(stroke)
        }
        copy.items.append(normalizedItem)
        return copy.normalized()
    }

    func removingLastItem() -> WhiteboardDocument {
        guard !renderItems.isEmpty else { return self }
        var copy = self
        if !copy.items.isEmpty {
            let removed = copy.items.removeLast()
            if case .stroke = removed.kind,
               !copy.strokes.isEmpty {
                copy.strokes.removeLast()
            }
        } else if !copy.strokes.isEmpty {
            copy.strokes.removeLast()
        }
        return copy.normalized()
    }

    func removingLastStroke() -> WhiteboardDocument {
        removingLastItem()
    }

    func groupingAllItems(title: String = "Group") -> WhiteboardDocument {
        let members = renderItems.filter { $0.kind != .group }
        return groupingItems(ids: Set(members.map(\.id)), title: title)
    }

    func groupingItems(ids selectedIDs: Set<UUID>, title: String = "Group") -> WhiteboardDocument {
        let members = renderItems.filter { selectedIDs.contains($0.id) && $0.kind != .group }
        guard members.count > 1,
              let bounds = WhiteboardGeometry.bounds(for: members) else {
            return self
        }

        let expanded = bounds.insetBy(dx: -0.025, dy: -0.025).clamped()
        let group = WhiteboardItem(
            kind: .group,
            rect: expanded,
            text: title,
            fill: .clear,
            ink: .blue,
            lineWidth: 2,
            memberIDs: members.map(\.id)
        )
        return appending(group)
    }

    func movingItem(id: UUID, by delta: WhiteboardPoint) -> WhiteboardDocument {
        movingItems(ids: [id], by: delta)
    }

    func movingItems(ids selectedIDs: Set<UUID>, by delta: WhiteboardPoint) -> WhiteboardDocument {
        let itemsToRender = renderItems
        guard !selectedIDs.isEmpty else {
            return self
        }

        let idsToMove = selectedIDs.reduce(into: Set<UUID>()) { partial, selectedID in
            guard let target = itemsToRender.first(where: { $0.id == selectedID }) else { return }
            if target.kind == .group && !target.memberIDs.isEmpty {
                partial.formUnion(target.memberIDs)
                partial.insert(target.id)
            } else {
                partial.insert(target.id)
            }
        }
        guard !idsToMove.isEmpty else { return self }

        var copy = self
        copy.items = itemsToRender.map { item in
            idsToMove.contains(item.id) ? item.moved(by: delta) : item
        }
        copy.reflowGroupBounds()
        copy.syncLegacyStrokesFromItems()
        return copy.normalized()
    }

    func duplicatingItem(id: UUID, offset: WhiteboardPoint = WhiteboardPoint(x: 0.025, y: 0.025)) -> (document: WhiteboardDocument, duplicatedID: UUID?) {
        let result = duplicatingItems(ids: [id], offset: offset)
        return (result.document, result.duplicatedIDs[id])
    }

    func duplicatingItems(ids selectedIDs: Set<UUID>, offset: WhiteboardPoint = WhiteboardPoint(x: 0.025, y: 0.025)) -> (document: WhiteboardDocument, duplicatedIDs: [UUID: UUID]) {
        let itemsToRender = renderItems
        guard !selectedIDs.isEmpty else {
            return (self, [:])
        }

        let sourceIDSet = selectedIDs.reduce(into: Set<UUID>()) { partial, selectedID in
            guard let target = itemsToRender.first(where: { $0.id == selectedID }) else { return }
            if target.kind == .group && !target.memberIDs.isEmpty {
                partial.formUnion(target.memberIDs)
                partial.insert(target.id)
            } else {
                partial.insert(target.id)
            }
        }
        let sourceItems = itemsToRender.filter { sourceIDSet.contains($0.id) }
        guard !sourceItems.isEmpty else {
            return (self, [:])
        }

        let idMap = Dictionary(uniqueKeysWithValues: sourceItems.map { ($0.id, UUID()) })
        let duplicatedItems = sourceItems.map { $0.duplicated(idMap: idMap, offset: offset) }
        var copy = self
        copy.items = itemsToRender + duplicatedItems
        copy.reflowGroupBounds()
        copy.syncLegacyStrokesFromItems()
        return (copy.normalized(), idMap.filter { selectedIDs.contains($0.key) })
    }

    func ungroupingItem(id: UUID) -> WhiteboardDocument {
        let itemsToRender = renderItems
        guard itemsToRender.contains(where: { $0.id == id && $0.kind == .group }) else {
            return self
        }

        var copy = self
        copy.items = itemsToRender.filter { $0.id != id }
        copy.reflowGroupBounds()
        copy.syncLegacyStrokesFromItems()
        return copy.normalized()
    }

    func aligningGroupMembers(groupID: UUID, alignment: WhiteboardGroupAlignment) -> WhiteboardDocument {
        let itemsToRender = renderItems
        guard let group = itemsToRender.first(where: { $0.id == groupID && $0.kind == .group }),
              !group.memberIDs.isEmpty else {
            return self
        }

        let memberIDSet = Set(group.memberIDs)
        let alignableItems = itemsToRender.filter {
            memberIDSet.contains($0.id) && [.sticky, .shape, .text].contains($0.kind) && $0.rect != nil
        }
        guard alignableItems.count > 1,
              let bounds = WhiteboardGeometry.bounds(for: alignableItems) else {
            return self
        }

        let alignableIDs = Set(alignableItems.map(\.id))
        var copy = self
        copy.items = itemsToRender.map { item in
            guard alignableIDs.contains(item.id),
                  let rect = item.rect else {
                return item
            }

            let delta = alignment.delta(for: rect, within: bounds)
            return delta == WhiteboardPoint(x: 0, y: 0) ? item : item.moved(by: delta)
        }
        copy.reflowGroupBounds()
        copy.syncLegacyStrokesFromItems()
        return copy.normalized()
    }

    private mutating func reflowGroupBounds() {
        guard !items.isEmpty else { return }

        let currentItems = items
        items = currentItems.map { item in
            guard item.kind == .group,
                  !item.memberIDs.isEmpty else {
                return item
            }

            let members = item.memberIDs.compactMap { memberID in
                currentItems.first { $0.id == memberID && $0.kind != .group }
            }
            guard members.count > 1,
                  let bounds = WhiteboardGeometry.bounds(for: members) else {
                return item
            }

            var copy = item
            copy.rect = bounds.insetBy(dx: -0.025, dy: -0.025).clamped()
            return copy
        }
    }

    private mutating func syncLegacyStrokesFromItems() {
        guard !items.isEmpty else { return }
        strokes = items.compactMap(\.strokeValue)
    }

    private func normalized() -> WhiteboardDocument {
        let normalizedStrokes = strokes
            .map { $0.normalized() }
            .filter { !$0.points.isEmpty }
        let normalizedItems = items
            .map { $0.normalized() }
            .filter(\.isRenderable)

        return WhiteboardDocument(
            version: max(2, version),
            strokes: normalizedStrokes,
            items: normalizedItems
        )
    }
}

enum WhiteboardItemKind: String, CaseIterable, Codable {
    case stroke
    case sticky
    case shape
    case text
    case connector
    case group
}

enum WhiteboardShapeKind: String, CaseIterable, Codable, Identifiable {
    case rectangle
    case ellipse
    case diamond

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .diamond: "Diamond"
        }
    }
}

enum WhiteboardConnectorRouting: String, CaseIterable, Codable, Identifiable {
    case straight
    case orthogonal
    case horizontalFirst
    case verticalFirst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .straight: "Straight"
        case .orthogonal: "Smart shortest"
        case .horizontalFirst: "Horizontal first"
        case .verticalFirst: "Vertical first"
        }
    }

    var systemName: String {
        switch self {
        case .straight: "line.diagonal"
        case .orthogonal: "arrow.triangle.turn.up.right.diamond"
        case .horizontalFirst: "arrow.right.to.line.compact"
        case .verticalFirst: "arrow.down.to.line.compact"
        }
    }
}

enum WhiteboardConnectorAnchor: String, Codable {
    case auto
    case center
    case top
    case right
    case bottom
    case left
}

enum WhiteboardGroupAlignment: String, CaseIterable, Identifiable {
    case left
    case horizontalCenter
    case right
    case top
    case verticalCenter
    case bottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: "Align left"
        case .horizontalCenter: "Align horizontal center"
        case .right: "Align right"
        case .top: "Align top"
        case .verticalCenter: "Align vertical center"
        case .bottom: "Align bottom"
        }
    }

    var systemName: String {
        switch self {
        case .left: "align.horizontal.left"
        case .horizontalCenter: "align.horizontal.center"
        case .right: "align.horizontal.right"
        case .top: "align.vertical.top"
        case .verticalCenter: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }

    fileprivate func delta(for rect: WhiteboardRect, within bounds: WhiteboardRect) -> WhiteboardPoint {
        switch self {
        case .left:
            WhiteboardPoint(x: bounds.x - rect.x, y: 0)
        case .horizontalCenter:
            WhiteboardPoint(x: (bounds.x + bounds.width / 2) - (rect.x + rect.width / 2), y: 0)
        case .right:
            WhiteboardPoint(x: bounds.maxX - rect.maxX, y: 0)
        case .top:
            WhiteboardPoint(x: 0, y: bounds.y - rect.y)
        case .verticalCenter:
            WhiteboardPoint(x: 0, y: (bounds.y + bounds.height / 2) - (rect.y + rect.height / 2))
        case .bottom:
            WhiteboardPoint(x: 0, y: bounds.maxY - rect.maxY)
        }
    }
}

struct WhiteboardConnectionEndpoint: Codable, Equatable {
    var itemID: UUID
    var anchor: WhiteboardConnectorAnchor

    init(itemID: UUID, anchor: WhiteboardConnectorAnchor = .auto) {
        self.itemID = itemID
        self.anchor = anchor
    }
}

enum WhiteboardFill: String, CaseIterable, Codable, Identifiable {
    case clear
    case white
    case yellow
    case blue
    case green
    case orange
    case red
    case purple

    var id: String { rawValue }
}

struct WhiteboardItem: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: WhiteboardItemKind
    var rect: WhiteboardRect?
    var text: String
    var fill: WhiteboardFill
    var ink: WhiteboardInk
    var lineWidth: Double
    var points: [WhiteboardPoint]
    var shape: WhiteboardShapeKind?
    var startArrow: Bool
    var endArrow: Bool
    var connectorRouting: WhiteboardConnectorRouting?
    var startConnection: WhiteboardConnectionEndpoint?
    var endConnection: WhiteboardConnectionEndpoint?
    var memberIDs: [UUID]

    init(
        id: UUID = UUID(),
        kind: WhiteboardItemKind,
        rect: WhiteboardRect? = nil,
        text: String = "",
        fill: WhiteboardFill = .clear,
        ink: WhiteboardInk = .blue,
        lineWidth: Double = 3,
        points: [WhiteboardPoint] = [],
        shape: WhiteboardShapeKind? = nil,
        startArrow: Bool = false,
        endArrow: Bool = false,
        connectorRouting: WhiteboardConnectorRouting? = nil,
        startConnection: WhiteboardConnectionEndpoint? = nil,
        endConnection: WhiteboardConnectionEndpoint? = nil,
        memberIDs: [UUID] = []
    ) {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.text = text
        self.fill = fill
        self.ink = ink
        self.lineWidth = lineWidth
        self.points = points
        self.shape = shape
        self.startArrow = startArrow
        self.endArrow = endArrow
        self.connectorRouting = connectorRouting
        self.startConnection = startConnection
        self.endConnection = endConnection
        self.memberIDs = memberIDs
    }

    static func stroke(_ stroke: WhiteboardStroke) -> WhiteboardItem {
        WhiteboardItem(
            id: stroke.id,
            kind: .stroke,
            ink: stroke.ink,
            lineWidth: stroke.lineWidth,
            points: stroke.points
        )
    }

    static func sticky(rect: WhiteboardRect, text: String, fill: WhiteboardFill = .yellow) -> WhiteboardItem {
        WhiteboardItem(kind: .sticky, rect: rect, text: text, fill: fill, ink: .black, lineWidth: 1)
    }

    static func text(rect: WhiteboardRect, text: String, ink: WhiteboardInk = .black) -> WhiteboardItem {
        WhiteboardItem(kind: .text, rect: rect, text: text, fill: .clear, ink: ink, lineWidth: 1)
    }

    static func shape(
        _ shape: WhiteboardShapeKind,
        rect: WhiteboardRect,
        text: String = "",
        fill: WhiteboardFill = .white,
        ink: WhiteboardInk = .blue
    ) -> WhiteboardItem {
        WhiteboardItem(kind: .shape, rect: rect, text: text, fill: fill, ink: ink, lineWidth: 3, shape: shape)
    }

    static func connector(
        from start: WhiteboardPoint,
        to end: WhiteboardPoint,
        ink: WhiteboardInk = .blue,
        endArrow: Bool = true,
        routing: WhiteboardConnectorRouting = .orthogonal,
        startConnection: WhiteboardConnectionEndpoint? = nil,
        endConnection: WhiteboardConnectionEndpoint? = nil
    ) -> WhiteboardItem {
        WhiteboardItem(
            kind: .connector,
            ink: ink,
            lineWidth: 3,
            points: [start, end],
            endArrow: endArrow,
            connectorRouting: routing,
            startConnection: startConnection,
            endConnection: endConnection
        )
    }

    var resolvedConnectorRouting: WhiteboardConnectorRouting {
        connectorRouting ?? ((startConnection != nil || endConnection != nil) ? .orthogonal : .straight)
    }

    var strokeValue: WhiteboardStroke? {
        guard kind == .stroke else { return nil }
        return WhiteboardStroke(id: id, ink: ink, lineWidth: lineWidth, points: points)
    }

    var isRenderable: Bool {
        switch kind {
        case .stroke:
            return !points.isEmpty
        case .connector:
            return points.count >= 2
        case .sticky, .shape, .text, .group:
            return rect != nil
        }
    }

    func normalized() -> WhiteboardItem {
        WhiteboardItem(
            id: id,
            kind: kind,
            rect: rect?.clamped(),
            text: text,
            fill: fill,
            ink: ink,
            lineWidth: min(max(lineWidth, 1), 24),
            points: points.map { $0.clamped() },
            shape: kind == .shape ? (shape ?? .rectangle) : shape,
            startArrow: startArrow,
            endArrow: endArrow,
            connectorRouting: kind == .connector ? connectorRouting : nil,
            startConnection: kind == .connector ? startConnection : nil,
            endConnection: kind == .connector ? endConnection : nil,
            memberIDs: Array(Set(memberIDs)).sorted { $0.uuidString < $1.uuidString }
        )
    }

    func moved(by delta: WhiteboardPoint) -> WhiteboardItem {
        var copy = self
        copy.rect = rect?.offsetBy(dx: delta.x, dy: delta.y).clamped()
        copy.points = points.map { $0.offsetBy(dx: delta.x, dy: delta.y).clamped() }
        return copy.normalized()
    }

    func duplicated(idMap: [UUID: UUID], offset: WhiteboardPoint) -> WhiteboardItem {
        var copy = moved(by: offset)
        copy.id = idMap[id] ?? UUID()
        copy.memberIDs = memberIDs.compactMap { idMap[$0] }
        if let startConnection,
           let duplicatedStartID = idMap[startConnection.itemID] {
            copy.startConnection = WhiteboardConnectionEndpoint(itemID: duplicatedStartID, anchor: startConnection.anchor)
        }
        if let endConnection,
           let duplicatedEndID = idMap[endConnection.itemID] {
            copy.endConnection = WhiteboardConnectionEndpoint(itemID: duplicatedEndID, anchor: endConnection.anchor)
        }
        return copy.normalized()
    }
}

enum WhiteboardInk: String, CaseIterable, Codable, Identifiable {
    case black
    case blue
    case green
    case orange
    case red
    case purple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .black: "Black"
        case .blue: "Blue"
        case .green: "Green"
        case .orange: "Orange"
        case .red: "Red"
        case .purple: "Purple"
        }
    }
}

struct WhiteboardStroke: Codable, Equatable, Identifiable {
    var id: UUID
    var ink: WhiteboardInk
    var lineWidth: Double
    var points: [WhiteboardPoint]

    init(
        id: UUID = UUID(),
        ink: WhiteboardInk = .blue,
        lineWidth: Double = 4,
        points: [WhiteboardPoint] = []
    ) {
        self.id = id
        self.ink = ink
        self.lineWidth = lineWidth
        self.points = points
    }

    func normalized() -> WhiteboardStroke {
        WhiteboardStroke(
            id: id,
            ink: ink,
            lineWidth: min(max(lineWidth, 1), 24),
            points: points.map { $0.clamped() }
        )
    }
}

struct WhiteboardPoint: Codable, Equatable {
    var x: Double
    var y: Double

    func clamped() -> WhiteboardPoint {
        WhiteboardPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }

    func offsetBy(dx: Double, dy: Double) -> WhiteboardPoint {
        WhiteboardPoint(x: x + dx, y: y + dy)
    }

    func distanceSquared(to other: WhiteboardPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}

struct WhiteboardRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let defaultBox = WhiteboardRect(x: 0.1, y: 0.1, width: 0.18, height: 0.12)

    var maxX: Double { x + width }
    var maxY: Double { y + height }

    func clamped() -> WhiteboardRect {
        let clampedWidth = min(max(abs(width), 0.02), 1)
        let clampedHeight = min(max(abs(height), 0.02), 1)
        return WhiteboardRect(
            x: min(max(width < 0 ? x + width : x, 0), max(0, 1 - clampedWidth)),
            y: min(max(height < 0 ? y + height : y, 0), max(0, 1 - clampedHeight)),
            width: clampedWidth,
            height: clampedHeight
        )
    }

    func insetBy(dx: Double, dy: Double) -> WhiteboardRect {
        WhiteboardRect(x: x + dx, y: y + dy, width: width - dx * 2, height: height - dy * 2)
    }

    func offsetBy(dx: Double, dy: Double) -> WhiteboardRect {
        WhiteboardRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    func intersects(_ other: WhiteboardRect) -> Bool {
        let lhs = clamped()
        let rhs = other.clamped()
        return lhs.x <= rhs.maxX &&
            lhs.maxX >= rhs.x &&
            lhs.y <= rhs.maxY &&
            lhs.maxY >= rhs.y
    }
}

enum WhiteboardGeometry {
    static let connectorAnchors: [WhiteboardConnectorAnchor] = [.top, .right, .bottom, .left]

    static func anchorPoint(_ anchor: WhiteboardConnectorAnchor, on rect: WhiteboardRect) -> WhiteboardPoint {
        switch anchor {
        case .top:
            return WhiteboardPoint(x: rect.x + rect.width / 2, y: rect.y)
        case .right:
            return WhiteboardPoint(x: rect.maxX, y: rect.y + rect.height / 2)
        case .bottom:
            return WhiteboardPoint(x: rect.x + rect.width / 2, y: rect.maxY)
        case .left:
            return WhiteboardPoint(x: rect.x, y: rect.y + rect.height / 2)
        case .center, .auto:
            return WhiteboardPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
        }
    }

    static func nearestAnchor(to point: WhiteboardPoint, on rect: WhiteboardRect) -> WhiteboardConnectorAnchor {
        connectorAnchors.min { lhs, rhs in
            point.distanceSquared(to: anchorPoint(lhs, on: rect)) < point.distanceSquared(to: anchorPoint(rhs, on: rect))
        } ?? .right
    }

    static func bounds(for items: [WhiteboardItem]) -> WhiteboardRect? {
        let rects = items.compactMap(itemBounds)
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { partial, rect in
            let minX = min(partial.x, rect.x)
            let minY = min(partial.y, rect.y)
            let maxX = max(partial.maxX, rect.maxX)
            let maxY = max(partial.maxY, rect.maxY)
            return WhiteboardRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    static func itemBounds(_ item: WhiteboardItem) -> WhiteboardRect? {
        switch item.kind {
        case .sticky, .shape, .text, .group:
            return item.rect
        case .stroke, .connector:
            guard let first = item.points.first else { return nil }
            var minX = first.x
            var minY = first.y
            var maxX = first.x
            var maxY = first.y
            for point in item.points.dropFirst() {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
            return WhiteboardRect(
                x: minX,
                y: minY,
                width: max(maxX - minX, 0.01),
                height: max(maxY - minY, 0.01)
            )
        }
    }
}

enum WhiteboardConnectorRouter {
    struct Bridge: Equatable {
        var segmentIndex: Int
        var point: CGPoint
    }

    enum PathCommand: Equatable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
    }

    private struct Attachment {
        var point: CGPoint
        var port: CGPoint?
    }

    static func routedPoints(
        for connector: WhiteboardItem,
        in items: [WhiteboardItem],
        size: CGSize
    ) -> [CGPoint] {
        guard connector.kind == .connector,
              connector.points.count >= 2 else {
            return connector.points.map { point($0, size: size) }
        }

        let fallbackStart = point(connector.points[0], size: size)
        let fallbackEnd = point(connector.points[1], size: size)
        let startItem = connectedItem(connector.startConnection, in: items)
        let endItem = connectedItem(connector.endConnection, in: items)
        let startRect = startItem.flatMap { rect($0.rect, size: size) }
        let endRect = endItem.flatMap { rect($0.rect, size: size) }
        let startReference = endRect.map(\.center) ?? fallbackEnd
        let endReference = startRect.map(\.center) ?? fallbackStart

        let start = startRect.map { attachment(on: $0, toward: startReference, anchor: connector.startConnection?.anchor ?? .auto) } ?? Attachment(point: fallbackStart)
        let end = endRect.map { attachment(on: $0, toward: endReference, anchor: connector.endConnection?.anchor ?? .auto) } ?? Attachment(point: fallbackEnd)
        let routeStart = start.port ?? start.point
        let routeEnd = end.port ?? end.point

        switch connector.resolvedConnectorRouting {
        case .straight:
            return [start.point, end.point]
        case .horizontalFirst:
            return withAttachmentPorts(start: start, route: simplified([routeStart, CGPoint(x: routeEnd.x, y: routeStart.y), routeEnd]), end: end)
        case .verticalFirst:
            return withAttachmentPorts(start: start, route: simplified([routeStart, CGPoint(x: routeStart.x, y: routeEnd.y), routeEnd]), end: end)
        case .orthogonal:
            let connectedIDs = Set([connector.startConnection?.itemID, connector.endConnection?.itemID].compactMap { $0 })
            let obstacles = objectObstacles(in: items, size: size, excluding: connectedIDs)
            return withAttachmentPorts(
                start: start,
                route: shortestOrthogonalRoute(from: routeStart, to: routeEnd, obstacles: obstacles),
                end: end
            )
        }
    }

    static func routedNormalizedPoints(
        for connector: WhiteboardItem,
        in items: [WhiteboardItem],
        size: CGSize
    ) -> [WhiteboardPoint] {
        routedPoints(for: connector, in: items, size: size).map {
            WhiteboardPoint(x: Double($0.x / max(size.width, 1)), y: Double($0.y / max(size.height, 1))).clamped()
        }
    }

    static func bridges(
        for connector: WhiteboardItem,
        routedPoints points: [CGPoint],
        in items: [WhiteboardItem],
        size: CGSize
    ) -> [Bridge] {
        guard connector.kind == .connector,
              points.count >= 2,
              let connectorIndex = items.firstIndex(where: { $0.id == connector.id }) else {
            return []
        }

        var bridges: [Bridge] = []
        for (otherIndex, other) in items.enumerated() where other.kind == .connector && other.id != connector.id && otherIndex < connectorIndex {
            let otherPoints = routedPoints(for: other, in: items, size: size)
            guard otherPoints.count >= 2 else { continue }

            for segmentIndex in points.indices.dropLast() {
                let segmentStart = points[segmentIndex]
                let segmentEnd = points[segmentIndex + 1]
                for otherSegmentIndex in otherPoints.indices.dropLast() {
                    let otherStart = otherPoints[otherSegmentIndex]
                    let otherEnd = otherPoints[otherSegmentIndex + 1]
                    guard let intersection = orthogonalIntersection(segmentStart, segmentEnd, otherStart, otherEnd),
                          !isNearEndpoint(intersection, segmentStart, segmentEnd, otherStart, otherEnd) else {
                        continue
                    }
                    bridges.append(Bridge(segmentIndex: segmentIndex, point: intersection))
                }
            }
        }

        var seen = Set<String>()
        return bridges
            .filter { bridge in
                let key = "\(bridge.segmentIndex):\(Int(bridge.point.x.rounded())):\(Int(bridge.point.y.rounded()))"
                return seen.insert(key).inserted
            }
            .sorted { first, second in
                if first.segmentIndex == second.segmentIndex {
                    return distance(points[first.segmentIndex], first.point) < distance(points[second.segmentIndex], second.point)
                }
                return first.segmentIndex < second.segmentIndex
            }
    }

    static func pathCommands(
        points: [CGPoint],
        bridges: [Bridge],
        bridgeRadius: CGFloat,
        cornerRadius: CGFloat
    ) -> [PathCommand] {
        guard let first = points.first else { return [] }
        guard points.count > 1 else { return [.move(to: first)] }

        var commands: [PathCommand] = [.move(to: first)]
        var cursor = first

        for segmentIndex in points.indices.dropLast() {
            let segmentStart = points[segmentIndex]
            let segmentEnd = points[segmentIndex + 1]
            let direction = normalizedDirection(from: segmentStart, to: segmentEnd)
            var drawEnd = segmentEnd
            var cornerExit: CGPoint?

            if points.indices.contains(segmentIndex + 2) {
                let nextEnd = points[segmentIndex + 2]
                let nextDirection = normalizedDirection(from: segmentEnd, to: nextEnd)
                if isTurn(from: direction, to: nextDirection) {
                    let radius = min(
                        cornerRadius,
                        max(0, distance(segmentStart, segmentEnd) / 2 - 0.5),
                        max(0, distance(segmentEnd, nextEnd) / 2 - 0.5)
                    )
                    if radius > 1 {
                        drawEnd = CGPoint(
                            x: segmentEnd.x - direction.x * radius,
                            y: segmentEnd.y - direction.y * radius
                        )
                        cornerExit = CGPoint(
                            x: segmentEnd.x + nextDirection.x * radius,
                            y: segmentEnd.y + nextDirection.y * radius
                        )
                    }
                }
            }

            appendSegmentCommands(
                to: &commands,
                from: cursor,
                to: drawEnd,
                originalStart: segmentStart,
                bridges: bridges.filter { $0.segmentIndex == segmentIndex },
                bridgeRadius: bridgeRadius
            )

            if let cornerExit {
                commands.append(.quadCurve(to: cornerExit, control: segmentEnd))
                cursor = cornerExit
            } else {
                cursor = drawEnd
            }
        }

        return commands
    }

    private static func connectedItem(_ endpoint: WhiteboardConnectionEndpoint?, in items: [WhiteboardItem]) -> WhiteboardItem? {
        guard let endpoint else { return nil }
        return items.first {
            $0.id == endpoint.itemID && [.sticky, .shape, .text, .group].contains($0.kind) && $0.rect != nil
        }
    }

    private static func objectObstacles(in items: [WhiteboardItem], size: CGSize, excluding ids: Set<UUID>) -> [CGRect] {
        items.compactMap { item in
            guard !ids.contains(item.id),
                  [.sticky, .shape, .text].contains(item.kind),
                  let frame = rect(item.rect, size: size) else {
                return nil
            }
            return frame.insetBy(dx: -10, dy: -10)
        }
    }

    private static func shortestOrthogonalRoute(from start: CGPoint, to end: CGPoint, obstacles: [CGRect]) -> [CGPoint] {
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let margin: CGFloat = 36
        let minObstacleX = obstacles.map(\.minX).min() ?? min(start.x, end.x)
        let maxObstacleX = obstacles.map(\.maxX).max() ?? max(start.x, end.x)
        let minObstacleY = obstacles.map(\.minY).min() ?? min(start.y, end.y)
        let maxObstacleY = obstacles.map(\.maxY).max() ?? max(start.y, end.y)
        let outsideLeftX = min(min(start.x, end.x), minObstacleX) - margin
        let outsideRightX = max(max(start.x, end.x), maxObstacleX) + margin
        let outsideTopY = min(min(start.y, end.y), minObstacleY) - margin
        let outsideBottomY = max(max(start.y, end.y), maxObstacleY) + margin
        let candidates = [
            [start, CGPoint(x: end.x, y: start.y), end],
            [start, CGPoint(x: start.x, y: end.y), end],
            [start, CGPoint(x: midX, y: start.y), CGPoint(x: midX, y: end.y), end],
            [start, CGPoint(x: start.x, y: midY), CGPoint(x: end.x, y: midY), end],
            [start, CGPoint(x: outsideLeftX, y: start.y), CGPoint(x: outsideLeftX, y: end.y), end],
            [start, CGPoint(x: outsideRightX, y: start.y), CGPoint(x: outsideRightX, y: end.y), end],
            [start, CGPoint(x: start.x, y: outsideTopY), CGPoint(x: end.x, y: outsideTopY), end],
            [start, CGPoint(x: start.x, y: outsideBottomY), CGPoint(x: end.x, y: outsideBottomY), end]
        ].map(simplified)

        return candidates.min { lhs, rhs in
            routeScore(lhs, obstacles: obstacles) < routeScore(rhs, obstacles: obstacles)
        } ?? [start, end]
    }

    private static func routeScore(_ points: [CGPoint], obstacles: [CGRect]) -> CGFloat {
        let length = zip(points, points.dropFirst()).reduce(CGFloat.zero) { partial, segment in
            partial + abs(segment.0.x - segment.1.x) + abs(segment.0.y - segment.1.y)
        }
        let crossings = zip(points, points.dropFirst()).reduce(0) { partial, segment in
            partial + obstacles.filter { segmentCrossesRect(segment.0, segment.1, rect: $0) }.count
        }
        return length + CGFloat(crossings) * 100_000
    }

    private static func segmentCrossesRect(_ start: CGPoint, _ end: CGPoint, rect: CGRect) -> Bool {
        if abs(start.y - end.y) < 0.5 {
            let y = start.y
            let minX = min(start.x, end.x)
            let maxX = max(start.x, end.x)
            return y >= rect.minY && y <= rect.maxY && maxX >= rect.minX && minX <= rect.maxX
        }
        if abs(start.x - end.x) < 0.5 {
            let x = start.x
            let minY = min(start.y, end.y)
            let maxY = max(start.y, end.y)
            return x >= rect.minX && x <= rect.maxX && maxY >= rect.minY && minY <= rect.maxY
        }
        return false
    }

    private static func orthogonalIntersection(_ aStart: CGPoint, _ aEnd: CGPoint, _ bStart: CGPoint, _ bEnd: CGPoint) -> CGPoint? {
        let aHorizontal = abs(aStart.y - aEnd.y) < 0.5
        let aVertical = abs(aStart.x - aEnd.x) < 0.5
        let bHorizontal = abs(bStart.y - bEnd.y) < 0.5
        let bVertical = abs(bStart.x - bEnd.x) < 0.5

        if aHorizontal, bVertical {
            let point = CGPoint(x: bStart.x, y: aStart.y)
            return contains(point.x, between: aStart.x, and: aEnd.x) &&
                contains(point.y, between: bStart.y, and: bEnd.y) ? point : nil
        }

        if aVertical, bHorizontal {
            let point = CGPoint(x: aStart.x, y: bStart.y)
            return contains(point.y, between: aStart.y, and: aEnd.y) &&
                contains(point.x, between: bStart.x, and: bEnd.x) ? point : nil
        }

        return nil
    }

    private static func contains(_ value: CGFloat, between first: CGFloat, and second: CGFloat) -> Bool {
        value >= min(first, second) + 1 && value <= max(first, second) - 1
    }

    private static func isNearEndpoint(_ point: CGPoint, _ endpoints: CGPoint...) -> Bool {
        endpoints.contains { distance(point, $0) < 18 }
    }

    private static func appendSegmentCommands(
        to commands: inout [PathCommand],
        from start: CGPoint,
        to end: CGPoint,
        originalStart: CGPoint,
        bridges: [Bridge],
        bridgeRadius: CGFloat
    ) {
        guard distance(start, end) > 0.5 else { return }

        let direction = normalizedDirection(from: start, to: end)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let startOffset = distance(originalStart, start)
        let endOffset = distance(originalStart, end)
        let usableStart = min(startOffset, endOffset) + bridgeRadius + 1
        let usableEnd = max(startOffset, endOffset) - bridgeRadius - 1
        let segmentBridges = bridges
            .filter { bridge in
                let offset = distance(originalStart, bridge.point)
                return offset >= usableStart && offset <= usableEnd
            }
            .sorted { distance(start, $0.point) < distance(start, $1.point) }

        for bridge in segmentBridges {
            let before = CGPoint(
                x: bridge.point.x - direction.x * bridgeRadius,
                y: bridge.point.y - direction.y * bridgeRadius
            )
            let after = CGPoint(
                x: bridge.point.x + direction.x * bridgeRadius,
                y: bridge.point.y + direction.y * bridgeRadius
            )
            let control = CGPoint(
                x: bridge.point.x + normal.x * bridgeRadius,
                y: bridge.point.y + normal.y * bridgeRadius
            )
            commands.append(.line(to: before))
            commands.append(.quadCurve(to: after, control: control))
        }

        commands.append(.line(to: end))
    }

    private static func normalizedDirection(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        return CGPoint(x: dx / length, y: dy / length)
    }

    private static func isTurn(from first: CGPoint, to second: CGPoint) -> Bool {
        abs(first.x - second.x) > 0.01 || abs(first.y - second.y) > 0.01
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func simplified(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last,
               abs(last.x - point.x) < 0.5,
               abs(last.y - point.y) < 0.5 {
                continue
            }
            result.append(point)
        }

        guard result.count > 2 else { return result }

        var collapsed: [CGPoint] = []
        for point in result {
            collapsed.append(point)
            while collapsed.count >= 3 {
                let a = collapsed[collapsed.count - 3]
                let b = collapsed[collapsed.count - 2]
                let c = collapsed[collapsed.count - 1]
                let sameX = abs(a.x - b.x) < 0.5 && abs(b.x - c.x) < 0.5
                let sameY = abs(a.y - b.y) < 0.5 && abs(b.y - c.y) < 0.5
                guard sameX || sameY else { break }
                collapsed.remove(at: collapsed.count - 2)
            }
        }
        return collapsed
    }

    private static func withAttachmentPorts(start: Attachment, route: [CGPoint], end: Attachment) -> [CGPoint] {
        var points: [CGPoint] = []
        points.append(start.point)
        points.append(contentsOf: route)
        points.append(end.point)
        return simplified(points)
    }

    private static func attachment(on rect: CGRect, toward target: CGPoint, anchor: WhiteboardConnectorAnchor) -> Attachment {
        let side = effectiveAnchor(on: rect, toward: target, anchor: anchor)
        let point = attachmentPoint(on: rect, anchor: side)
        guard let side else {
            return Attachment(point: point)
        }

        return Attachment(point: point, port: portPoint(from: point, anchor: side))
    }

    private static func effectiveAnchor(on rect: CGRect, toward target: CGPoint, anchor: WhiteboardConnectorAnchor) -> WhiteboardConnectorAnchor? {
        switch anchor {
        case .center:
            return nil
        case .top:
            return .top
        case .right:
            return .right
        case .bottom:
            return .bottom
        case .left:
            return .left
        case .auto:
            let center = rect.center
            let dx = target.x - center.x
            let dy = target.y - center.y
            let halfWidth = max(rect.width / 2, 1)
            let halfHeight = max(rect.height / 2, 1)
            if abs(dx / halfWidth) >= abs(dy / halfHeight) {
                return dx >= 0 ? .right : .left
            }
            return dy >= 0 ? .bottom : .top
        }
    }

    private static func attachmentPoint(on rect: CGRect, anchor: WhiteboardConnectorAnchor?) -> CGPoint {
        switch anchor {
        case .top:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .right:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .left:
            return CGPoint(x: rect.minX, y: rect.midY)
        case .center, .auto, nil:
            return rect.center
        }
    }

    private static func portPoint(from point: CGPoint, anchor: WhiteboardConnectorAnchor) -> CGPoint {
        let offset: CGFloat = 28
        switch anchor {
        case .top:
            return CGPoint(x: point.x, y: point.y - offset)
        case .right:
            return CGPoint(x: point.x + offset, y: point.y)
        case .bottom:
            return CGPoint(x: point.x, y: point.y + offset)
        case .left:
            return CGPoint(x: point.x - offset, y: point.y)
        case .auto, .center:
            return point
        }
    }

    private static func rect(_ rect: WhiteboardRect?, size: CGSize) -> CGRect? {
        guard let rect else { return nil }
        let resolved = rect.clamped()
        return CGRect(
            x: resolved.x * size.width,
            y: resolved.y * size.height,
            width: resolved.width * size.width,
            height: resolved.height * size.height
        )
    }

    private static func point(_ point: WhiteboardPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
