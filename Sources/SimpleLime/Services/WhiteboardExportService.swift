import AppKit
import Foundation

enum WhiteboardExportService {
    static let defaultCanvasSize = CGSize(width: 1600, height: 1000)

    static func svgDocument(
        title: String,
        document: WhiteboardDocument,
        size: CGSize = defaultCanvasSize
    ) -> String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let items = document.renderItems
        let body = items.map { svgElement(for: $0, size: size, allItems: items) }.joined(separator: "\n")
        let markers = WhiteboardInk.allCases.map { ink in
            let color = svgStrokeColor(for: ink)
            return """
            <marker id="arrow-\(ink.rawValue)" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
              <path d="M 0 0 L 10 5 L 0 10 z" fill="\(color)" />
            </marker>
            """
        }.joined(separator: "\n")

        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)" role="img" aria-label="\(escapeXML(title))">
        <defs>
        \(markers)
        </defs>
        <rect width="100%" height="100%" fill="#ffffff"/>
        \(svgGrid(size: size))
        \(body)
        </svg>
        """
    }

    static func pngData(
        document: WhiteboardDocument,
        size: CGSize = defaultCanvasSize
    ) -> Data? {
        let image = image(document: document, size: size)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    @discardableResult
    static func writePNGToPasteboard(
        document: WhiteboardDocument,
        size: CGSize = defaultCanvasSize,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard let data = pngData(document: document, size: size) else {
            return false
        }

        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    static func image(
        document: WhiteboardDocument,
        size: CGSize = defaultCanvasSize
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        draw(document: document, size: size)
        image.unlockFocus()
        return image
    }

    static func draw(document: WhiteboardDocument, size: CGSize) {
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        drawGrid(size: size)

        let items = document.renderItems
        for item in items {
            draw(item: item, size: size, allItems: items)
        }
    }

    private static func draw(item: WhiteboardItem, size: CGSize, allItems: [WhiteboardItem]) {
        switch item.kind {
        case .stroke:
            drawStroke(item, size: size)
        case .connector:
            drawConnector(item, size: size, allItems: allItems)
        case .sticky:
            drawSticky(item, size: size)
        case .shape:
            drawShape(item, size: size)
        case .text:
            drawText(item.text, in: rect(item.rect, size: size), color: nsStrokeColor(for: item.ink), fontSize: 18)
        case .group:
            drawGroup(item, size: size)
        }
    }

    private static func drawStroke(_ item: WhiteboardItem, size: CGSize) {
        guard let first = item.points.first else { return }
        nsStrokeColor(for: item.ink).setStroke()
        nsStrokeColor(for: item.ink).setFill()

        if item.points.count == 1 {
            let center = point(first, size: size)
            NSBezierPath(ovalIn: CGRect(
                x: center.x - item.lineWidth / 2,
                y: center.y - item.lineWidth / 2,
                width: item.lineWidth,
                height: item.lineWidth
            )).fill()
            return
        }

        let path = NSBezierPath()
        path.lineWidth = item.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: point(first, size: size))
        item.points.dropFirst().forEach { path.line(to: point($0, size: size)) }
        path.stroke()
    }

    private static func drawGrid(size: CGSize) {
        NSColor.gridColor.withAlphaComponent(0.24).setStroke()
        let minorPath = NSBezierPath()
        minorPath.lineWidth = 1
        var x: CGFloat = 0
        while x <= size.width {
            minorPath.move(to: CGPoint(x: x, y: 0))
            minorPath.line(to: CGPoint(x: x, y: size.height))
            x += 24
        }
        var y: CGFloat = 0
        while y <= size.height {
            minorPath.move(to: CGPoint(x: 0, y: y))
            minorPath.line(to: CGPoint(x: size.width, y: y))
            y += 24
        }
        minorPath.stroke()

        NSColor.gridColor.withAlphaComponent(0.40).setStroke()
        let majorPath = NSBezierPath()
        majorPath.lineWidth = 1
        x = 0
        while x <= size.width {
            majorPath.move(to: CGPoint(x: x, y: 0))
            majorPath.line(to: CGPoint(x: x, y: size.height))
            x += 120
        }
        y = 0
        while y <= size.height {
            majorPath.move(to: CGPoint(x: 0, y: y))
            majorPath.line(to: CGPoint(x: size.width, y: y))
            y += 120
        }
        majorPath.stroke()
    }

    private static func drawConnector(_ item: WhiteboardItem, size: CGSize, allItems: [WhiteboardItem]) {
        let points = WhiteboardConnectorRouter.routedPoints(for: item, in: allItems, size: size)
        guard let start = points.first,
              let end = points.last,
              points.count >= 2 else {
            return
        }

        nsStrokeColor(for: item.ink).setStroke()
        let bridges = WhiteboardConnectorRouter.bridges(for: item, routedPoints: points, in: allItems, size: size)
        let path = connectorPath(points: points, bridges: bridges, bridgeRadius: 10)
        path.lineWidth = item.lineWidth
        path.lineCapStyle = .round
        path.stroke()

        if item.startArrow, points.count > 1 {
            drawArrowHead(tip: start, tail: points[1], color: nsStrokeColor(for: item.ink), width: item.lineWidth)
        }
        if item.endArrow, points.count > 1 {
            drawArrowHead(tip: end, tail: points[points.count - 2], color: nsStrokeColor(for: item.ink), width: item.lineWidth)
        }
    }

    private static func drawSticky(_ item: WhiteboardItem, size: CGSize) {
        let frame = rect(item.rect, size: size)
        let path = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        nsFillColor(for: item.fill).setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1
        path.stroke()
        if !item.text.isEmpty {
            drawText(item.text, in: frame.insetBy(dx: 12, dy: 10), color: .black, fontSize: 16)
        }
    }

    private static func connectorPath(points: [CGPoint], bridges: [WhiteboardConnectorRouter.Bridge], bridgeRadius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for command in WhiteboardConnectorRouter.pathCommands(
            points: points,
            bridges: bridges,
            bridgeRadius: bridgeRadius,
            cornerRadius: 14
        ) {
            switch command {
            case let .move(point):
                path.move(to: point)
            case let .line(point):
                path.line(to: point)
            case let .quadCurve(point, control):
                path.curve(to: point, controlPoint1: control, controlPoint2: control)
            }
        }

        return path
    }

    private static func drawShape(_ item: WhiteboardItem, size: CGSize) {
        let frame = rect(item.rect, size: size)
        let path = shapePath(kind: item.shape ?? .rectangle, rect: frame)
        nsFillColor(for: item.fill).setFill()
        path.fill()
        nsStrokeColor(for: item.ink).setStroke()
        path.lineWidth = item.lineWidth
        path.stroke()

        if !item.text.isEmpty {
            drawText(item.text, in: frame.insetBy(dx: 10, dy: 10), color: nsStrokeColor(for: item.ink), fontSize: 15)
        }
    }

    private static func drawGroup(_ item: WhiteboardItem, size: CGSize) {
        let frame = rect(item.rect, size: size)
        let path = NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10)
        path.lineWidth = item.lineWidth
        path.setLineDash([8, 6], count: 2, phase: 0)
        nsStrokeColor(for: item.ink).withAlphaComponent(0.78).setStroke()
        path.stroke()
        if !item.text.isEmpty {
            drawText(item.text, in: CGRect(x: frame.minX + 10, y: frame.minY + 6, width: frame.width - 20, height: 24), color: nsStrokeColor(for: item.ink), fontSize: 12)
        }
    }

    private static func drawArrowHead(tip: CGPoint, tail: CGPoint, color: NSColor, width: CGFloat) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let length = max(width * 3.5, 12)
        let spread = CGFloat.pi / 7
        let left = CGPoint(
            x: tip.x - cos(angle - spread) * length,
            y: tip.y - sin(angle - spread) * length
        )
        let right = CGPoint(
            x: tip.x - cos(angle + spread) * length,
            y: tip.y - sin(angle + spread) * length
        )
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: left)
        path.line(to: right)
        path.close()
        color.setFill()
        path.fill()
    }

    private static func drawText(_ text: String, in rect: CGRect, color: NSColor, fontSize: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    private static func shapePath(kind: WhiteboardShapeKind, rect: CGRect) -> NSBezierPath {
        switch kind {
        case .rectangle:
            return NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        case .ellipse:
            return NSBezierPath(ovalIn: rect)
        case .diamond:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.line(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.line(to: CGPoint(x: rect.minX, y: rect.midY))
            path.close()
            return path
        }
    }

    private static func svgElement(for item: WhiteboardItem, size: CGSize, allItems: [WhiteboardItem]) -> String {
        switch item.kind {
        case .stroke:
            return svgStroke(item, size: size)
        case .connector:
            return svgConnector(item, size: size, allItems: allItems)
        case .sticky:
            return svgBox(item, size: size, sticky: true)
        case .shape:
            return svgShape(item, size: size)
        case .text:
            return svgText(item.text, rect: rect(item.rect, size: size), color: svgStrokeColor(for: item.ink), fontSize: 20)
        case .group:
            let frame = rect(item.rect, size: size)
            let label = item.text.isEmpty ? "" : svgText(item.text, rect: CGRect(x: frame.minX + 10, y: frame.minY + 6, width: frame.width - 20, height: 24), color: svgStrokeColor(for: item.ink), fontSize: 14)
            return """
            <g data-kind="group" data-members="\(item.memberIDs.map(\.uuidString).joined(separator: ","))">
              <rect x="\(format(frame.minX))" y="\(format(frame.minY))" width="\(format(frame.width))" height="\(format(frame.height))" rx="10" fill="none" stroke="\(svgStrokeColor(for: item.ink))" stroke-width="\(format(item.lineWidth))" stroke-dasharray="8 6"/>
              \(label)
            </g>
            """
        }
    }

    private static func svgStroke(_ item: WhiteboardItem, size: CGSize) -> String {
        guard let first = item.points.first else { return "" }
        if item.points.count == 1 {
            let center = point(first, size: size)
            return #"<circle cx="\#(format(center.x))" cy="\#(format(center.y))" r="\#(format(item.lineWidth / 2))" fill="\#(svgStrokeColor(for: item.ink))"/>"#
        }

        let points = item.points.map { point($0, size: size) }
        let data = points.enumerated().map { index, point in
            "\(index == 0 ? "M" : "L") \(format(point.x)) \(format(point.y))"
        }.joined(separator: " ")
        return #"<path d="\#(data)" fill="none" stroke="\#(svgStrokeColor(for: item.ink))" stroke-width="\#(format(item.lineWidth))" stroke-linecap="round" stroke-linejoin="round"/>"#
    }

    private static func svgConnector(_ item: WhiteboardItem, size: CGSize, allItems: [WhiteboardItem]) -> String {
        let points = WhiteboardConnectorRouter.routedPoints(for: item, in: allItems, size: size)
        guard points.count >= 2 else { return "" }
        let markerStart = item.startArrow ? #" marker-start="url(#arrow-\#(item.ink.rawValue))""# : ""
        let markerEnd = item.endArrow ? #" marker-end="url(#arrow-\#(item.ink.rawValue))""# : ""
        let bridges = WhiteboardConnectorRouter.bridges(for: item, routedPoints: points, in: allItems, size: size)
        let data = svgConnectorPathData(points: points, bridges: bridges, bridgeRadius: 10)
        return #"<path data-kind="connector" data-routing="\#(item.resolvedConnectorRouting.rawValue)" d="\#(data)" fill="none" stroke="\#(svgStrokeColor(for: item.ink))" stroke-width="\#(format(item.lineWidth))" stroke-linecap="round" stroke-linejoin="round"\#(markerStart)\#(markerEnd)/>"#
    }

    private static func svgBox(_ item: WhiteboardItem, size: CGSize, sticky: Bool) -> String {
        let frame = rect(item.rect, size: size)
        let fill = svgFillColor(for: item.fill)
        let text = item.text.isEmpty ? "" : svgText(item.text, rect: frame.insetBy(dx: 12, dy: 10), color: "#111827", fontSize: 18)
        return """
        <g data-kind="sticky">
          <rect x="\(format(frame.minX))" y="\(format(frame.minY))" width="\(format(frame.width))" height="\(format(frame.height))" rx="8" fill="\(fill)" stroke="rgba(17,24,39,0.18)"/>
          \(text)
        </g>
        """
    }

    private static func svgShape(_ item: WhiteboardItem, size: CGSize) -> String {
        let frame = rect(item.rect, size: size)
        let fill = svgFillColor(for: item.fill)
        let stroke = svgStrokeColor(for: item.ink)
        let shape: String
        switch item.shape ?? .rectangle {
        case .rectangle:
            shape = #"<rect x="\#(format(frame.minX))" y="\#(format(frame.minY))" width="\#(format(frame.width))" height="\#(format(frame.height))" rx="7" fill="\#(fill)" stroke="\#(stroke)" stroke-width="\#(format(item.lineWidth))"/>"#
        case .ellipse:
            shape = #"<ellipse cx="\#(format(frame.midX))" cy="\#(format(frame.midY))" rx="\#(format(frame.width / 2))" ry="\#(format(frame.height / 2))" fill="\#(fill)" stroke="\#(stroke)" stroke-width="\#(format(item.lineWidth))"/>"#
        case .diamond:
            let points = [
                CGPoint(x: frame.midX, y: frame.minY),
                CGPoint(x: frame.maxX, y: frame.midY),
                CGPoint(x: frame.midX, y: frame.maxY),
                CGPoint(x: frame.minX, y: frame.midY)
            ].map { "\(format($0.x)),\(format($0.y))" }.joined(separator: " ")
            shape = #"<polygon points="\#(points)" fill="\#(fill)" stroke="\#(stroke)" stroke-width="\#(format(item.lineWidth))"/>"#
        }
        let text = item.text.isEmpty ? "" : svgText(item.text, rect: frame.insetBy(dx: 10, dy: 10), color: stroke, fontSize: 17)
        return "<g data-kind=\"shape\">\n\(shape)\n\(text)\n</g>"
    }

    private static func svgText(_ text: String, rect: CGRect, color: String, fontSize: CGFloat) -> String {
        guard !text.isEmpty else { return "" }
        let lines = text.components(separatedBy: .newlines)
        let lineHeight = fontSize * 1.2
        let firstY = rect.midY - CGFloat(lines.count - 1) * lineHeight / 2
        let tspans = lines.enumerated().map { index, line in
            #"<tspan x="\#(format(rect.midX))" y="\#(format(firstY + CGFloat(index) * lineHeight))">\#(escapeXML(line))</tspan>"#
        }.joined(separator: "\n")
        return #"<text text-anchor="middle" dominant-baseline="middle" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" font-size="\#(format(fontSize))" font-weight="500" fill="\#(color)">\#(tspans)</text>"#
    }

    private static func svgConnectorPathData(points: [CGPoint], bridges: [WhiteboardConnectorRouter.Bridge], bridgeRadius: CGFloat) -> String {
        WhiteboardConnectorRouter.pathCommands(
            points: points,
            bridges: bridges,
            bridgeRadius: bridgeRadius,
            cornerRadius: 14
        ).map { command in
            switch command {
            case let .move(point):
                "M \(format(point.x)) \(format(point.y))"
            case let .line(point):
                "L \(format(point.x)) \(format(point.y))"
            case let .quadCurve(point, control):
                "Q \(format(control.x)) \(format(control.y)) \(format(point.x)) \(format(point.y))"
            }
        }
        .joined(separator: " ")
    }

    private static func svgGrid(size: CGSize) -> String {
        func pathData(step: CGFloat) -> String {
            var commands: [String] = []
            var x: CGFloat = 0
            while x <= size.width {
                commands.append("M \(format(x)) 0 L \(format(x)) \(format(size.height))")
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                commands.append("M 0 \(format(y)) L \(format(size.width)) \(format(y))")
                y += step
            }
            return commands.joined(separator: " ")
        }

        return """
        <g data-kind="grid" aria-hidden="true">
          <path d="\(pathData(step: 24))" fill="none" stroke="#d1d5db" stroke-width="1" opacity="0.42"/>
          <path d="\(pathData(step: 120))" fill="none" stroke="#9ca3af" stroke-width="1" opacity="0.42"/>
        </g>
        """
    }

    private static func rect(_ rect: WhiteboardRect?, size: CGSize) -> CGRect {
        let resolved = (rect ?? .defaultBox).clamped()
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

    private static func nsStrokeColor(for ink: WhiteboardInk) -> NSColor {
        switch ink {
        case .black: .labelColor
        case .blue: .systemBlue
        case .green: .systemGreen
        case .orange: .systemOrange
        case .red: .systemRed
        case .purple: .systemPurple
        }
    }

    private static func nsFillColor(for fill: WhiteboardFill) -> NSColor {
        switch fill {
        case .clear: .clear
        case .white: .white
        case .yellow: NSColor.systemYellow.withAlphaComponent(0.85)
        case .blue: NSColor.systemBlue.withAlphaComponent(0.16)
        case .green: NSColor.systemGreen.withAlphaComponent(0.18)
        case .orange: NSColor.systemOrange.withAlphaComponent(0.22)
        case .red: NSColor.systemRed.withAlphaComponent(0.16)
        case .purple: NSColor.systemPurple.withAlphaComponent(0.16)
        }
    }

    private static func svgStrokeColor(for ink: WhiteboardInk) -> String {
        switch ink {
        case .black: "#111827"
        case .blue: "#0a84ff"
        case .green: "#34c759"
        case .orange: "#ff9f0a"
        case .red: "#ff453a"
        case .purple: "#bf5af2"
        }
    }

    private static func svgFillColor(for fill: WhiteboardFill) -> String {
        switch fill {
        case .clear: "none"
        case .white: "#ffffff"
        case .yellow: "#ffe66d"
        case .blue: "#d8ecff"
        case .green: "#ddf8df"
        case .orange: "#ffe4bc"
        case .red: "#ffd9d7"
        case .purple: "#f0ddff"
        }
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
