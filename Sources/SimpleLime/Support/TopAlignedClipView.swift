import AppKit

final class TopAlignedClipView: NSClipView {
    override var isFlipped: Bool { true }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return constrained }

        let documentSize = documentView.frame.size
        let viewportSize = bounds.size

        if documentSize.height <= viewportSize.height {
            constrained.origin.y = 0
        } else {
            constrained.origin.y = min(
                max(constrained.origin.y, 0),
                documentSize.height - viewportSize.height
            )
        }

        if documentSize.width <= viewportSize.width {
            constrained.origin.x = 0
        } else {
            constrained.origin.x = min(
                max(constrained.origin.x, 0),
                documentSize.width - viewportSize.width
            )
        }

        return constrained
    }
}
