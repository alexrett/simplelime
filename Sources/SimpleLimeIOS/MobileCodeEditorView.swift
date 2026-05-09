import STTextView
import SwiftUI
import UIKit

struct MobileCodeEditorView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectionRanges: [TextRange]

    let language: EditorLanguage
    let fontSize: CGFloat
    let wrapsLines: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> STTextView {
        let textView = STTextView()
        textView.textDelegate = context.coordinator
        textView.allowsUndo = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.alwaysBounceHorizontal = true
        textView.showsLineNumbers = true
        textView.highlightSelectedLine = true
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 24)
        applyChrome(to: textView)
        return textView
    }

    func updateUIView(_ textView: STTextView, context: Context) {
        context.coordinator.parent = self
        applyChrome(to: textView)

        context.coordinator.isProgrammaticUpdate = true
        if textView.text != text {
            textView.text = text
        }
        applySelection(selectionRanges, to: textView)
        context.coordinator.isProgrammaticUpdate = false

        MobileSyntaxHighlighter.apply(language: language, to: textView, fontSize: fontSize)
    }

    private func applyChrome(to textView: STTextView) {
        let background = UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
        textView.backgroundColor = background
        textView.tintColor = UIColor(red: 0.05, green: 0.52, blue: 1.0, alpha: 1)
        textView.textColor = UIColor(white: 0.86, alpha: 1)
        textView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.isHorizontallyResizable = !wrapsLines
        textView.showsHorizontalScrollIndicator = !wrapsLines
        textView.selectedLineHighlightColor = UIColor(red: 0.10, green: 0.18, blue: 0.30, alpha: 0.72)
        textView.gutterView?.backgroundColor = background
        textView.gutterView?.font = UIFont.monospacedDigitSystemFont(ofSize: max(11, fontSize - 2), weight: .regular)
        textView.gutterView?.textColor = UIColor(white: 0.45, alpha: 1)
        textView.gutterView?.selectedLineTextColor = UIColor(white: 0.72, alpha: 1)
        textView.gutterView?.selectedLineHighlightColor = textView.selectedLineHighlightColor
        textView.gutterView?.separatorColor = UIColor(white: 1, alpha: 0.08)
    }

    private func applySelection(_ ranges: [TextRange], to textView: STTextView) {
        let nsRanges = ranges.map { $0.nsRange }.filter { range in
            range.location != NSNotFound && range.location <= (textView.text as NSString?)?.length ?? 0
        }
        guard !nsRanges.isEmpty else { return }

        if nsRanges.count == 1 {
            textView.textSelection = nsRanges[0]
            textView.scrollRangeToVisible(nsRanges[0])
            return
        }

        let textRanges = nsRanges.compactMap { NSTextRange($0, in: textView.textContentManager) }
        guard !textRanges.isEmpty else { return }
        textView.textLayoutManager.textSelections = [
            NSTextSelection(textRanges, affinity: .downstream, granularity: .character)
        ]
        textView.scrollRangeToVisible(nsRanges[0])
    }

    final class Coordinator: NSObject, STTextViewDelegate {
        var parent: MobileCodeEditorView
        var isProgrammaticUpdate = false

        init(_ parent: MobileCodeEditorView) {
            self.parent = parent
        }

        func textViewDidChangeText(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView = notification.object as? STTextView else { return }
            parent.text = textView.text ?? ""
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView = notification.object as? STTextView else { return }
            let ranges = textView.textLayoutManager.textSelections
                .flatMap(\.textRanges)
                .map { TextRange(NSRange($0, in: textView.textContentManager)) }
            parent.selectionRanges = ranges.isEmpty ? [.zero] : ranges
        }
    }
}

private enum MobileSyntaxHighlighter {
    static func apply(language: EditorLanguage, to textView: STTextView, fontSize: CGFloat) {
        let text = textView.text ?? ""
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else { return }

        let baseFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.setAttributes([
            .font: baseFont,
            .foregroundColor: UIColor(white: 0.86, alpha: 1)
        ], range: fullRange)

        switch language {
        case .markdown:
            applyMarkdown(to: textView, text: text, fontSize: fontSize)
        case .json:
            applyJSON(to: textView, text: text)
        default:
            applyCodeComments(to: textView, text: text)
        }
    }

    private static func applyMarkdown(to textView: STTextView, text: String, fontSize: CGFloat) {
        apply(pattern: #"(?m)^#{1,6}\s+.*$"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.10, green: 0.58, blue: 1.0, alpha: 1),
            .font: UIFont.monospacedSystemFont(ofSize: fontSize + 2, weight: .bold)
        ])
        apply(pattern: #"(?m)^\s*[-*+]\s+"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.95, green: 0.58, blue: 0.18, alpha: 1)
        ])
        apply(pattern: #"`[^`]+`"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.50, green: 0.84, blue: 0.48, alpha: 1)
        ])
    }

    private static func applyJSON(to textView: STTextView, text: String) {
        apply(pattern: #""([^"\\]|\\.)*"(?=\s*:)"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 1.0, green: 0.34, blue: 0.34, alpha: 1)
        ])
        apply(pattern: #"(?<=:)\s*"([^"\\]|\\.)*""#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.55, green: 0.76, blue: 1.0, alpha: 1)
        ])
        apply(pattern: #"\b(true|false|null)\b"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.10, green: 0.58, blue: 1.0, alpha: 1)
        ])
        apply(pattern: #"\b-?\d+(\.\d+)?\b"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(red: 0.95, green: 0.58, blue: 0.18, alpha: 1)
        ])
    }

    private static func applyCodeComments(to textView: STTextView, text: String) {
        apply(pattern: #"(?m)//.*$|#.*$"#, text: text, to: textView, attrs: [
            .foregroundColor: UIColor(white: 0.45, alpha: 1)
        ])
    }

    private static func apply(pattern: String, text: String, to textView: STTextView, attrs: [NSAttributedString.Key: Any]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: (text as NSString).length)
        regex.matches(in: text, range: range).forEach { match in
            textView.addAttributes(attrs, range: match.range)
        }
    }
}
