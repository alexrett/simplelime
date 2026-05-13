import AppKit
import Foundation
import STTextView

enum SyntaxHighlighter {
    private static let complexHighlightCharacterLimit = 250_000
    private typealias AttributeApplicator = ([NSAttributedString.Key: Any], NSRange) -> Void

    private struct MarkdownFence {
        let fullRange: NSRange
        let openingRange: NSRange
        let contentRange: NSRange
        let closingRange: NSRange?
        let language: String
    }

    static func apply(to textView: NSTextView, language: EditorLanguage, fontSize: CGFloat) {
        let storage = textView.textStorage
        let string = textView.string
        let fullRange = NSRange(location: 0, length: (string as NSString).length)

        guard fullRange.length > 0 else {
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            return
        }

        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let firstParagraph = firstParagraphStyle(from: paragraph)

        storage?.beginEditing()
        storage?.setAttributes(
            [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ],
            range: fullRange
        )
        storage?.addAttributes([.paragraphStyle: firstParagraph], range: firstParagraphRange(in: string))

        guard fullRange.length <= complexHighlightCharacterLimit else {
            storage?.endEditing()
            return
        }

        switch language {
        case .markdown:
            applyMarkdown(to: storage, text: string, baseFont: baseFont)
        case .plain, .yaml, .csv, .tsv, .image, .pdf, .hex:
            break
        default:
            applyCode(to: storage, text: string, language: language, baseFont: baseFont)
        }

        applyTypographicDashMarks(text: string) { attributes, range in
            storage?.addAttributes(attributes, range: range)
        }

        storage?.endEditing()
    }

    static func attributedLine(
        _ text: String,
        language: EditorLanguage,
        fontSize: CGFloat
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2

        guard fullRange.length > 0 else {
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph
                ]
            )
        }

        attributed.setAttributes(
            [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ],
            range: fullRange
        )

        if fullRange.length <= complexHighlightCharacterLimit {
            switch language {
            case .markdown:
                applyMarkdown(text: text, baseFont: baseFont) { attributes, range in
                    attributed.addAttributes(attributes, range: range)
                }
            case .plain, .yaml, .csv, .tsv, .image, .pdf, .hex:
                break
            default:
                applyCode(text: text, language: language, baseFont: baseFont) { attributes, range in
                    attributed.addAttributes(attributes, range: range)
                }
            }
        }

        applyTypographicDashMarks(text: text) { attributes, range in
            attributed.addAttributes(attributes, range: range)
        }

        return attributed
    }

    @MainActor
    static func apply(to textView: STTextView, language: EditorLanguage, fontSize: CGFloat) {
        let string = textView.text ?? ""
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let firstParagraph = firstParagraphStyle(from: paragraph)

        textView.font = baseFont
        textView.textColor = .labelColor
        textView.defaultParagraphStyle = paragraph

        guard fullRange.length > 0 else {
            return
        }

        textView.setAttributes(
            [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ],
            range: fullRange
        )
        textView.addAttributes([.paragraphStyle: firstParagraph], range: firstParagraphRange(in: string))

        guard fullRange.length <= complexHighlightCharacterLimit else {
            return
        }

        switch language {
        case .markdown:
            applyMarkdown(to: textView, text: string, baseFont: baseFont)
        case .plain, .yaml, .csv, .tsv, .image, .pdf, .hex:
            break
        default:
            applyCode(to: textView, text: string, language: language, baseFont: baseFont)
        }

        applyTypographicDashMarks(text: string) { attributes, range in
            textView.addAttributes(attributes, range: range)
        }
    }

    @MainActor
    static func applyBaseFormatting(to textView: STTextView, fontSize: CGFloat) {
        let string = textView.text ?? ""
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2

        textView.font = baseFont
        textView.textColor = .labelColor
        textView.defaultParagraphStyle = paragraph

        guard fullRange.length > 0 else {
            return
        }

        textView.setAttributes(
            [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ],
            range: fullRange
        )
    }

    private static func applyMarkdown(to storage: NSTextStorage?, text: String, baseFont: NSFont) {
        applyMarkdown(text: text, baseFont: baseFont) { attributes, range in
            storage?.addAttributes(attributes, range: range)
        }
    }

    private static func applyMarkdown(text: String, baseFont: NSFont, addAttributes: AttributeApplicator) {
        let fences = markdownFences(in: text)
        let excludedRanges = fences.map(\.fullRange)
        let codeFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        let fenceFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .medium)

        for fence in fences {
            addAttributes(
                [
                    .font: fenceFont,
                    .foregroundColor: NSColor.secondaryLabelColor
                ],
                fence.openingRange
            )

            if fence.contentRange.length > 0 {
                addAttributes(
                    [
                        .font: codeFont,
                        .foregroundColor: NSColor.labelColor
                    ],
                    fence.contentRange
                )

                if let language = codeLanguage(forMarkdownFenceLanguage: fence.language) {
                    applyCode(text: text, language: language, baseFont: baseFont, range: fence.contentRange, addAttributes: addAttributes)
                }
            }

            if let closingRange = fence.closingRange {
                addAttributes(
                    [
                        .font: fenceFont,
                        .foregroundColor: NSColor.secondaryLabelColor
                    ],
                    closingRange
                )
            }
        }

        applyPattern("(?m)^#{1,6}\\s.*$", text: text, excluding: excludedRanges, addAttributes: addAttributes) { range in
            let levelText = (text as NSString).substring(with: range)
            let level = levelText.prefix { $0 == "#" }.count
            let size = max(baseFont.pointSize + CGFloat(7 - level), baseFont.pointSize)
            return [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor.systemBlue
            ]
        }

        applyPattern("(?m)^>.*$", text: text, excluding: excludedRanges, addAttributes: addAttributes) { _ in
            [.foregroundColor: NSColor.systemTeal]
        }

        applyPattern("(?m)^\\s*[-*+]\\s+", text: text, excluding: excludedRanges, addAttributes: addAttributes) { _ in
            [.foregroundColor: NSColor.systemOrange]
        }

        applyPattern("(?<!`)`[^`\\n]+`(?!`)", text: text, excluding: excludedRanges, addAttributes: addAttributes) { _ in
            [
                .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .medium),
                .foregroundColor: NSColor.systemPurple
            ]
        }

        applyPattern("\\*\\*[^*\\n]+\\*\\*", text: text, excluding: excludedRanges, addAttributes: addAttributes) { _ in
            [.font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .bold)]
        }

        applyPattern("https?://[^\\s)]+", text: text, excluding: excludedRanges, addAttributes: addAttributes) { _ in
            [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        }
    }

    private static func firstParagraphStyle(from base: NSParagraphStyle) -> NSParagraphStyle {
        let paragraph = base.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = 12
        return paragraph
    }

    private static func firstParagraphRange(in text: String) -> NSRange {
        let nsText = text as NSString
        guard nsText.length > 0 else {
            return NSRange(location: 0, length: 0)
        }

        return nsText.paragraphRange(for: NSRange(location: 0, length: 0))
    }

    private static func applyCode(to storage: NSTextStorage?, text: String, language: EditorLanguage, baseFont: NSFont) {
        applyCode(text: text, language: language, baseFont: baseFont) { attributes, range in
            storage?.addAttributes(attributes, range: range)
        }
    }

    private static func applyCode(
        text: String,
        language: EditorLanguage,
        baseFont: NSFont,
        range: NSRange? = nil,
        addAttributes: AttributeApplicator
    ) {
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'", text: text, range: range, addAttributes: addAttributes) { _ in
            [.foregroundColor: NSColor.systemRed]
        }

        applyPattern("\\b\\d+(?:\\.\\d+)?\\b", text: text, range: range, addAttributes: addAttributes) { _ in
            [.foregroundColor: NSColor.systemOrange]
        }

        applyPattern(commentPattern(for: language), text: text, range: range, addAttributes: addAttributes) { _ in
            [.foregroundColor: NSColor.systemGreen]
        }

        let keywords = keywordPattern(for: language)
        if !keywords.isEmpty {
            applyPattern("\\b(\(keywords))\\b", text: text, range: range, addAttributes: addAttributes) { _ in
                [
                    .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .semibold),
                    .foregroundColor: NSColor.systemBlue
                ]
            }
        }
    }

    private static func applyMarkdown(to textView: STTextView, text: String, baseFont: NSFont) {
        applyMarkdown(text: text, baseFont: baseFont) { attributes, range in
            textView.addAttributes(attributes, range: range)
        }
    }

    private static func applyCode(to textView: STTextView, text: String, language: EditorLanguage, baseFont: NSFont) {
        applyCode(text: text, language: language, baseFont: baseFont) { attributes, range in
            textView.addAttributes(attributes, range: range)
        }
    }

    private static func applyTypographicDashMarks(text: String, addAttributes: AttributeApplicator) {
        let nsText = text as NSString
        var location = 0

        while location < nsText.length {
            let range = nsText.rangeOfComposedCharacterSequence(at: location)
            let token = nsText.substring(with: range)

            if isTypographicDash(token) {
                addAttributes(
                    [
                        .foregroundColor: NSColor.systemPink,
                        .backgroundColor: NSColor.systemPink.withAlphaComponent(0.13),
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: NSColor.systemPink
                    ],
                    range
                )
            }

            let nextLocation = range.location + max(range.length, 1)
            guard nextLocation > location else { break }
            location = nextLocation
        }
    }

    private static func isTypographicDash(_ value: String) -> Bool {
        switch value {
        case "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}":
            return true
        default:
            return false
        }
    }

    private static func keywordPattern(for language: EditorLanguage) -> String {
        switch language {
        case .swift:
            return "actor|as|async|await|case|catch|class|defer|else|enum|extension|false|for|func|guard|if|import|in|init|let|nil|private|protocol|public|return|self|static|struct|switch|throw|throws|true|try|var|while"
        case .javascript, .typescript:
            return "async|await|break|case|catch|class|const|continue|default|else|export|false|finally|for|from|function|if|import|in|let|new|null|return|switch|this|throw|true|try|type|undefined|var|while"
        case .json:
            return "true|false|null"
        case .html:
            return "html|head|body|script|style|div|span|section|article|main|button|input|meta|link|title"
        case .css:
            return "align-items|background|border|color|display|flex|font|gap|grid|height|justify-content|margin|padding|position|width"
        case .python:
            return "and|as|async|await|break|class|continue|def|elif|else|except|False|finally|for|from|if|import|in|is|lambda|None|not|or|pass|raise|return|True|try|while|with|yield"
        case .ruby:
            return "begin|case|class|def|do|else|elsif|end|false|if|module|nil|private|protected|public|require|rescue|return|self|true|unless|when|while|yield"
        case .go:
            return "break|case|chan|const|continue|defer|default|else|fallthrough|for|func|go|goto|if|import|interface|map|package|range|return|select|struct|switch|type|var"
        case .rust:
            return "as|async|await|break|const|continue|crate|else|enum|extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|true|type|unsafe|use|where|while"
        case .shell:
            return "case|do|done|elif|else|esac|fi|for|function|if|in|then|while"
        case .plain, .markdown, .yaml, .csv, .tsv, .image, .pdf, .hex, .drawing:
            return ""
        }
    }

    private static func commentPattern(for language: EditorLanguage) -> String {
        switch language {
        case .python, .ruby, .shell:
            return "(?m)#.*$"
        case .html:
            return "<!--[\\s\\S]*?-->"
        case .css:
            return "/\\*[\\s\\S]*?\\*/"
        default:
            return "(?m)//.*$|/\\*[\\s\\S]*?\\*/"
        }
    }

    private static func applyPattern(
        _ pattern: String,
        text: String,
        range: NSRange? = nil,
        excluding excludedRanges: [NSRange] = [],
        addAttributes: AttributeApplicator,
        attributes: (NSRange) -> [NSAttributedString.Key: Any]
    ) {
        guard !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }

        let nsText = text as NSString
        let searchRange = range ?? NSRange(location: 0, length: nsText.length)
        regex.enumerateMatches(in: text, range: searchRange) { match, _, _ in
            guard let range = match?.range, range.location != NSNotFound else { return }
            guard !range.intersectsAny(excludedRanges) else { return }
            addAttributes(attributes(range), range)
        }
    }

    private static func markdownFences(in text: String) -> [MarkdownFence] {
        let nsText = text as NSString
        var fences: [MarkdownFence] = []
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let line = nsText.substring(with: lineRange)

            guard let opening = markdownFenceOpening(line) else {
                location = nextLineLocation(after: lineRange, textLength: nsText.length)
                continue
            }

            let contentStart = lineRange.location + lineRange.length
            var scanLocation = contentStart
            var closingRange: NSRange?

            while scanLocation < nsText.length {
                let currentLineRange = nsText.lineRange(for: NSRange(location: scanLocation, length: 0))
                let currentLine = nsText.substring(with: currentLineRange)
                if markdownFenceClosing(currentLine, matches: opening.marker) {
                    closingRange = currentLineRange
                    break
                }
                scanLocation = nextLineLocation(after: currentLineRange, textLength: nsText.length)
            }

            let contentEnd = closingRange?.location ?? nsText.length
            let fullEnd = closingRange.map { $0.location + $0.length } ?? nsText.length
            fences.append(
                MarkdownFence(
                    fullRange: NSRange(location: lineRange.location, length: fullEnd - lineRange.location),
                    openingRange: lineRange,
                    contentRange: NSRange(location: contentStart, length: max(0, contentEnd - contentStart)),
                    closingRange: closingRange,
                    language: opening.language
                )
            )
            location = fullEnd
        }

        return fences
    }

    private static func markdownFenceOpening(_ line: String) -> (marker: String, language: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }

        let markerLength = trimmed.prefix { $0 == first }.count
        guard markerLength >= 3 else { return nil }

        let marker = String(repeating: String(first), count: markerLength)
        let language = trimmed
            .dropFirst(markerLength)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? ""

        return (marker, language)
    }

    private static func markdownFenceClosing(_ line: String, matches marker: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = marker.first,
              trimmed.first == first else {
            return false
        }

        return trimmed.prefix { $0 == first }.count >= marker.count
    }

    private static func nextLineLocation(after lineRange: NSRange, textLength: Int) -> Int {
        let next = lineRange.location + max(lineRange.length, 1)
        return min(next, textLength)
    }

    private static func codeLanguage(forMarkdownFenceLanguage language: String) -> EditorLanguage? {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let fileExtension: String
        switch normalized {
        case "javascript", "js", "jsx", "mjs", "cjs":
            fileExtension = "js"
        case "typescript", "ts", "tsx":
            fileExtension = "ts"
        case "html", "xml":
            fileExtension = "html"
        case "css", "scss", "sass":
            fileExtension = "css"
        case "python", "py":
            fileExtension = "py"
        case "ruby", "rb":
            fileExtension = "rb"
        case "golang", "go":
            fileExtension = "go"
        case "rust", "rs":
            fileExtension = "rs"
        case "shell", "bash", "zsh", "fish", "sh":
            fileExtension = "sh"
        case "json", "jsonl":
            fileExtension = "json"
        case "yaml", "yml":
            fileExtension = "yaml"
        case "swift":
            fileExtension = "swift"
        default:
            return nil
        }

        let detected = EditorLanguage.detect(fileName: "block.\(fileExtension)")
        return detected == .plain || detected == .markdown ? nil : detected
    }
}

private extension NSRange {
    func intersectsAny(_ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange(self, $0).length > 0 }
    }
}
