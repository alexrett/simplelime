import AppKit

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let rulerWidth: CGFloat = 46

    override var isFlipped: Bool {
        true
    }

    override var requiredThickness: CGFloat {
        rulerWidth
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = rulerWidth

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateLineNumbers),
            name: NSText.didChangeNotification,
            object: textView
        )

        if let contentView = textView.enclosingScrollView?.contentView {
            contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(invalidateLineNumbers),
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func invalidateLineNumbers() {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let nsText = textView.string as NSString

        drawCurrentLineBackground(textView: textView, visibleRect: visibleRect)
        drawLineNumbers(
            in: characterRange,
            text: nsText,
            layoutManager: layoutManager,
            textView: textView,
            visibleRect: visibleRect
        )
    }

    private func drawCurrentLineBackground(textView: NSTextView, visibleRect: NSRect) {
        guard let lineRect = textView.editorCurrentLineRect() else {
            return
        }

        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        NSRect(
            x: 0,
            y: lineRect.minY - visibleRect.minY,
            width: bounds.width,
            height: lineRect.height
        ).fill()
    }

    private func drawLineNumbers(
        in visibleCharacterRange: NSRange,
        text nsText: NSString,
        layoutManager: NSLayoutManager,
        textView: NSTextView,
        visibleRect: NSRect
    ) {
        if nsText.length == 0 {
            draw(number: 1, y: textView.textContainerInset.height - visibleRect.minY)
            return
        }

        var lineNumber = 1
        var index = 0
        let visibleEnd = visibleCharacterRange.location + visibleCharacterRange.length

        while index < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: index, length: 0))
            let lineEnd = lineRange.location + lineRange.length

            if lineEnd >= visibleCharacterRange.location, lineRange.location <= visibleEnd {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(lineRange.location, nsText.length - 1))
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let y = lineRect.minY + textView.textContainerInset.height - visibleRect.minY
                draw(number: lineNumber, y: y)
            }

            if lineEnd <= index {
                break
            }

            index = lineEnd
            lineNumber += 1
        }

        if nsText.length > 0, nsText.character(at: nsText.length - 1) == 10 {
            let lastGlyphIndex = max(0, layoutManager.numberOfGlyphs - 1)
            let lastLineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
            draw(number: lineNumber, y: lastLineRect.maxY + textView.textContainerInset.height - visibleRect.minY)
        }
    }

    private func draw(number: Int, y: CGFloat) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        let text = "\(number)" as NSString
        let lineHeight = numberFont.ascender - numberFont.descender + numberFont.leading
        text.draw(
            in: NSRect(x: 0, y: y + 2, width: rulerWidth - 10, height: lineHeight),
            withAttributes: attributes
        )
    }
}
