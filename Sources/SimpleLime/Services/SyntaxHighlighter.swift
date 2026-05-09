import AppKit
import Foundation
import STTextView

enum SyntaxHighlighter {
    private static let complexHighlightCharacterLimit = 250_000

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
        case .plain:
            break
        default:
            applyCode(to: storage, text: string, language: language, baseFont: baseFont)
        }

        storage?.endEditing()
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
        case .plain:
            break
        default:
            applyCode(to: textView, text: string, language: language, baseFont: baseFont)
        }
    }

    private static func applyMarkdown(to storage: NSTextStorage?, text: String, baseFont: NSFont) {
        applyPattern("(?m)^#{1,6}\\s.*$", to: storage, text: text) { range in
            let levelText = (text as NSString).substring(with: range)
            let level = levelText.prefix { $0 == "#" }.count
            let size = max(baseFont.pointSize + CGFloat(7 - level), baseFont.pointSize)
            return [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor.systemBlue
            ]
        }

        applyPattern("(?m)^>.*$", to: storage, text: text) { _ in
            [.foregroundColor: NSColor.systemTeal]
        }

        applyPattern("(?m)^\\s*[-*+]\\s+", to: storage, text: text) { _ in
            [.foregroundColor: NSColor.systemOrange]
        }

        applyPattern("`[^`]+`", to: storage, text: text) { _ in
            [
                .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .medium),
                .foregroundColor: NSColor.systemPurple
            ]
        }

        applyPattern("\\*\\*[^*]+\\*\\*", to: storage, text: text) { _ in
            [.font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .bold)]
        }

        applyPattern("https?://[^\\s)]+", to: storage, text: text) { _ in
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
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'", to: storage, text: text) { _ in
            [.foregroundColor: NSColor.systemRed]
        }

        applyPattern("\\b\\d+(?:\\.\\d+)?\\b", to: storage, text: text) { _ in
            [.foregroundColor: NSColor.systemOrange]
        }

        applyPattern(commentPattern(for: language), to: storage, text: text) { _ in
            [.foregroundColor: NSColor.systemGreen]
        }

        let keywords = keywordPattern(for: language)
        if !keywords.isEmpty {
            applyPattern("\\b(\(keywords))\\b", to: storage, text: text) { _ in
                [
                    .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .semibold),
                    .foregroundColor: NSColor.systemBlue
                ]
            }
        }
    }

    private static func applyMarkdown(to textView: STTextView, text: String, baseFont: NSFont) {
        applyPattern("(?m)^#{1,6}\\s.*$", to: textView, text: text) { range in
            let levelText = (text as NSString).substring(with: range)
            let level = levelText.prefix { $0 == "#" }.count
            let size = max(baseFont.pointSize + CGFloat(7 - level), baseFont.pointSize)
            return [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor.systemBlue
            ]
        }

        applyPattern("(?m)^>.*$", to: textView, text: text) { _ in
            [.foregroundColor: NSColor.systemTeal]
        }

        applyPattern("(?m)^\\s*[-*+]\\s+", to: textView, text: text) { _ in
            [.foregroundColor: NSColor.systemOrange]
        }

        applyPattern("`[^`]+`", to: textView, text: text) { _ in
            [
                .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .medium),
                .foregroundColor: NSColor.systemPurple
            ]
        }

        applyPattern("\\*\\*[^*]+\\*\\*", to: textView, text: text) { _ in
            [.font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .bold)]
        }

        applyPattern("https?://[^\\s)]+", to: textView, text: text) { _ in
            [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        }
    }

    private static func applyCode(to textView: STTextView, text: String, language: EditorLanguage, baseFont: NSFont) {
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'", to: textView, text: text) { _ in
            [.foregroundColor: NSColor.systemRed]
        }

        applyPattern("\\b\\d+(?:\\.\\d+)?\\b", to: textView, text: text) { _ in
            [.foregroundColor: NSColor.systemOrange]
        }

        applyPattern(commentPattern(for: language), to: textView, text: text) { _ in
            [.foregroundColor: NSColor.systemGreen]
        }

        let keywords = keywordPattern(for: language)
        if !keywords.isEmpty {
            applyPattern("\\b(\(keywords))\\b", to: textView, text: text) { _ in
                [
                    .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .semibold),
                    .foregroundColor: NSColor.systemBlue
                ]
            }
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
        case .plain, .markdown:
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
        to storage: NSTextStorage?,
        text: String,
        attributes: (NSRange) -> [NSAttributedString.Key: Any]
    ) {
        guard !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let range = match?.range, range.location != NSNotFound else { return }
            storage?.addAttributes(attributes(range), range: range)
        }
    }

    private static func applyPattern(
        _ pattern: String,
        to textView: STTextView,
        text: String,
        attributes: (NSRange) -> [NSAttributedString.Key: Any]
    ) {
        guard !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let range = match?.range, range.location != NSNotFound else { return }
            textView.addAttributes(attributes(range), range: range)
        }
    }
}
