import SwiftUI
import WebKit

struct CodeMirrorSourceEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectionRanges: [TextRange]

    let configuration: SourceEditorConfiguration
    let decorations: SourceEditorDecorations
    let callbacks: SourceEditorCallbacks

    static var htmlForTesting: String {
        html
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webConfiguration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "ready")
        contentController.add(context.coordinator, name: "textDidChange")
        contentController.add(context.coordinator, name: "selectionDidChange")
        contentController.add(context.coordinator, name: "shortcut")
        contentController.add(context.coordinator, name: "visibleLineRange")
        webConfiguration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        callbacks.onRegisterEditorCommandHandler { [weak coordinator = context.coordinator] command in
            coordinator?.perform(command) ?? false
        }
        webView.loadHTMLString(Self.html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyStateIfReady()
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        let controller = nsView.configuration.userContentController
        ["ready", "textDidChange", "selectionDidChange", "shortcut", "visibleLineRange"].forEach {
            controller.removeScriptMessageHandler(forName: $0)
        }
        nsView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: CodeMirrorSourceEditorView
        weak var webView: WKWebView?
        private var isReady = false
        private var lastAppliedText: String?
        private var lastAppliedSelection: [TextRange] = []
        private var lastAppliedViewSignature: String?

        init(_ parent: CodeMirrorSourceEditorView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyStateIfReady()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "ready":
                isReady = true
                applyStateIfReady()
            case "textDidChange":
                guard let value = message.body as? String else { return }
                lastAppliedText = value
                parent.text = value
            case "selectionDidChange":
                guard let body = message.body as? [String: Any] else { return }
                let ranges = Self.selectionRanges(from: body)
                guard !ranges.isEmpty else { return }
                lastAppliedSelection = ranges
                parent.selectionRanges = ranges
            case "shortcut":
                guard let shortcut = message.body as? String else { return }
                handleShortcut(shortcut)
            case "visibleLineRange":
                guard let body = message.body as? [String: Any],
                      let start = body["start"] as? Int,
                      let end = body["end"] as? Int else { return }
                parent.callbacks.onVisibleLineRangeChange(max(1, start)...max(1, end))
            default:
                break
            }
        }

        func applyStateIfReady() {
            guard isReady, let webView else { return }

            let selection = parent.selectionRanges.first ?? TextRange(location: 0, length: 0)
            let viewSignature = parent.viewSignature
            guard lastAppliedText != parent.text ||
                    lastAppliedSelection != parent.selectionRanges ||
                    lastAppliedViewSignature != viewSignature else { return }

            lastAppliedText = parent.text
            lastAppliedSelection = parent.selectionRanges
            lastAppliedViewSignature = viewSignature
            let state: [String: Any] = [
                "text": parent.text,
                "language": parent.configuration.language.rawValue,
                "fontSize": parent.configuration.fontSize,
                "wrapsLines": parent.configuration.wrapsLines,
                "columnGuide": parent.configuration.columnGuide,
                "editable": parent.configuration.isEditable,
                "focusModeEnabled": parent.configuration.focusModeEnabled,
                "typewriterModeEnabled": parent.configuration.typewriterModeEnabled,
                "syntaxHighlightingEnabled": parent.configuration.syntaxHighlightingEnabled,
                "selectionLocation": selection.location,
                "selectionLength": selection.length,
                "selectionRanges": parent.webSelectionRangesPayload,
                "foldedRanges": parent.webFoldedRangesPayload,
                "decorations": parent.webDecorationsPayload
            ]
            guard let json = Self.jsonLiteral(state) else { return }
            webView.evaluateJavaScript("window.simplelimeSetState(\(json));")
        }

        func perform(_ command: EditorCommand) -> Bool {
            switch command {
            case .transform(let transform):
                guard let command = Self.codeMirrorTransformCommand(for: transform) else {
                    return false
                }
                webView?.evaluateJavaScript("window.simplelimeCommand && window.simplelimeCommand('\(command)');")
                return true
            case .markdown(let command):
                webView?.evaluateJavaScript("window.simplelimeCommand && window.simplelimeCommand('markdown:\(command.rawValue)');")
                return true
            case .deleteLine:
                webView?.evaluateJavaScript("window.simplelimeCommand && window.simplelimeCommand('deleteLine');")
                return true
            case .moveLineUp:
                webView?.evaluateJavaScript("window.simplelimeCommand && window.simplelimeCommand('moveLineUp');")
                return true
            case .moveLineDown:
                webView?.evaluateJavaScript("window.simplelimeCommand && window.simplelimeCommand('moveLineDown');")
                return true
            case .splitSelectionIntoLines:
                webView?.evaluateJavaScript("window.simplelimeCommand && window.simplelimeCommand('splitSelectionIntoLines');")
                return true
            case .expandSelectionToLine:
                webView?.evaluateJavaScript("window.simplelimeCommand && window.simplelimeCommand('expandSelectionToLine');")
                return true
            case .indentLines:
                webView?.evaluateJavaScript("window.simplelimeCommand && window.simplelimeCommand('indent');")
                return true
            case .outdentLines:
                webView?.evaluateJavaScript("window.simplelimeCommand && window.simplelimeCommand('outdent');")
                return true
            case .toggleComment:
                webView?.evaluateJavaScript("window.simplelimeCommand && window.simplelimeCommand('toggleComment');")
                return true
            }
        }

        private static func codeMirrorTransformCommand(for transform: TextTransform) -> String? {
            switch transform {
            case .uppercase, .lowercase, .titlecase, .swapCase, .reverseSelection,
                    .sortLines, .uniqueLines, .trimTrailingWhitespace, .duplicateLine, .joinLines:
                return "transform:\(transform.rawValue)"
            case .formatJSON, .minifyJSON, .formatMarkdownTables:
                return nil
            }
        }

        private func handleShortcut(_ rawValue: String) {
            switch rawValue {
            case "showFind":
                _ = parent.callbacks.onShortcut(.showFind)
            case "showReplace":
                _ = parent.callbacks.onShortcut(.showReplace)
            case "findNext":
                _ = parent.callbacks.onShortcut(.findNext)
            case "findPrevious":
                _ = parent.callbacks.onShortcut(.findPrevious)
            case "toggleComment":
                _ = parent.callbacks.onShortcut(.editorCommand(.toggleComment))
            case "increaseFontSize":
                _ = parent.callbacks.onShortcut(.increaseFontSize)
            case "decreaseFontSize":
                _ = parent.callbacks.onShortcut(.decreaseFontSize)
            case "escape":
                _ = parent.callbacks.onShortcut(.escape)
            default:
                break
            }
        }

        private static func jsonLiteral(_ value: Any) -> String? {
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let string = String(data: data, encoding: .utf8) else { return nil }
            return string
        }

        private static func selectionRanges(from body: [String: Any]) -> [TextRange] {
            if let rawRanges = body["ranges"] as? [[String: Any]] {
                let ranges = rawRanges.compactMap { rawRange -> TextRange? in
                    guard let location = rawRange["location"] as? Int,
                          let length = rawRange["length"] as? Int else { return nil }
                    return TextRange(location: location, length: length)
                }
                if !ranges.isEmpty {
                    return ranges
                }
            }

            guard let location = body["location"] as? Int,
                  let length = body["length"] as? Int else { return [] }
            return [TextRange(location: location, length: length)]
        }
    }

    private var webSelectionRangesPayload: [[String: Int]] {
        SourceEditorWebSelection
            .normalizedRanges(selectionRanges, textLength: (text as NSString).length)
            .map { range in
                [
                    "location": range.location,
                    "length": range.length
                ]
            }
    }

    private var webDecorationsPayload: [[String: Any]] {
        decorations
            .webDecorations(textLength: (text as NSString).length)
            .map { decoration in
                var payload: [String: Any] = [
                    "kind": decoration.kind.rawValue,
                    "location": decoration.range.location,
                    "length": decoration.range.length
                ]
                if let color = decoration.color {
                    payload["color"] = color
                }
                if let label = decoration.label {
                    payload["label"] = label
                }
                return payload
            }
    }

    private var webFoldedRangesPayload: [[String: Any]] {
        configuration.foldedRanges.map { range in
            [
                "startLine": range.startLine,
                "endLine": range.endLine,
                "title": range.title,
                "foldedLineCount": range.foldedLineCount
            ]
        }
    }

    private var viewSignature: String {
        let decorationSignature = decorations
            .webDecorations(textLength: (text as NSString).length)
            .map { decoration in
                [
                    decoration.kind.rawValue,
                    "\(decoration.range.location)",
                    "\(decoration.range.length)",
                    decoration.color ?? "",
                    decoration.label ?? ""
                ].joined(separator: ":")
            }
            .joined(separator: "|")
        let foldedSignature = configuration.foldedRanges
            .map { "\($0.startLine):\($0.endLine):\($0.title)" }
            .joined(separator: "|")
        return [
            configuration.language.rawValue,
            "\(configuration.fontSize)",
            "\(configuration.wrapsLines)",
            "\(configuration.columnGuide)",
            "\(configuration.isEditable)",
            "\(configuration.focusModeEnabled)",
            "\(configuration.typewriterModeEnabled)",
            "\(configuration.syntaxHighlightingEnabled)",
            foldedSignature,
            decorationSignature
        ].joined(separator: "#")
    }

    private static let html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        html, body, #editor {
          height: 100%;
          margin: 0;
          overflow: hidden;
          background: #1f1f1f;
          color: #e8e8e8;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        }
        .cm-editor, .cm-scroller, textarea {
          height: 100%;
        }
        .cm-editor {
          background: #1f1f1f;
          color: #e8e8e8;
        }
        .cm-content, textarea {
          font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        }
        textarea {
          box-sizing: border-box;
          width: 100%;
          resize: none;
          border: 0;
          outline: none;
          background: #1f1f1f;
          color: #e8e8e8;
          padding: 12px 16px;
          line-height: 1.45;
        }
        textarea.sl-has-column-guide {
          --sl-column-guide: 0ch;
          background-image: linear-gradient(
            to right,
            transparent calc(var(--sl-column-guide) - 1px),
            rgba(142, 142, 147, 0.38) calc(var(--sl-column-guide) - 1px),
            rgba(142, 142, 147, 0.38) var(--sl-column-guide),
            transparent var(--sl-column-guide)
          );
          background-position: 16px 0;
          background-repeat: repeat-y;
        }
        textarea.sl-typewriter-mode {
          padding-top: 35vh;
          padding-bottom: 35vh;
        }
        textarea.sl-focus-mode {
          caret-color: #0a84ff;
        }
        .cm-lineNumbers .cm-gutterElement,
        .cm-gutters {
          background: #1f1f1f;
          color: #7d7d7d;
          border: 0;
        }
        .cm-activeLine,
        .cm-activeLineGutter {
          background: rgba(10, 132, 255, 0.12);
        }
        .cm-focused {
          outline: none;
        }
        .sl-focus-dimmed {
          opacity: 0.28;
        }
        .sl-folded-block {
          color: #a8a8a8;
          background: rgba(142, 142, 147, 0.12);
          border: 1px solid rgba(142, 142, 147, 0.24);
          border-radius: 4px;
          padding: 0 6px;
        }
        .sl-comment {
          background: rgba(255, 214, 10, 0.22);
          border-radius: 2px;
        }
        .sl-active-comment {
          background: rgba(10, 132, 255, 0.30);
          border-radius: 2px;
        }
        .sl-collaboration-selection {
          border-radius: 2px;
        }
        .sl-collaboration-caret {
          display: inline-block;
          height: 1.25em;
          margin-left: -1px;
          pointer-events: none;
          vertical-align: text-bottom;
          border-left: 2px solid currentColor;
        }
      </style>
    </head>
    <body>
      <div id="editor"></div>
      <script type="module">
        const post = (name, body) => {
          try { window.webkit.messageHandlers[name].postMessage(body); } catch (_error) {}
        };

        let editorView = null;
        let textarea = null;
        let applyingHostState = false;
        let scrollPrimarySelectionIntoView = () => {};
        let currentState = {
          text: "",
          language: "plain",
          fontSize: 14,
          wrapsLines: true,
          columnGuide: 0,
          editable: true,
          focusModeEnabled: false,
          typewriterModeEnabled: false,
          syntaxHighlightingEnabled: true,
          selectionLocation: 0,
          selectionLength: 0,
          selectionRanges: [],
          foldedRanges: [],
          decorations: []
        };

        function reportText(value) {
          if (!applyingHostState) post("textDidChange", value);
        }

        function reportSelection(location, length) {
          if (!applyingHostState) {
            post("selectionDidChange", { location, length });
          }
        }

        function reportSelectionRanges(selection) {
          const ranges = selection.ranges.map((range) => {
            const from = Math.min(range.from, range.to);
            const to = Math.max(range.from, range.to);
            return { location: from, length: to - from };
          });
          const first = ranges[0] || { location: 0, length: 0 };
          if (!applyingHostState) {
            post("selectionDidChange", {
              location: first.location,
              length: first.length,
              ranges
            });
          }
        }

        function reportVisibleRange() {
          if (editorView) {
            const from = editorView.state.doc.lineAt(editorView.viewport.from).number;
            const to = editorView.state.doc.lineAt(editorView.viewport.to).number;
            post("visibleLineRange", { start: from, end: to });
          } else if (textarea) {
            post("visibleLineRange", { start: 1, end: Math.max(1, textarea.value.split("\\n").length) });
          }
        }

        function selectionSignature(hostState) {
          const ranges = Array.isArray(hostState.selectionRanges) && hostState.selectionRanges.length > 0
            ? hostState.selectionRanges
            : [{ location: hostState.selectionLocation || 0, length: hostState.selectionLength || 0 }];
          return ranges.map((range) => {
            const location = Math.max(0, range.location || 0);
            const length = Math.max(0, range.length || 0);
            return `${location}:${length}`;
          }).join("|");
        }

        function scrollTextareaSelectionIntoView() {
          if (!textarea) return;
          const start = textarea.selectionStart || 0;
          const textBeforeSelection = textarea.value.slice(0, start);
          const lineNumber = textBeforeSelection.split("\\n").length;
          const style = window.getComputedStyle(textarea);
          const parsedLineHeight = Number.parseFloat(style.lineHeight);
          const parsedFontSize = Number.parseFloat(style.fontSize);
          const lineHeight = Number.isFinite(parsedLineHeight)
            ? parsedLineHeight
            : Math.max(1, (Number.isFinite(parsedFontSize) ? parsedFontSize : 14) * 1.45);
          const top = Math.max(0, (lineNumber - 1) * lineHeight);
          const bottom = top + lineHeight;
          const visibleTop = textarea.scrollTop;
          const visibleBottom = visibleTop + textarea.clientHeight;
          if (top < visibleTop) {
            textarea.scrollTop = top;
          } else if (bottom > visibleBottom) {
            textarea.scrollTop = Math.max(0, bottom - textarea.clientHeight + lineHeight);
          }
        }

        function shortcutName(event) {
          if (event.key === "Escape") return "escape";
          if (!event.metaKey || event.ctrlKey) return null;
          const key = event.key.toLowerCase();
          if (key === "f" && !event.shiftKey) return "showFind";
          if (key === "r") return "showReplace";
          if (key === "g" && event.shiftKey) return "findPrevious";
          if (key === "g") return "findNext";
          if (key === "/" && !event.shiftKey) return "toggleComment";
          if (key === "+" || key === "=") return "increaseFontSize";
          if (key === "-") return "decreaseFontSize";
          return null;
        }

        function handleShortcut(event) {
          const name = shortcutName(event);
          if (!name) return false;
          event.preventDefault();
          post("shortcut", name);
          return true;
        }

        function extensionForLanguage(language, modules) {
          switch (language) {
          case "json": return modules.json();
          case "javascript": return modules.javascript();
          case "typescript": return modules.javascript({ typescript: true });
          case "html": return modules.html();
          case "css": return modules.css();
          case "markdown": return modules.markdown();
          default: return [];
          }
        }

        async function startCodeMirror() {
          const [
            stateModule,
            viewModule,
            commandsModule,
            searchModule,
            languageModule,
            jsonModule,
            javascriptModule,
            htmlModule,
            cssModule,
            markdownModule
          ] = await Promise.all([
            import("https://esm.sh/@codemirror/state"),
            import("https://esm.sh/@codemirror/view"),
            import("https://esm.sh/@codemirror/commands"),
            import("https://esm.sh/@codemirror/search"),
            import("https://esm.sh/@codemirror/language"),
            import("https://esm.sh/@codemirror/lang-json"),
            import("https://esm.sh/@codemirror/lang-javascript"),
            import("https://esm.sh/@codemirror/lang-html"),
            import("https://esm.sh/@codemirror/lang-css"),
            import("https://esm.sh/@codemirror/lang-markdown")
          ]);

          const modules = {
            json: jsonModule.json,
            javascript: javascriptModule.javascript,
            html: htmlModule.html,
            css: cssModule.css,
            markdown: markdownModule.markdown
          };
          const { EditorState, EditorSelection } = stateModule;
          const {
            EditorView,
            keymap,
            lineNumbers,
            highlightActiveLine,
            highlightActiveLineGutter,
            drawSelection
          } = viewModule;
          const { defaultKeymap, history, historyKeymap, indentMore, indentLess } = commandsModule;
          const { searchKeymap, highlightSelectionMatches } = searchModule;
          const { syntaxHighlighting, defaultHighlightStyle } = languageModule;
          const { Decoration, WidgetType } = viewModule;

          function rgbaFromRGB(color, alpha) {
            if (!color) return `rgba(10, 132, 255, ${alpha})`;
            return color
              .replace(/^rgb\\((.*)\\)$/i, `rgba($1, ${alpha})`);
          }

          class CollaboratorCaretWidget extends WidgetType {
            constructor(color, label) {
              super();
              this.color = color || "rgb(10, 132, 255)";
              this.label = label || "Collaborator";
            }

            eq(other) {
              return other.color === this.color && other.label === this.label;
            }

            toDOM() {
              const element = document.createElement("span");
              element.className = "sl-collaboration-caret";
              element.style.borderLeftColor = this.color;
              element.title = this.label;
              return element;
            }

            ignoreEvent() {
              return true;
            }
          }

          class FoldedBlockWidget extends WidgetType {
            constructor(firstLine, foldedLineCount) {
              super();
              this.firstLine = firstLine || "";
              this.foldedLineCount = Math.max(1, Number(foldedLineCount || 1));
            }

            eq(other) {
              return other.firstLine === this.firstLine && other.foldedLineCount === this.foldedLineCount;
            }

            toDOM() {
              const element = document.createElement("span");
              const suffix = this.foldedLineCount === 1 ? "line" : "lines";
              element.className = "sl-folded-block";
              element.textContent = `${this.firstLine}  ... ${this.foldedLineCount} ${suffix} folded`;
              return element;
            }

            ignoreEvent() {
              return true;
            }
          }

          function decorationExtension(hostState) {
            const docLength = (hostState.text || "").length;
            const ranges = [];
            for (const decoration of hostState.decorations || []) {
              const from = Math.max(0, Math.min(decoration.location || 0, docLength));
              const length = Math.max(0, decoration.length || 0);
              const to = Math.max(from, Math.min(from + length, docLength));
              if (decoration.kind === "comment" && to > from) {
                ranges.push(Decoration.mark({ class: "sl-comment", title: decoration.label || "" }).range(from, to));
              } else if (decoration.kind === "activeComment" && to > from) {
                ranges.push(Decoration.mark({ class: "sl-active-comment", title: decoration.label || "" }).range(from, to));
              } else if (decoration.kind === "collaboratorSelection" && to > from) {
                ranges.push(
                  Decoration.mark({
                    class: "sl-collaboration-selection",
                    attributes: {
                      title: decoration.label || "Collaborator",
                      style: `background-color: ${rgbaFromRGB(decoration.color, 0.24)}; border-bottom: 2px solid ${decoration.color || "rgb(10, 132, 255)"};`
                    }
                  }).range(from, to)
                );
              } else if (decoration.kind === "collaboratorCaret") {
                ranges.push(
                  Decoration.widget({
                    widget: new CollaboratorCaretWidget(decoration.color, decoration.label),
                    side: 1
                  }).range(from)
                );
              }
            }

            return EditorView.decorations.of(Decoration.set(ranges, true));
          }

          function hostSelection(hostState) {
            const docLength = (hostState.text || "").length;
            const rawRanges = Array.isArray(hostState.selectionRanges) && hostState.selectionRanges.length > 0
              ? hostState.selectionRanges
              : [{ location: hostState.selectionLocation || 0, length: hostState.selectionLength || 0 }];
            const ranges = rawRanges.map((range) => {
              const from = Math.max(0, Math.min(range.location || 0, docLength));
              const length = Math.max(0, range.length || 0);
              const to = Math.max(from, Math.min(from + length, docLength));
              return from === to ? EditorSelection.cursor(from) : EditorSelection.range(from, to);
            });
            return EditorSelection.create(ranges.length ? ranges : [EditorSelection.cursor(0)], 0);
          }

          function columnGuideExtension(hostState) {
            const columnGuide = Math.max(0, Math.min(200, Number(hostState.columnGuide || 0)));
            if (columnGuide <= 0) return [];
            return EditorView.theme({
              ".cm-content": {
                position: "relative"
              },
              ".cm-content::before": {
                content: '""',
                position: "absolute",
                top: "0",
                bottom: "0",
                left: `${columnGuide}ch`,
                borderLeft: "1px solid rgba(142, 142, 147, 0.38)",
                pointerEvents: "none"
              }
            });
          }

          function typewriterModeExtension(hostState) {
            if (!hostState.typewriterModeEnabled) return [];
            return EditorView.theme({
              ".cm-scroller": {
                scrollPaddingTop: "35vh",
                scrollPaddingBottom: "35vh"
              },
              ".cm-content": {
                paddingTop: "35vh",
                paddingBottom: "35vh"
              },
              ".cm-gutters": {
                paddingTop: "35vh",
                paddingBottom: "35vh"
              }
            });
          }

          function lineRanges(text) {
            const ranges = [];
            let start = 0;
            while (start <= text.length) {
              const newline = text.indexOf("\\n", start);
              const contentEnd = newline === -1 ? text.length : newline;
              const end = newline === -1 ? contentEnd : newline + 1;
              ranges.push({ start, contentEnd, end });
              if (newline === -1) break;
              start = newline + 1;
            }
            return ranges;
          }

          function focusedBlockBounds(hostState) {
            const text = hostState.text || "";
            const docLength = text.length;
            const rawRanges = Array.isArray(hostState.selectionRanges) && hostState.selectionRanges.length > 0
              ? hostState.selectionRanges
              : [{ location: hostState.selectionLocation || 0, length: hostState.selectionLength || 0 }];
            const cursor = Math.max(0, Math.min((rawRanges[rawRanges.length - 1] || {}).location || 0, docLength));
            const ranges = lineRanges(text);
            const currentIndex = Math.max(0, ranges.findIndex((range) => cursor >= range.start && cursor <= range.end));
            const isBlank = (range) => text.slice(range.start, range.contentEnd).trim().length === 0;
            if (isBlank(ranges[currentIndex])) {
              return { from: ranges[currentIndex].start, to: ranges[currentIndex].end };
            }

            let firstIndex = currentIndex;
            let lastIndex = currentIndex;
            while (firstIndex > 0 && !isBlank(ranges[firstIndex - 1])) firstIndex -= 1;
            while (lastIndex + 1 < ranges.length && !isBlank(ranges[lastIndex + 1])) lastIndex += 1;
            return { from: ranges[firstIndex].start, to: ranges[lastIndex].end };
          }

          function focusModeExtension(hostState) {
            if (!hostState.focusModeEnabled) return [];
            const text = hostState.text || "";
            const docLength = text.length;
            if (docLength <= 0) return [];
            const focus = focusedBlockBounds(hostState);
            const ranges = [];
            if (focus.from > 0) {
              ranges.push(Decoration.mark({ class: "sl-focus-dimmed" }).range(0, focus.from));
            }
            if (focus.to < docLength) {
              ranges.push(Decoration.mark({ class: "sl-focus-dimmed" }).range(focus.to, docLength));
            }
            return EditorView.decorations.of(Decoration.set(ranges, true));
          }

          function normalizedFoldedRanges(hostState, doc) {
            const rawRanges = Array.isArray(hostState.foldedRanges) ? hostState.foldedRanges : [];
            const ranges = rawRanges
              .map((range) => ({
                startLine: Math.max(1, Number(range.startLine || 0)),
                endLine: Math.max(1, Number(range.endLine || 0)),
                title: range.title || ""
              }))
              .filter((range) => range.endLine > range.startLine && range.endLine <= doc.lines)
              .sort((first, second) => {
                if (first.startLine === second.startLine) return second.endLine - first.endLine;
                return first.startLine - second.startLine;
              });
            const normalized = [];
            for (const range of ranges) {
              const previous = normalized[normalized.length - 1];
              if (previous && previous.endLine >= range.startLine) continue;
              normalized.push(range);
            }
            return normalized;
          }

          function foldedRangeExtension(hostState, doc) {
            const ranges = [];
            for (const range of normalizedFoldedRanges(hostState, doc)) {
              const firstLine = doc.line(range.startLine);
              const lastLine = doc.line(range.endLine);
              ranges.push(
                Decoration.replace({
                  widget: new FoldedBlockWidget(firstLine.text, range.endLine - range.startLine)
                }).range(firstLine.from, lastLine.to)
              );
            }
            return ranges.length ? EditorView.decorations.of(Decoration.set(ranges, true)) : [];
          }

          window.simplelimeCreateState = function(hostState) {
            const languageExtension = hostState.syntaxHighlightingEnabled
              ? extensionForLanguage(hostState.language, modules)
              : [];
            const doc = EditorState.create({ doc: hostState.text || "" }).doc;
            const foldedRanges = normalizedFoldedRanges(hostState, doc);
            const isEditable = !!hostState.editable && foldedRanges.length === 0;
            return EditorState.create({
              doc: hostState.text || "",
              selection: hostSelection(hostState),
              extensions: [
                EditorState.allowMultipleSelections.of(true),
                lineNumbers(),
                highlightActiveLineGutter(),
                history(),
                drawSelection(),
                highlightActiveLine(),
                highlightSelectionMatches(),
                syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
                EditorState.readOnly.of(!isEditable),
                EditorView.editable.of(isEditable),
                hostState.wrapsLines ? EditorView.lineWrapping : [],
                EditorView.theme({
                  ".cm-content": {
                    fontSize: `${hostState.fontSize || 14}px`
                  }
                }),
                columnGuideExtension(hostState),
                typewriterModeExtension(hostState),
                foldedRangeExtension(hostState, doc),
                focusModeExtension(hostState),
                decorationExtension(hostState),
                EditorView.domEventHandlers({
                  keydown: handleShortcut,
                  scroll: reportVisibleRange
                }),
                EditorView.updateListener.of((update) => {
                  if (update.docChanged) reportText(update.state.doc.toString());
                  if (update.selectionSet || update.docChanged) {
                    reportSelectionRanges(update.state.selection);
                  }
                  if (update.viewportChanged || update.docChanged) reportVisibleRange();
                }),
                keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap]),
                languageExtension
              ]
            });
          };

          editorView = new EditorView({
            state: window.simplelimeCreateState(currentState),
            parent: document.getElementById("editor")
          });
          scrollPrimarySelectionIntoView = () => {
            if (!editorView) return;
            const mainSelection = editorView.state.selection.main;
            editorView.dispatch({
              effects: EditorView.scrollIntoView(mainSelection.head, {
                y: currentState.typewriterModeEnabled ? "center" : "nearest"
              })
            });
          };

          function normalizedSelectionRanges(ranges) {
            const sortedRanges = ranges
              .filter((range) => range)
              .sort((first, second) => {
                if (first.from === second.from) return first.to - second.to;
                return first.from - second.from;
              });
            const normalized = [];
            for (const range of sortedRanges) {
              const previous = normalized[normalized.length - 1];
              if (previous && range.from <= previous.to) {
                normalized[normalized.length - 1] = EditorSelection.range(
                  previous.from,
                  Math.max(previous.to, range.to)
                );
              } else {
                normalized.push(range);
              }
            }
            return normalized;
          }

          function contentRange(from, to) {
            return from === to ? EditorSelection.cursor(from) : EditorSelection.range(from, to);
          }

          function expandSelectionToLine(view) {
            const doc = view.state.doc;
            const ranges = view.state.selection.ranges.map((range) => {
              const fromLine = doc.lineAt(Math.min(range.from, range.to));
              const toLine = doc.lineAt(Math.max(range.from, range.to));
              return contentRange(fromLine.from, toLine.to);
            });
            const normalizedRanges = normalizedSelectionRanges(ranges);
            view.dispatch({
              selection: EditorSelection.create(
                normalizedRanges.length ? normalizedRanges : [EditorSelection.cursor(0)],
                Math.max(0, normalizedRanges.length - 1)
              )
            });
            return true;
          }

          function splitSelectionIntoLines(view) {
            const doc = view.state.doc;
            const selectedRanges = view.state.selection.ranges.filter((range) => range.from !== range.to);
            if (selectedRanges.length === 0) return expandSelectionToLine(view);
            const splitRanges = [];
            for (const range of selectedRanges) {
              const from = Math.min(range.from, range.to);
              const to = Math.max(range.from, range.to);
              const fromLine = doc.lineAt(from);
              const toLine = doc.lineAt(Math.max(from, to - 1));
              for (let lineNumber = fromLine.number; lineNumber <= toLine.number; lineNumber += 1) {
                const line = doc.line(lineNumber);
                const lineFrom = Math.max(line.from, from);
                const lineTo = Math.min(line.to, to);
                if (lineTo > lineFrom) splitRanges.push(EditorSelection.range(lineFrom, lineTo));
              }
            }
            const normalizedRanges = normalizedSelectionRanges(splitRanges);
            if (normalizedRanges.length === 0) return false;
            view.dispatch({
              selection: EditorSelection.create(normalizedRanges, normalizedRanges.length - 1)
            });
            return true;
          }

          function lineRangeEnd(doc, line) {
            if (line.number >= doc.lines) return line.to;
            return doc.line(line.number + 1).from;
          }

          function selectedLineBlock(view) {
            const doc = view.state.doc;
            if (doc.length <= 0) return null;
            const selectedRanges = view.state.selection.ranges.filter((range) => range.from !== range.to);
            const ranges = selectedRanges.length > 0 ? selectedRanges : [view.state.selection.main];
            let blockFrom = Number.POSITIVE_INFINITY;
            let blockTo = 0;
            for (const range of ranges) {
              const from = Math.max(0, Math.min(range.from, range.to, doc.length));
              const to = Math.max(0, Math.min(Math.max(range.from, range.to), doc.length));
              const endPosition = to > from ? Math.max(from, to - 1) : from;
              const fromLine = doc.lineAt(from);
              const toLine = doc.lineAt(Math.min(endPosition, doc.length));
              blockFrom = Math.min(blockFrom, fromLine.from);
              blockTo = Math.max(blockTo, lineRangeEnd(doc, toLine));
            }
            if (!Number.isFinite(blockFrom)) return null;
            return { from: blockFrom, to: blockTo };
          }

          function moveSelectedLines(view, direction) {
            const doc = view.state.doc;
            const block = selectedLineBlock(view);
            if (!block || block.to <= block.from) return false;
            const targetText = doc.sliceString(block.from, block.to);
            if (direction < 0) {
              if (block.from <= 0) return false;
              const previousLine = doc.lineAt(block.from - 1);
              const previousFrom = previousLine.from;
              const previousTo = lineRangeEnd(doc, previousLine);
              const previousText = doc.sliceString(previousFrom, previousTo);
              view.dispatch({
                changes: { from: previousFrom, to: block.to, insert: targetText + previousText },
                selection: EditorSelection.create([EditorSelection.range(previousFrom, previousFrom + targetText.length)])
              });
              return true;
            }
            if (block.to >= doc.length) return false;
            const nextLine = doc.lineAt(block.to);
            const nextFrom = nextLine.from;
            const nextTo = lineRangeEnd(doc, nextLine);
            const nextText = doc.sliceString(nextFrom, nextTo);
            view.dispatch({
              changes: { from: block.from, to: nextTo, insert: nextText + targetText },
              selection: EditorSelection.create([
                EditorSelection.range(block.from + nextText.length, block.from + nextText.length + targetText.length)
              ])
            });
            return true;
          }

          function lineCommentPrefixForLanguage(language) {
            switch (language) {
              case "swift":
              case "javascript":
              case "typescript":
              case "go":
              case "rust":
                return "//";
              case "python":
              case "ruby":
              case "shell":
              case "yaml":
                return "#";
              default:
                return null;
            }
          }

          function selectedLineRanges(view) {
            const doc = view.state.doc;
            if (doc.length <= 0) return [];
            const selectedRanges = view.state.selection.ranges.filter((range) => range.from !== range.to);
            const ranges = selectedRanges.length > 0 ? selectedRanges : [view.state.selection.main];
            const lineRanges = [];
            for (const range of ranges) {
              const from = Math.max(0, Math.min(range.from, range.to, doc.length));
              const to = Math.max(0, Math.min(Math.max(range.from, range.to), doc.length));
              const endPosition = to > from ? Math.max(from, to - 1) : from;
              const fromLine = doc.lineAt(from);
              const toLine = doc.lineAt(Math.min(endPosition, doc.length));
              lineRanges.push({ from: fromLine.from, to: lineRangeEnd(doc, toLine) });
            }
            return lineRanges
              .sort((first, second) => first.from - second.from)
              .reduce((merged, range) => {
                const previous = merged[merged.length - 1];
                if (previous && range.from <= previous.to) {
                  previous.to = Math.max(previous.to, range.to);
                } else {
                  merged.push({ from: range.from, to: range.to });
                }
                return merged;
              }, []);
          }

          function splitLineRecords(text) {
            if (text.length === 0) return [{ content: "", ending: "" }];
            const records = [];
            let start = 0;
            while (start < text.length) {
              const newline = text.indexOf("\\n", start);
              if (newline === -1) {
                records.push({ content: text.slice(start), ending: "" });
                break;
              }
              const endingStart = newline > start && text[newline - 1] === "\\r" ? newline - 1 : newline;
              records.push({
                content: text.slice(start, endingStart),
                ending: text.slice(endingStart, newline + 1)
              });
              start = newline + 1;
            }
            return records;
          }

          function toggleLineCommentsText(text, prefix) {
            const records = splitLineRecords(text);
            const meaningfulRecords = records.filter((record) => record.content.trim().length > 0);
            const shouldUncomment = meaningfulRecords.length > 0 && meaningfulRecords.every((record) => {
              const match = record.content.match(/^(\\s*)(.*)$/);
              const body = match ? match[2] : record.content;
              return body.startsWith(prefix);
            });

            return records.map((record) => {
              const match = record.content.match(/^(\\s*)(.*)$/);
              const indent = match ? match[1] : "";
              const body = match ? match[2] : record.content;
              if (body.trim().length === 0) return record.content + record.ending;
              if (shouldUncomment && body.startsWith(prefix)) {
                let uncommented = body.slice(prefix.length);
                if (uncommented.startsWith(" ")) uncommented = uncommented.slice(1);
                return indent + uncommented + record.ending;
              }
              return indent + prefix + " " + body + record.ending;
            }).join("");
          }

          function toggleLineComments(view) {
            const prefix = lineCommentPrefixForLanguage(currentState.language);
            if (!prefix) return false;
            const doc = view.state.doc;
            const ranges = selectedLineRanges(view);
            if (ranges.length === 0) return false;
            const changes = [];
            const selections = [];
            let delta = 0;
            for (const range of ranges) {
              const original = doc.sliceString(range.from, range.to);
              const replacement = toggleLineCommentsText(original, prefix);
              changes.push({ from: range.from, to: range.to, insert: replacement });
              const selectionFrom = range.from + delta;
              selections.push(EditorSelection.range(selectionFrom, selectionFrom + replacement.length));
              delta += replacement.length - (range.to - range.from);
            }
            view.dispatch({
              changes,
              selection: EditorSelection.create(selections, Math.max(0, selections.length - 1))
            });
            return true;
          }

          function mergeDocumentRanges(ranges) {
            return ranges
              .sort((first, second) => first.from - second.from)
              .reduce((merged, range) => {
                const previous = merged[merged.length - 1];
                if (previous && range.from <= previous.to) {
                  previous.to = Math.max(previous.to, range.to);
                } else {
                  merged.push({ from: range.from, to: range.to });
                }
                return merged;
              }, []);
          }

          function selectedTextRanges(view) {
            const doc = view.state.doc;
            const ranges = view.state.selection.ranges
              .filter((range) => range.from !== range.to)
              .map((range) => ({
                from: Math.max(0, Math.min(range.from, range.to, doc.length)),
                to: Math.max(0, Math.min(Math.max(range.from, range.to), doc.length))
              }));
            return ranges.length > 0 ? mergeDocumentRanges(ranges) : [{ from: 0, to: doc.length }];
          }

          function selectedOrAllLineRanges(view) {
            const doc = view.state.doc;
            const selectedRanges = view.state.selection.ranges.filter((range) => range.from !== range.to);
            if (selectedRanges.length === 0) return [{ from: 0, to: doc.length }];
            return selectedLineRanges(view);
          }

          function replaceDocumentRanges(view, ranges, replacements) {
            if (ranges.length !== replacements.length) return false;
            const changes = [];
            const selections = [];
            let delta = 0;
            for (let index = 0; index < ranges.length; index += 1) {
              const range = ranges[index];
              const replacement = replacements[index];
              changes.push({ from: range.from, to: range.to, insert: replacement });
              const selectionFrom = range.from + delta;
              selections.push(EditorSelection.range(selectionFrom, selectionFrom + replacement.length));
              delta += replacement.length - (range.to - range.from);
            }
            view.dispatch({
              changes,
              selection: EditorSelection.create(selections, Math.max(0, selections.length - 1))
            });
            return true;
          }

          function swapCaseText(text) {
            return Array.from(text).map((character) => {
              const lower = character.toLocaleLowerCase();
              const upper = character.toLocaleUpperCase();
              if (character === lower && character !== upper) return upper;
              if (character === upper && character !== lower) return lower;
              return character;
            }).join("");
          }

          function titlecaseText(text) {
            return text.replace(/\\S+/g, (word) => {
              const characters = Array.from(word);
              if (characters.length === 0) return word;
              return characters[0].toLocaleUpperCase() + characters.slice(1).join("").toLocaleLowerCase();
            });
          }

          function splitNormalizedLines(text) {
            const hasTrailingNewline = text.endsWith("\\n") || text.endsWith("\\r");
            const normalized = text.replace(/\\r\\n/g, "\\n").replace(/\\r/g, "\\n");
            const lines = normalized.split("\\n");
            if (hasTrailingNewline && lines[lines.length - 1] === "") lines.pop();
            return { lines, hasTrailingNewline };
          }

          function joinNormalizedLines(lines, hasTrailingNewline) {
            const output = lines.join("\\n");
            return hasTrailingNewline ? `${output}\\n` : output;
          }

          function transformLineText(text, transform) {
            if (transform === "trimTrailingWhitespace") {
              return text.replace(/[ \\t]+(?=\\r?\\n|\\r|$)/g, "");
            }

            if (transform === "joinLines") {
              return text
                .replace(/\\r\\n/g, "\\n")
                .replace(/\\r/g, "\\n")
                .split("\\n")
                .map((line) => line.trim())
                .filter((line) => line.length > 0)
                .join(" ");
            }

            const { lines, hasTrailingNewline } = splitNormalizedLines(text);
            if (transform === "sortLines") {
              return joinNormalizedLines(
                lines.slice().sort((left, right) => left.localeCompare(right, undefined, { sensitivity: "base" })),
                hasTrailingNewline
              );
            }

            if (transform === "uniqueLines") {
              const seen = new Set();
              return joinNormalizedLines(
                lines.filter((line) => {
                  if (seen.has(line)) return false;
                  seen.add(line);
                  return true;
                }),
                hasTrailingNewline
              );
            }

            return null;
          }

          function duplicateSelectionOrCurrentLine(view) {
            const doc = view.state.doc;
            const selectedRanges = view.state.selection.ranges
              .filter((range) => range.from !== range.to)
              .map((range) => ({
                from: Math.max(0, Math.min(range.from, range.to, doc.length)),
                to: Math.max(0, Math.min(Math.max(range.from, range.to), doc.length))
              }));
            if (selectedRanges.length > 0) {
              const ranges = mergeDocumentRanges(selectedRanges);
              return replaceDocumentRanges(
                view,
                ranges,
                ranges.map((range) => {
                  const text = doc.sliceString(range.from, range.to);
                  return text + text;
                })
              );
            }

            const cursor = Math.max(0, Math.min(view.state.selection.main.head, doc.length));
            const line = doc.lineAt(cursor);
            const to = lineRangeEnd(doc, line);
            const text = doc.sliceString(line.from, to);
            const insertion = text.endsWith("\\n") ? text : `\\n${text}`;
            view.dispatch({
              changes: { from: to, to: to, insert: insertion },
              selection: EditorSelection.create([EditorSelection.range(to, to + insertion.length)])
            });
            return true;
          }

          function performTextTransform(view, transform) {
            const doc = view.state.doc;
            if (transform === "duplicateLine") return duplicateSelectionOrCurrentLine(view);

            if (["sortLines", "uniqueLines", "trimTrailingWhitespace", "joinLines"].includes(transform)) {
              const ranges = selectedOrAllLineRanges(view);
              const replacements = ranges.map((range) => transformLineText(doc.sliceString(range.from, range.to), transform));
              if (replacements.some((replacement) => replacement === null)) return false;
              return replaceDocumentRanges(view, ranges, replacements);
            }

            const textTransformers = {
              uppercase: (text) => text.toLocaleUpperCase(),
              lowercase: (text) => text.toLocaleLowerCase(),
              titlecase: titlecaseText,
              swapCase: swapCaseText,
              reverseSelection: (text) => Array.from(text).reverse().join("")
            };
            const transformer = textTransformers[transform];
            if (!transformer) return false;
            const ranges = selectedTextRanges(view);
            return replaceDocumentRanges(
              view,
              ranges,
              ranges.map((range) => transformer(doc.sliceString(range.from, range.to)))
            );
          }

          function wrapMarkdownSelections(view, left, right) {
            const doc = view.state.doc;
            const ranges = view.state.selection.ranges.map((range) => ({
              from: Math.max(0, Math.min(range.from, range.to, doc.length)),
              to: Math.max(0, Math.min(Math.max(range.from, range.to), doc.length))
            }));
            if (ranges.length === 0) return false;
            const changes = [];
            const selections = [];
            let delta = 0;
            for (const range of ranges) {
              const selectedText = doc.sliceString(range.from, range.to);
              const replacement = `${left}${selectedText}${right}`;
              changes.push({ from: range.from, to: range.to, insert: replacement });
              const selectionFrom = range.from + delta + left.length;
              selections.push(EditorSelection.range(selectionFrom, selectionFrom + (range.to - range.from)));
              delta += replacement.length - (range.to - range.from);
            }
            view.dispatch({
              changes,
              selection: EditorSelection.create(selections, Math.max(0, selections.length - 1))
            });
            return true;
          }

          function splitIndentLine(line) {
            const match = line.match(/^(\\s*)(.*)$/);
            return { indent: match ? match[1] : "", body: match ? match[2] : line };
          }

          function removeMarkdownPrefix(body, pattern) {
            return body.replace(pattern, "");
          }

          function applyMarkdownHeading(level, line) {
            const { indent, body } = splitIndentLine(line);
            if (body.trim().length === 0) return line;
            return `${indent}${"#".repeat(level)} ${removeMarkdownPrefix(body, /^#{1,6}\\s+/)}`;
          }

          function toggleMarkdownLinePrefix(prefix, line, pattern) {
            const { indent, body } = splitIndentLine(line);
            if (body.trim().length === 0) return line;
            const cleaned = removeMarkdownPrefix(body, pattern);
            return cleaned !== body ? `${indent}${cleaned}` : `${indent}${prefix}${body}`;
          }

          function transformMarkdownLines(view, transform) {
            const doc = view.state.doc;
            const ranges = selectedLineRanges(view);
            if (ranges.length === 0) return false;
            return replaceDocumentRanges(
              view,
              ranges,
              ranges.map((range) => {
                const { lines, hasTrailingNewline } = splitNormalizedLines(doc.sliceString(range.from, range.to));
                return joinNormalizedLines(transform(lines), hasTrailingNewline);
              })
            );
          }

          function needsLeadingBlankLine(location, doc) {
            if (location <= 0) return false;
            return !doc.sliceString(0, Math.min(location, doc.length)).endsWith("\\n\\n");
          }

          function needsTrailingBlankLine(location, doc) {
            if (location >= doc.length) return false;
            return !doc.sliceString(Math.max(0, location), doc.length).startsWith("\\n\\n");
          }

          function insertMarkdownSnippet(view, snippet, selectOffset, selectLength) {
            const doc = view.state.doc;
            const range = view.state.selection.main;
            const from = Math.max(0, Math.min(range.from, range.to, doc.length));
            const to = Math.max(0, Math.min(Math.max(range.from, range.to), doc.length));
            const prefix = needsLeadingBlankLine(from, doc) ? "\\n\\n" : "";
            const suffix = needsTrailingBlankLine(to, doc) ? "\\n\\n" : "";
            const insertion = `${prefix}${snippet}${suffix}`;
            view.dispatch({
              changes: { from, to, insert: insertion },
              selection: EditorSelection.create([
                EditorSelection.range(
                  from + prefix.length + selectOffset,
                  from + prefix.length + selectOffset + selectLength
                )
              ])
            });
            return true;
          }

          function insertMarkdownLink(view) {
            const doc = view.state.doc;
            const ranges = view.state.selection.ranges.map((range) => ({
              from: Math.max(0, Math.min(range.from, range.to, doc.length)),
              to: Math.max(0, Math.min(Math.max(range.from, range.to), doc.length))
            }));
            if (ranges.length === 0) return false;
            const changes = [];
            const selections = [];
            let delta = 0;
            for (const range of ranges) {
              const selectedText = doc.sliceString(range.from, range.to);
              const text = selectedText.length > 0 ? selectedText : "link";
              const replacement = `[${text}](https://example.com)`;
              changes.push({ from: range.from, to: range.to, insert: replacement });
              const selectionFrom = range.from + delta + 1;
              selections.push(EditorSelection.range(selectionFrom, selectionFrom + text.length));
              delta += replacement.length - (range.to - range.from);
            }
            view.dispatch({
              changes,
              selection: EditorSelection.create(selections, Math.max(0, selections.length - 1))
            });
            return true;
          }

          function insertMarkdownCodeFence(view) {
            const doc = view.state.doc;
            const selectedRanges = view.state.selection.ranges.filter((range) => range.from !== range.to);
            if (selectedRanges.length === 0) {
              const cursor = Math.max(0, Math.min(view.state.selection.main.head, doc.length));
              const insertion = "```\\n\\n```";
              view.dispatch({
                changes: { from: cursor, to: cursor, insert: insertion },
                selection: EditorSelection.create([EditorSelection.cursor(cursor + 4)])
              });
              return true;
            }

            const ranges = selectedLineRanges(view);
            const replacements = ranges.map((range) => {
              const text = doc.sliceString(range.from, range.to);
              return "```\\n" + (text.endsWith("\\n") ? text : text + "\\n") + "```";
            });
            const changes = [];
            const selections = [];
            let delta = 0;
            for (let index = 0; index < ranges.length; index += 1) {
              const range = ranges[index];
              const replacement = replacements[index];
              changes.push({ from: range.from, to: range.to, insert: replacement });
              const selectionFrom = range.from + delta + 4;
              selections.push(EditorSelection.range(selectionFrom, selectionFrom + (range.to - range.from)));
              delta += replacement.length - (range.to - range.from);
            }
            view.dispatch({
              changes,
              selection: EditorSelection.create(selections, Math.max(0, selections.length - 1))
            });
            return true;
          }

          function performMarkdownCommand(view, command) {
            switch (command) {
              case "bold":
                return wrapMarkdownSelections(view, "**", "**");
              case "italic":
                return wrapMarkdownSelections(view, "*", "*");
              case "inlineCode":
                return wrapMarkdownSelections(view, "`", "`");
              case "strikethrough":
                return wrapMarkdownSelections(view, "~~", "~~");
              case "highlight":
                return wrapMarkdownSelections(view, "==", "==");
              case "subscript":
                return wrapMarkdownSelections(view, "~", "~");
              case "superscript":
                return wrapMarkdownSelections(view, "^", "^");
              case "heading1":
                return transformMarkdownLines(view, (lines) => lines.map((line) => applyMarkdownHeading(1, line)));
              case "heading2":
                return transformMarkdownLines(view, (lines) => lines.map((line) => applyMarkdownHeading(2, line)));
              case "heading3":
                return transformMarkdownLines(view, (lines) => lines.map((line) => applyMarkdownHeading(3, line)));
              case "unorderedList":
                return transformMarkdownLines(view, (lines) => lines.map((line) => toggleMarkdownLinePrefix("- ", line, /^[-*+]\\s+/)));
              case "orderedList":
                return transformMarkdownLines(view, (lines) => lines.map((line, index) => toggleMarkdownLinePrefix(`${index + 1}. `, line, /^\\d+[.)]\\s+/)));
              case "taskList":
                return transformMarkdownLines(view, (lines) => lines.map((line) => toggleMarkdownLinePrefix("- [ ] ", line, /^[-*+]\\s+\\[[ xX]\\]\\s+/)));
              case "quote":
                return transformMarkdownLines(view, (lines) => lines.map((line) => toggleMarkdownLinePrefix("> ", line, /^>\\s?/)));
              case "link":
                return insertMarkdownLink(view);
              case "image":
                return insertMarkdownSnippet(view, "![image](image.png)", 9, 9);
              case "table":
                return insertMarkdownSnippet(view, "| Column 1 | Column 2 |\\n| --- | --- |\\n|  |  |", 2, 8);
              case "codeFence":
                return insertMarkdownCodeFence(view);
              case "mathBlock":
                return insertMarkdownSnippet(view, "$$\\nx = y\\n$$", 3, 5);
              case "mermaidDiagram":
                return insertMarkdownSnippet(view, "```mermaid\\ngraph TD\\n  A-->B\\n```", 11, 16);
              default:
                return false;
            }
          }

          window.simplelimeCommand = function(command) {
            if (!editorView) return false;
            const canMutate = hostStateIsEditable(currentState);
            if (command === "expandSelectionToLine") return expandSelectionToLine(editorView);
            if (command === "splitSelectionIntoLines") return splitSelectionIntoLines(editorView);
            if (!canMutate) return false;
            if (command === "indent") return indentMore(editorView);
            if (command === "outdent") return indentLess(editorView);
            if (command.startsWith("transform:")) return performTextTransform(editorView, command.slice("transform:".length));
            if (command.startsWith("markdown:")) return performMarkdownCommand(editorView, command.slice("markdown:".length));
            if (command === "toggleComment") return toggleLineComments(editorView);
            if (command === "moveLineUp") return moveSelectedLines(editorView, -1);
            if (command === "moveLineDown") return moveSelectedLines(editorView, 1);
            if (command === "deleteLine") {
              const selection = editorView.state.selection.main;
              const fromLine = editorView.state.doc.lineAt(selection.from);
              const toLine = editorView.state.doc.lineAt(selection.to);
              editorView.dispatch({
                changes: { from: fromLine.from, to: Math.min(editorView.state.doc.length, toLine.to + 1), insert: "" }
              });
              return true;
            }
            return false;
          };

          reportVisibleRange();
          post("ready", true);
        }

        function applyTextareaColumnGuide(element, rawColumnGuide) {
          const columnGuide = Math.max(0, Math.min(200, Number(rawColumnGuide || 0)));
          if (columnGuide > 0) {
            element.classList.add("sl-has-column-guide");
            element.style.setProperty("--sl-column-guide", `${columnGuide}ch`);
          } else {
            element.classList.remove("sl-has-column-guide");
            element.style.removeProperty("--sl-column-guide");
          }
        }

        function applyTextareaEditorModes(element, hostState) {
          element.classList.toggle("sl-typewriter-mode", !!hostState.typewriterModeEnabled);
          element.classList.toggle("sl-focus-mode", !!hostState.focusModeEnabled);
        }

        function foldedTextForTextarea(hostState) {
          const text = hostState.text || "";
          const lines = text.split("\\n");
          const ranges = (Array.isArray(hostState.foldedRanges) ? hostState.foldedRanges : [])
            .map((range) => ({
              startLine: Math.max(1, Number(range.startLine || 0)),
              endLine: Math.max(1, Number(range.endLine || 0))
            }))
            .filter((range) => range.endLine > range.startLine && range.endLine <= lines.length)
            .sort((first, second) => {
              if (first.startLine === second.startLine) return second.endLine - first.endLine;
              return first.startLine - second.startLine;
            });
          const normalized = [];
          for (const range of ranges) {
            const previous = normalized[normalized.length - 1];
            if (previous && previous.endLine >= range.startLine) continue;
            normalized.push(range);
          }
          if (normalized.length === 0) return text;

          const output = [];
          let lineNumber = 1;
          for (const range of normalized) {
            while (lineNumber < range.startLine) {
              output.push(lines[lineNumber - 1] || "");
              lineNumber += 1;
            }
            const foldedLineCount = range.endLine - range.startLine;
            const suffix = foldedLineCount === 1 ? "line" : "lines";
            output.push(`${lines[range.startLine - 1] || ""}  ... ${foldedLineCount} ${suffix} folded`);
            lineNumber = range.endLine + 1;
          }
          while (lineNumber <= lines.length) {
            output.push(lines[lineNumber - 1] || "");
            lineNumber += 1;
          }
          return output.join("\\n");
        }

        function hostStateIsEditable(hostState) {
          return !!hostState.editable && !(Array.isArray(hostState.foldedRanges) && hostState.foldedRanges.length > 0);
        }

        function startTextareaFallback() {
          textarea = document.createElement("textarea");
          textarea.spellcheck = false;
          textarea.value = foldedTextForTextarea(currentState);
          textarea.style.fontSize = `${currentState.fontSize || 14}px`;
          applyTextareaColumnGuide(textarea, currentState.columnGuide);
          applyTextareaEditorModes(textarea, currentState);
          textarea.readOnly = !hostStateIsEditable(currentState);
          textarea.addEventListener("input", () => reportText(textarea.value));
          textarea.addEventListener("select", () => {
            reportSelection(textarea.selectionStart || 0, Math.max(0, (textarea.selectionEnd || 0) - (textarea.selectionStart || 0)));
          });
          textarea.addEventListener("keydown", handleShortcut);
          textarea.addEventListener("scroll", reportVisibleRange);
          document.getElementById("editor").replaceChildren(textarea);
          post("ready", true);
        }

        window.simplelimeSetState = function(hostState) {
          const previousSelectionSignature = selectionSignature(currentState);
          const previousText = currentState.text || "";
          currentState = Object.assign({}, currentState, hostState || {});
          const shouldScrollSelection =
            previousText !== (currentState.text || "") ||
            previousSelectionSignature !== selectionSignature(currentState);
          applyingHostState = true;
          try {
            if (editorView && window.simplelimeCreateState) {
              editorView.setState(window.simplelimeCreateState(currentState));
              if (shouldScrollSelection) scrollPrimarySelectionIntoView();
              reportVisibleRange();
            } else if (textarea) {
              textarea.value = foldedTextForTextarea(currentState);
              textarea.readOnly = !hostStateIsEditable(currentState);
              textarea.style.fontSize = `${currentState.fontSize || 14}px`;
              applyTextareaColumnGuide(textarea, currentState.columnGuide);
              applyTextareaEditorModes(textarea, currentState);
              const start = Math.min(currentState.selectionLocation || 0, textarea.value.length);
              const end = Math.min(start + (currentState.selectionLength || 0), textarea.value.length);
              textarea.setSelectionRange(start, end);
              if (shouldScrollSelection) scrollTextareaSelectionIntoView();
              reportVisibleRange();
            }
          } finally {
            applyingHostState = false;
          }
        };

        startCodeMirror().catch(() => startTextareaFallback());
      </script>
    </body>
    </html>
    """
}
