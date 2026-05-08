import AppKit

extension NSTextView {
    var editorLineHeight: CGFloat {
        guard let font else { return 18 }
        return max(1, ceil(font.ascender - font.descender + font.leading))
    }

    func editorCurrentLineRect() -> NSRect? {
        guard let layoutManager,
              let textContainer else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)

        let selectedRange = selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
        let nsText = string as NSString
        let location = min(max(0, selectedRange.location), nsText.length)
        let origin = textContainerOrigin

        guard nsText.length > 0 else {
            return NSRect(
                x: origin.x,
                y: origin.y,
                width: visibleRect.width,
                height: editorLineHeight
            )
        }

        if location == nsText.length, nsText.endsWithLineBreak {
            let extraLineRect = layoutManager.extraLineFragmentRect
            if !extraLineRect.isEmpty, extraLineRect.height > 0 {
                return NSRect(
                    x: extraLineRect.minX + origin.x,
                    y: extraLineRect.minY + origin.y,
                    width: max(extraLineRect.width, visibleRect.width),
                    height: extraLineRect.height
                )
            }

            let lastGlyphIndex = max(0, layoutManager.numberOfGlyphs - 1)
            let lastLineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
            return NSRect(
                x: origin.x,
                y: lastLineRect.maxY + origin.y,
                width: visibleRect.width,
                height: editorLineHeight
            )
        }

        let lineLocation = min(location, nsText.length - 1)
        let lineRange = nsText.lineRange(for: NSRange(location: lineLocation, length: 0))
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: lineRange,
            actualCharacterRange: nil
        )

        guard glyphRange.length > 0 else {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineLocation)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            return NSRect(
                x: lineRect.minX + origin.x,
                y: lineRect.minY + origin.y,
                width: max(lineRect.width, visibleRect.width),
                height: lineRect.height
            )
        }

        var unionRect: NSRect?
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
            let translated = NSRect(
                x: rect.minX + origin.x,
                y: rect.minY + origin.y,
                width: max(rect.width, self.visibleRect.width),
                height: rect.height
            )
            unionRect = unionRect.map { $0.union(translated) } ?? translated
        }

        guard let unionRect else { return nil }

        return NSRect(
            x: unionRect.minX,
            y: unionRect.minY,
            width: max(unionRect.width, visibleRect.width),
            height: unionRect.height
        )
    }
}

private extension NSString {
    var endsWithLineBreak: Bool {
        guard length > 0 else { return false }
        let lastCharacter = character(at: length - 1)
        return lastCharacter == 10 || lastCharacter == 13
    }
}
