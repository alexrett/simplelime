import AppKit
import SwiftUI
import WebKit

struct MarkdownWYSIWYGEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectionRanges: [TextRange]

    var baseURL: URL?
    var fontSize: Double
    var typewriterModeEnabled: Bool
    var onShortcut: (EditorShortcut) -> Void
    var onRegisterEditorCommandHandler: (@escaping (EditorCommand) -> Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: LocalImageSchemeHandler.scheme)
        configuration.userContentController.add(context.coordinator, name: "simplelime")

        let webView = MarkdownWYSIWYGWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.shortcutHandler = { shortcut in
            context.coordinator.parent.onShortcut(shortcut)
            return true
        }
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.lastAppliedMarkdown = text

        webView.loadHTMLString(
            Self.html(
                markdown: text,
                fontSize: fontSize,
                typewriterModeEnabled: typewriterModeEnabled,
                baseURL: baseURL
            ),
            baseURL: baseURL ?? URL(fileURLWithPath: "/", isDirectory: true)
        )
        context.coordinator.applySelectionIfNeeded(selectionRanges, force: true)
        registerCommandHandler(context: context)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.webView = webView
        if let webView = webView as? MarkdownWYSIWYGWebView {
            webView.shortcutHandler = { shortcut in
                context.coordinator.parent.onShortcut(shortcut)
                return true
            }
        }
        registerCommandHandler(context: context)

        if context.coordinator.lastAppliedMarkdown != text {
            context.coordinator.applyExternalMarkdown(text)
        }

        context.coordinator.applyEditorOptions(fontSize: fontSize, typewriterModeEnabled: typewriterModeEnabled)
        context.coordinator.applySelectionIfNeeded(selectionRanges)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "simplelime")
    }

    private func registerCommandHandler(context: Context) {
        onRegisterEditorCommandHandler { [weak coordinator = context.coordinator] command in
            coordinator?.perform(command) ?? false
        }
    }

    static func html(markdown: String, fontSize: Double, typewriterModeEnabled: Bool, baseURL: URL? = nil) -> String {
        let initialMarkdown = javaScriptLiteral(markdown)
        let initialFontSize = max(10, min(32, fontSize))
        let initialTypewriter = typewriterModeEnabled ? "true" : "false"
        let documentBasePath = baseURL?.isFileURL == true ? javaScriptLiteral(baseURL?.path ?? "") : "\"\""

        return #"""
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.css">
          <style>
            :root {
              color-scheme: light dark;
              --editor-font-size: \#(initialFontSize)px;
              --editor-max-width: 860px;
              --accent: -apple-system-control-accent;
            }

            html, body {
              margin: 0;
              min-height: 100%;
              background: transparent;
              color: CanvasText;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }

            body {
              overflow: auto;
            }

            #editor {
              box-sizing: border-box;
              min-height: 100vh;
              max-width: var(--editor-max-width);
              margin: 0 auto;
              padding: 26px 34px 42px;
              font-size: var(--editor-font-size);
              line-height: 1.62;
              outline: none;
              word-break: break-word;
            }

            body.typewriter #editor {
              padding-top: max(160px, 45vh);
              padding-bottom: max(160px, 45vh);
            }

            #editor:empty::before {
              content: "Start writing...";
              color: color-mix(in srgb, CanvasText 34%, transparent);
            }

            h1, h2, h3, h4, h5, h6 {
              line-height: 1.2;
              margin: 1.15em 0 0.45em;
              font-weight: 700;
            }

            h1 { font-size: 2em; }
            h2 { font-size: 1.55em; }
            h3 { font-size: 1.28em; }
            h4, h5, h6 { font-size: 1.08em; }

            p {
              margin: 0.65em 0;
            }

            a {
              color: var(--accent);
            }

            code {
              font-family: "SF Mono", ui-monospace, Menlo, monospace;
              font-size: 0.92em;
              padding: 0.08em 0.32em;
              border-radius: 4px;
              background: color-mix(in srgb, CanvasText 11%, transparent);
            }

            kbd {
              font-family: "SF Mono", ui-monospace, Menlo, monospace;
              font-size: 0.84em;
              padding: 1px 5px;
              border-radius: 4px;
              border: 1px solid color-mix(in srgb, CanvasText 22%, transparent);
              background: color-mix(in srgb, CanvasText 9%, transparent);
              box-shadow: inset 0 -1px color-mix(in srgb, CanvasText 12%, transparent);
            }

            mark {
              background: color-mix(in srgb, yellow 34%, transparent);
              color: inherit;
              border-radius: 3px;
              padding: 0 2px;
            }

            .inline-math {
              font-family: KaTeX_Main, "Times New Roman", serif;
              background: color-mix(in srgb, CanvasText 7%, transparent);
              border-radius: 4px;
              padding: 1px 4px;
              white-space: nowrap;
            }

            .math-fallback {
              font-family: KaTeX_Main, "Times New Roman", Times, serif;
              letter-spacing: 0;
            }

            .math-fallback.display {
              display: block;
              text-align: center;
              font-size: 1.18em;
              line-height: 1.8;
            }

            .math-frac {
              display: inline-flex;
              flex-direction: column;
              align-items: center;
              vertical-align: middle;
              margin: 0 0.16em;
              line-height: 1.05;
            }

            .math-frac > span:first-child {
              border-bottom: 1px solid currentColor;
              padding: 0 0.18em 0.08em;
            }

            .math-frac > span:last-child {
              padding: 0.08em 0.18em 0;
            }

            .math-sqrt {
              display: inline-flex;
              align-items: flex-start;
              gap: 0.08em;
              vertical-align: middle;
            }

            .math-sqrt > span {
              border-top: 1px solid currentColor;
              padding: 0 0.12em;
            }

            pre {
              box-sizing: border-box;
              width: 100%;
              overflow: auto;
              margin: 0.9em 0;
              padding: 12px 14px;
              border-radius: 7px;
              background: color-mix(in srgb, CanvasText 10%, transparent);
              font-family: "SF Mono", ui-monospace, Menlo, monospace;
              font-size: 0.91em;
              line-height: 1.45;
              white-space: pre-wrap;
            }

            pre code {
              padding: 0;
              border-radius: 0;
              background: transparent;
              font-size: inherit;
            }

            blockquote {
              margin: 0.85em 0;
              padding: 0.1em 0 0.1em 1em;
              border-left: 3px solid color-mix(in srgb, CanvasText 24%, transparent);
              color: color-mix(in srgb, CanvasText 78%, transparent);
            }

            ul, ol {
              margin: 0.7em 0;
              padding-left: 1.55em;
            }

            li {
              margin: 0.25em 0;
            }

            li[data-task] {
              list-style: none;
              margin-left: -1.25em;
            }

            li[data-task] input {
              margin-right: 0.45em;
              vertical-align: middle;
            }

            hr {
              border: 0;
              border-top: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
              margin: 1.3em 0;
            }

            table {
              width: 100%;
              border-collapse: collapse;
              margin: 1em 0;
              font-size: 0.94em;
            }

            th, td {
              min-width: 90px;
              border: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
              padding: 7px 9px;
              vertical-align: top;
            }

            th {
              background: color-mix(in srgb, CanvasText 8%, transparent);
              font-weight: 650;
            }

            figure {
              margin: 1em 0;
            }

            figure[data-md-block="image"] img,
            figure[data-md-block="html-image"] img {
              display: block;
              max-width: 100%;
              height: auto;
              border-radius: 6px;
            }

            figure[data-md-block="html-media"] video,
            figure[data-md-block="html-media"] audio,
            figure[data-md-block="html-media"] iframe {
              display: block;
              max-width: 100%;
              border: 0;
              border-radius: 6px;
            }

            figure[data-md-block="html-media"] iframe {
              width: min(100%, 720px);
              min-height: 260px;
              background: color-mix(in srgb, CanvasText 8%, transparent);
            }

            figcaption {
              margin-top: 0.4em;
              color: color-mix(in srgb, CanvasText 56%, transparent);
              font-size: 0.88em;
            }

            figure[data-md-block="diagram"] > pre,
            figure[data-md-block="math"] > pre {
              display: none;
            }

            .callout {
              margin: 0.9em 0;
              padding: 11px 13px;
              border-radius: 7px;
              background: color-mix(in srgb, var(--accent) 16%, transparent);
              border: 1px solid color-mix(in srgb, var(--accent) 24%, transparent);
            }

            .callout-title {
              margin: 0 0 0.35em;
              font-weight: 700;
            }

            .toc {
              margin: 0.9em 0;
              padding: 10px 12px;
              border-radius: 7px;
              background: color-mix(in srgb, CanvasText 7%, transparent);
              color: color-mix(in srgb, CanvasText 70%, transparent);
            }

            .toc div {
              margin: 0.2em 0;
            }

            .diagram-render,
            .math-render {
              margin-top: 8px;
              padding: 12px;
              border-radius: 7px;
              background: color-mix(in srgb, CanvasText 6%, transparent);
              overflow: auto;
            }

            .diagram-render svg {
              max-width: 100%;
              height: auto;
            }

            .footnote-def {
              display: flex;
              align-items: first baseline;
              gap: 8px;
              color: color-mix(in srgb, CanvasText 70%, transparent);
              font-size: 0.9em;
            }

            .link-reference {
              margin: 0.45em 0;
              color: color-mix(in srgb, CanvasText 56%, transparent);
              font-size: 0.9em;
            }

            .table-toolbar {
              position: fixed;
              z-index: 20;
              display: none;
              gap: 3px;
              padding: 4px;
              border-radius: 7px;
              border: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
              background: color-mix(in srgb, Canvas 92%, CanvasText 8%);
              box-shadow: 0 6px 20px rgba(0, 0, 0, 0.22);
            }

            .table-toolbar.is-visible {
              display: flex;
            }

            .table-toolbar button {
              min-width: 26px;
              height: 24px;
              padding: 0 6px;
              border: 0;
              border-radius: 5px;
              background: transparent;
              color: CanvasText;
              font: 600 11px -apple-system, BlinkMacSystemFont, sans-serif;
            }

            .table-toolbar button:hover {
              background: color-mix(in srgb, var(--accent) 22%, transparent);
            }

            ::selection {
              background: color-mix(in srgb, var(--accent) 36%, transparent);
            }
          </style>
          <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.js"></script>
        </head>
        <body>
          <div id="table-toolbar" class="table-toolbar" contenteditable="false" aria-hidden="true">
            <button type="button" data-action="addRowAfter" title="Add row">+R</button>
            <button type="button" data-action="deleteRow" title="Delete row">-R</button>
            <button type="button" data-action="addColumnAfter" title="Add column">+C</button>
            <button type="button" data-action="deleteColumn" title="Delete column">-C</button>
            <button type="button" data-action="alignLeft" title="Align left">L</button>
            <button type="button" data-action="alignCenter" title="Align center">C</button>
            <button type="button" data-action="alignRight" title="Align right">R</button>
          </div>
          <main id="editor" contenteditable="true" spellcheck="true"></main>

          <script type="module">
            const initialMarkdown = \#(initialMarkdown);
            const initialTypewriter = \#(initialTypewriter);
            const documentBasePath = \#(documentBasePath);
            const editor = document.getElementById('editor');
            const tableToolbar = document.getElementById('table-toolbar');
            const CARET_TOKEN = String.fromCharCode(0xE000) + 'simplelime-caret' + String.fromCharCode(0xE000);
            let isSettingMarkdown = false;
            let lastPostedMarkdown = initialMarkdown;
            let lastRestoredCaretOffset = null;
            let emitTimer = null;
            let renderTimer = null;
            let normalizeTimer = null;
            let selectionTimer = null;
            let mermaidModulePromise = null;
            let activeTableCell = null;
            let lastPostedSelectionOffset = null;
            let activeReferences = new Map();
            const pendingPastedImages = new Map();
            let renderSerial = 0;

            document.body.classList.toggle('typewriter', initialTypewriter);

            function post(message) {
              window.webkit?.messageHandlers?.simplelime?.postMessage(message);
            }

            function escapeHtml(value) {
              return String(value)
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;');
            }

            function escapeAttr(value) {
              return escapeHtml(value).replace(/"/g, '&quot;');
            }

            function stripDiagramMarkup(value) {
              return String(value || '')
                .replace(/^[A-Za-z0-9_:-]+\s*/, '')
                .replace(/^[\[\(\{]/, '')
                .replace(/[\]\)\}]$/, '')
                .trim();
            }

            function diagramEndpoint(raw) {
              const value = String(raw || '').replace(/^\|[^|]*\|\s*/, '').trim();
              const match = value.match(/^([A-Za-z0-9_:-]+)\s*(?:\[(.*?)\]|\((.*?)\)|\{(.*?)\})?/);
              if (!match) return { id: value || 'node', label: stripDiagramMarkup(value) || value || 'node' };

              return {
                id: match[1],
                label: match[2] || match[3] || match[4] || match[1]
              };
            }

            function fallbackGraphSVG(source) {
              const lines = String(source || '').split('\n').map(line => line.replace(/%%.*$/, '').trim()).filter(Boolean);
              const direction = lines[0]?.match(/^(graph|flowchart)\s+(LR|RL|TD|TB|BT)/i)?.[2]?.toUpperCase() || 'TD';
              const horizontal = direction === 'LR' || direction === 'RL';
              const nodes = new Map();
              const edges = [];

              for (const line of lines) {
                if (/^(graph|flowchart)\s+/i.test(line) || /^subgraph\b/i.test(line) || /^end$/i.test(line)) continue;
                const match = line.match(/^(.+?)\s*(?:-->|---|==>|-.->|--.*?-->)\s*(.+)$/);
                if (!match) continue;

                const from = diagramEndpoint(match[1].replace(/\|.*\|$/, ''));
                const to = diagramEndpoint(match[2]);
                nodes.set(from.id, from.label);
                nodes.set(to.id, to.label);
                edges.push({ from: from.id, to: to.id });
              }

              if (!nodes.size) return null;

              const entries = Array.from(nodes.entries());
              const positions = new Map();
              entries.forEach(([id], index) => {
                positions.set(id, horizontal
                  ? { x: 70 + index * 180, y: 86 }
                  : { x: 160, y: 52 + index * 94 }
                );
              });

              const width = horizontal ? Math.max(320, entries.length * 180 + 40) : 360;
              const height = horizontal ? 190 : Math.max(190, entries.length * 94 + 40);
              const edgeMarkup = edges.map(edge => {
                const from = positions.get(edge.from);
                const to = positions.get(edge.to);
                if (!from || !to) return '';
                const startX = horizontal ? from.x + 58 : from.x;
                const startY = horizontal ? from.y : from.y + 26;
                const endX = horizontal ? to.x - 58 : to.x;
                const endY = horizontal ? to.y - 26 : to.y;
                return `<line x1="${startX}" y1="${startY}" x2="${endX}" y2="${endY}" stroke="currentColor" stroke-width="1.6" marker-end="url(#arrow)" opacity="0.72"/>`;
              }).join('');
              const nodeMarkup = entries.map(([id, label]) => {
                const point = positions.get(id);
                return `<g><rect x="${point.x - 58}" y="${point.y - 25}" width="116" height="50" rx="8" fill="rgba(255,255,255,0.08)" stroke="currentColor" opacity="0.9"/><text x="${point.x}" y="${point.y + 5}" text-anchor="middle" font-size="13" fill="currentColor">${escapeHtml(label)}</text></g>`;
              }).join('');

              return `<svg data-simplelime-diagram="graph" viewBox="0 0 ${width} ${height}" role="img" aria-label="Mermaid graph">${diagramDefs()}${edgeMarkup}${nodeMarkup}</svg>`;
            }

            function fallbackSequenceSVG(source) {
              const lines = String(source || '').split('\n').map(line => line.replace(/%%.*$/, '').trim()).filter(Boolean);
              const participants = [];
              const messages = [];

              function addParticipant(name) {
                if (name && !participants.includes(name)) participants.push(name);
              }

              for (const line of lines) {
                const participant = line.match(/^participant\s+([A-Za-z0-9_.:-]+)/i);
                if (participant) {
                  addParticipant(participant[1]);
                  continue;
                }

                const message = line.match(/^([A-Za-z0-9_.:-]+)\s*(?:-+>>?|=+>>?|-->>?)\s*([A-Za-z0-9_.:-]+)\s*:\s*(.+)$/);
                if (message) {
                  addParticipant(message[1]);
                  addParticipant(message[2]);
                  messages.push({ from: message[1], to: message[2], text: message[3] });
                }
              }

              if (!participants.length || !messages.length) return null;

              const gap = 170;
              const width = Math.max(320, participants.length * gap + 40);
              const height = Math.max(190, messages.length * 56 + 112);
              const positions = new Map(participants.map((name, index) => [name, 80 + index * gap]));
              const actors = participants.map(name => {
                const x = positions.get(name);
                return `<g><rect x="${x - 54}" y="20" width="108" height="34" rx="8" fill="rgba(255,255,255,0.08)" stroke="currentColor"/><text x="${x}" y="42" text-anchor="middle" font-size="13" fill="currentColor">${escapeHtml(name)}</text><line x1="${x}" y1="58" x2="${x}" y2="${height - 24}" stroke="currentColor" stroke-dasharray="4 5" opacity="0.45"/></g>`;
              }).join('');
              const messageMarkup = messages.map((message, index) => {
                const y = 88 + index * 56;
                const fromX = positions.get(message.from);
                const toX = positions.get(message.to);
                const textX = (fromX + toX) / 2;
                return `<g><line x1="${fromX}" y1="${y}" x2="${toX}" y2="${y}" stroke="currentColor" stroke-width="1.6" marker-end="url(#arrow)" opacity="0.78"/><text x="${textX}" y="${y - 8}" text-anchor="middle" font-size="12" fill="currentColor">${escapeHtml(message.text)}</text></g>`;
              }).join('');

              return `<svg data-simplelime-diagram="sequence" viewBox="0 0 ${width} ${height}" role="img" aria-label="Mermaid sequence diagram">${diagramDefs()}${actors}${messageMarkup}</svg>`;
            }

            function diagramDefs() {
              return '<defs><marker id="arrow" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="currentColor"/></marker></defs>';
            }

            function fallbackSourceSVG(source, language) {
              const lines = String(source || '').split('\n');
              const width = 520;
              const height = Math.max(120, lines.length * 20 + 58);
              const text = lines.map((line, index) => `<text x="18" y="${48 + index * 20}" font-size="13" fill="currentColor">${escapeHtml(line)}</text>`).join('');
              return `<svg data-simplelime-diagram="source" viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeAttr(language || 'diagram')} source"><rect x="1" y="1" width="${width - 2}" height="${height - 2}" rx="8" fill="rgba(255,255,255,0.06)" stroke="currentColor" opacity="0.75"/><text x="18" y="24" font-size="12" fill="currentColor" opacity="0.68">${escapeHtml(language || 'diagram')}</text>${text}</svg>`;
            }

            function fallbackDiagramSVG(source, language) {
              const text = String(source || '');
              const firstLine = text.trim().split('\n')[0] || '';
              if (/^(graph|flowchart)\s+/i.test(firstLine)) return fallbackGraphSVG(text) || fallbackSourceSVG(text, language);
              if (/^sequenceDiagram\b/i.test(firstLine) || String(language || '').toLowerCase() === 'sequence') {
                return fallbackSequenceSVG(text) || fallbackSourceSVG(text, language);
              }
              return fallbackSourceSVG(text, language);
            }

            function fallbackMathHTML(source, displayMode = false) {
              const greek = {
                alpha: 'α', beta: 'β', gamma: 'γ', delta: 'δ', epsilon: 'ε', zeta: 'ζ',
                eta: 'η', theta: 'θ', iota: 'ι', kappa: 'κ', lambda: 'λ', mu: 'μ',
                nu: 'ν', xi: 'ξ', pi: 'π', rho: 'ρ', sigma: 'σ', tau: 'τ',
                upsilon: 'υ', phi: 'φ', chi: 'χ', psi: 'ψ', omega: 'ω',
                Gamma: 'Γ', Delta: 'Δ', Theta: 'Θ', Lambda: 'Λ', Xi: 'Ξ',
                Pi: 'Π', Sigma: 'Σ', Phi: 'Φ', Psi: 'Ψ', Omega: 'Ω'
              };
              const operators = {
                times: '×', cdot: '·', pm: '±', mp: '∓', leq: '≤', geq: '≥',
                neq: '≠', approx: '≈', infty: '∞', partial: '∂', sum: '∑',
                prod: '∏', int: '∫',rightarrow: '→', leftarrow: '←', to: '→'
              };

              let html = escapeHtml(String(source || '').trim());
              html = html.replace(/\\frac\{([^{}]+)\}\{([^{}]+)\}/g, (_match, top, bottom) => {
                return `<span class="math-frac"><span>${fallbackMathInline(top)}</span><span>${fallbackMathInline(bottom)}</span></span>`;
              });
              html = html.replace(/\\sqrt\{([^{}]+)\}/g, (_match, value) => {
                return `<span class="math-sqrt">√<span>${fallbackMathInline(value)}</span></span>`;
              });
              html = fallbackMathInline(html);
              return `<span class="math-fallback${displayMode ? ' display' : ''}">${html}</span>`;

              function fallbackMathInline(value) {
                return String(value)
                  .replace(/\\([A-Za-z]+)/g, (_match, name) => greek[name] || operators[name] || name)
                  .replace(/([A-Za-z0-9)\]}]+)\^\{([^{}]+)\}/g, '$1<sup>$2</sup>')
                  .replace(/([A-Za-z0-9)\]}]+)_\{([^{}]+)\}/g, '$1<sub>$2</sub>')
                  .replace(/([A-Za-z0-9)\]}]+)\^([A-Za-z0-9+\-=]+)/g, '$1<sup>$2</sup>')
                  .replace(/([A-Za-z0-9)\]}]+)_([A-Za-z0-9+\-=]+)/g, '$1<sub>$2</sub>');
              }
            }

            function stripCaretToken(value) {
              return String(value).split(CARET_TOKEN).join('');
            }

            function parseRawHTMLImage(value) {
              const trimmed = stripCaretToken(String(value).trim());
              if (!/^<img\s+/i.test(trimmed) || !/\/?>$/i.test(trimmed)) return null;

              const document = new DOMParser().parseFromString(trimmed, 'text/html');
              const image = document.body.querySelector('img');
              if (!image) return null;

              return {
                source: image.getAttribute('src') || '',
                alt: image.getAttribute('alt') || '',
                title: image.getAttribute('title') || '',
                style: image.getAttribute('style') || '',
                rawHTML: trimmed
              };
            }

            function parseRawHTMLMedia(value) {
              const trimmed = stripCaretToken(String(value).trim());
              if (!/^<(video|audio|iframe)\s+/i.test(trimmed) || !/<\/(video|audio|iframe)>$/i.test(trimmed)) return null;

              const document = new DOMParser().parseFromString(trimmed, 'text/html');
              const media = document.body.firstElementChild;
              if (!media) return null;

              const tag = media.tagName.toLowerCase();
              if (!['audio', 'iframe', 'video'].includes(tag)) return null;

              return {
                tag,
                source: media.getAttribute('src') || '',
                title: media.getAttribute('title') || '',
                controls: media.hasAttribute('controls'),
                width: media.getAttribute('width') || '',
                height: media.getAttribute('height') || '',
                rawHTML: trimmed
              };
            }

            function parseMarkdownImageParts(alt, body) {
              let source = String(body || '').trim();
              let title = '';
              const titleMatch = source.match(/^(.*?)(?:\s+"([^"]*)")\s*$/);
              if (titleMatch) {
                source = titleMatch[1].trim();
                title = titleMatch[2] || '';
              }
              if (source.startsWith('<') && source.endsWith('>')) {
                source = source.slice(1, -1);
              }

              if (!source) return null;
              return { source, alt: alt || '', title, style: '' };
            }

            function normalizeReferenceLabel(value) {
              return stripCaretToken(String(value || '')).trim().replace(/\s+/g, ' ').toLowerCase();
            }

            function parseReferenceDefinition(value) {
              const trimmed = stripCaretToken(String(value || '').trim());
              const match = trimmed.match(/^\[([^\]]+)\]:\s+(.+)$/);
              if (!match) return null;
              if (match[1].startsWith('^')) return null;

              const image = parseMarkdownImageParts('', match[2]);
              if (!image || !image.source) return null;

              return {
                label: match[1],
                key: normalizeReferenceLabel(match[1]),
                source: image.source,
                title: image.title
              };
            }

            function parseMarkdownImageLine(value) {
              const trimmed = stripCaretToken(String(value).trim());
              const match = trimmed.match(/^!\[([^\]]*)\]\((.*)\)$/);
              return match ? parseMarkdownImageParts(match[1], match[2]) : null;
            }

            function localImageURL(path) {
              return 'simplelime-image://local?path=' + encodeURIComponent(path);
            }

            function localPathForSource(source) {
              if (!source) return null;

              if (/^file:/i.test(source)) {
                try {
                  return decodeURIComponent(new URL(source).pathname);
                } catch {
                  return null;
                }
              }

              if (source.startsWith('/')) {
                return source;
              }

              if (!/^[a-z][a-z0-9+.-]*:/i.test(source) && documentBasePath) {
                try {
                  const base = documentBasePath.endsWith('/') ? documentBasePath : documentBasePath + '/';
                  return decodeURIComponent(new URL(source, 'file://' + base).pathname);
                } catch {
                  return null;
                }
              }

              return null;
            }

            function sourceForHTML(source) {
              if (!source) return '';
              if (/^(https?:|data:|blob:|simplelime-image:)/i.test(source)) return source;

              const localPath = localPathForSource(source);
              if (localPath) {
                return localImageURL(localPath);
              }

              return source;
            }

            function imageFigureHTML(image, rawHTML = false) {
              const htmlSource = sourceForHTML(image.source);
              const titleAttr = image.title ? ` title="${escapeAttr(image.title)}"` : '';
              const styleAttr = image.style ? ` style="${escapeAttr(image.style)}"` : '';
              const rawAttr = rawHTML ? ` data-raw-html="${escapeAttr(image.rawHTML || '')}"` : '';
              const block = rawHTML ? 'html-image' : 'image';
              const caption = image.title ? `<figcaption>${escapeHtml(image.title)}</figcaption>` : '';

              return `<figure data-md-block="${block}" data-src="${escapeAttr(image.source)}" data-alt="${escapeAttr(image.alt)}" data-title="${escapeAttr(image.title || '')}" data-style="${escapeAttr(image.style || '')}"${rawAttr}><img src="${escapeAttr(htmlSource)}" alt="${escapeAttr(image.alt)}"${titleAttr}${styleAttr}>${caption}</figure>`;
            }

            function mediaFigureHTML(media) {
              const htmlSource = sourceForHTML(media.source);
              const rawAttr = ` data-raw-html="${escapeAttr(media.rawHTML || '')}"`;
              const titleAttr = media.title ? ` title="${escapeAttr(media.title)}"` : '';
              const widthAttr = media.width ? ` width="${escapeAttr(media.width)}"` : '';
              const heightAttr = media.height ? ` height="${escapeAttr(media.height)}"` : '';
              const controlsAttr = media.tag === 'iframe' ? '' : (media.controls ? ' controls' : ' controls');
              return `<figure data-md-block="html-media" data-tag="${escapeAttr(media.tag)}" data-src="${escapeAttr(media.source)}"${rawAttr}><${media.tag} src="${escapeAttr(htmlSource)}"${titleAttr}${widthAttr}${heightAttr}${controlsAttr} contenteditable="false"></${media.tag}></figure>`;
            }

            function imageMarkdown(source, alt = '') {
              return `![${String(alt || '').replace(/]/g, '\\]')}](${source})`;
            }

            function insertMarkdownAtSelection(markdown) {
              focusEditor();
              const payload = markdownWithCaretToken();
              const insertion = String(markdown || '');
              const nextMarkdown = payload.hasCaret
                ? payload.markdown.replace(CARET_TOKEN, () => insertion + CARET_TOKEN)
                : `${currentMarkdown()}\\n\\n${insertion}${CARET_TOKEN}`;
              const changed = stripCaretToken(nextMarkdown) !== lastPostedMarkdown;
              setMarkdown(nextMarkdown, { preserveCaretToken: true });
              if (changed) {
                post({ type: 'markdownChanged', markdown: stripCaretToken(nextMarkdown) });
              }
            }

            function insertLinkAtSelection() {
              focusEditor();
              const selection = window.getSelection();
              const range = selection?.rangeCount ? selection.getRangeAt(0) : null;
              const link = document.createElement('a');
              link.href = 'https://example.com';

              if (range && editor.contains(range.startContainer) && !range.collapsed) {
                link.appendChild(range.extractContents());
                range.insertNode(link);
              } else if (range && editor.contains(range.startContainer)) {
                link.textContent = 'link';
                range.insertNode(link);
              } else {
                link.textContent = 'link';
                editor.appendChild(link);
              }

              const nextRange = document.createRange();
              nextRange.selectNodeContents(link);
              selection.removeAllRanges();
              selection.addRange(nextRange);
              emitMarkdownChanged();
            }

            function insertImageMarkdown(source, alt = '') {
              insertMarkdownAtSelection(`\n\n${imageMarkdown(source, alt)}\n\n`);
            }

            function fileBaseName(name) {
              return String(name || 'image').replace(/\.[^.]+$/, '') || 'image';
            }

            function saveOrInsertImageFile(file) {
              if (!file || !file.type?.startsWith?.('image/')) return false;

              const reader = new FileReader();
              reader.onload = () => {
                const dataURL = String(reader.result || '');
                const alt = fileBaseName(file.name);
                const id = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
                pendingPastedImages.set(id, { dataURL, alt });

                if (documentBasePath && window.webkit?.messageHandlers?.simplelime) {
                  post({
                    type: 'savePastedImage',
                    id,
                    name: file.name || 'image',
                    mimeType: file.type || '',
                    dataURL
                  });
                } else {
                  pendingPastedImages.delete(id);
                  insertImageMarkdown(dataURL, alt);
                }
              };
              reader.readAsDataURL(file);
              return true;
            }

            function handleImageFileList(files) {
              let handled = false;
              for (const file of Array.from(files || [])) {
                handled = saveOrInsertImageFile(file) || handled;
              }
              return handled;
            }

            function receiveSavedImage(id, source, alt, error) {
              const pending = pendingPastedImages.get(id);
              pendingPastedImages.delete(id);
              if (!pending) return;

              if (source && !error) {
                insertImageMarkdown(source, alt || pending.alt);
              } else {
                insertImageMarkdown(pending.dataURL, pending.alt);
              }
            }

            function parseInline(value) {
              const tokenMark = String.fromCharCode(0xE001);
              const tokens = [];
              function stash(htmlValue) {
                const token = `${tokenMark}${tokens.length}${tokenMark}`;
                tokens.push(htmlValue);
                return token;
              }

              let html = String(value);
              html = html.replace(/<(u|kbd)\b[^>]*>([\s\S]*?)<\/\1>/gi, (_match, tag, body) => {
                return stash(`<${tag.toLowerCase()}>${escapeHtml(body)}</${tag.toLowerCase()}>`);
              });
              html = escapeHtml(html);
              html = html.replace(/\[\^([^\]]+)\]/g, (_match, label) => {
                return stash(`<sup data-md-footnote-ref="${escapeAttr(label)}">[${escapeHtml(label)}]</sup>`);
              });
              html = html.replace(/!\[([^\]]*)\]\[([^\]]*)\]/g, (_match, alt, label) => {
                const resolvedLabel = label || alt;
                const reference = activeReferences.get(normalizeReferenceLabel(resolvedLabel));
                if (!reference) return _match;
                const titleAttr = reference.title ? ` title="${escapeAttr(reference.title)}"` : '';
                return stash(`<img src="${escapeAttr(sourceForHTML(reference.source))}" data-md-src="${escapeAttr(reference.source)}" data-md-reference-label="${escapeAttr(resolvedLabel)}" alt="${escapeAttr(alt)}"${titleAttr}>`);
              });
              html = html.replace(/!\[([^\]]*)\]\(([^)]*)\)/g, (_match, alt, body) => {
                const image = parseMarkdownImageParts(alt, body);
                if (!image) return _match;
                const titleAttr = image.title ? ` title="${escapeAttr(image.title)}"` : '';
                return stash(`<img src="${escapeAttr(sourceForHTML(image.source))}" data-md-src="${escapeAttr(image.source)}" alt="${escapeAttr(image.alt)}"${titleAttr}>`);
              });
              html = html.replace(/\[([^\]]+)\]\[([^\]]*)\]/g, (_match, text, label) => {
                const resolvedLabel = label || text;
                const reference = activeReferences.get(normalizeReferenceLabel(resolvedLabel));
                if (!reference) return _match;
                const titleAttr = reference.title ? ` title="${escapeAttr(reference.title)}"` : '';
                return stash(`<a href="${escapeAttr(reference.source)}" data-md-reference-label="${escapeAttr(resolvedLabel)}"${titleAttr}>${text}</a>`);
              });
              html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_match, text, href) => stash(`<a href="${escapeAttr(href)}">${text}</a>`));
              html = html.replace(/&lt;(https?:\/\/[^&\s]+)&gt;/g, (_match, href) => stash(`<a href="${escapeAttr(href)}">${escapeHtml(href)}</a>`));
              html = html.replace(/\$([^$\n]+)\$/g, (_match, source) => {
                return stash(`<span class="inline-math" data-md-inline="math" data-source="${escapeAttr(source)}" contenteditable="false">${escapeHtml(source)}</span>`);
              });
              html = html.replace(/`([^`]+)`/g, (_match, code) => stash(`<code>${code}</code>`));
              html = html.replace(/~~([^~\n]+)~~/g, '<del>$1</del>');
              html = html.replace(/==([^=\n]+)==/g, '<mark>$1</mark>');
              html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
              html = html.replace(/__([^_]+)__/g, '<strong>$1</strong>');
              html = html.replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>');
              html = html.replace(/(^|[^_])_([^_\n]+)_/g, '$1<em>$2</em>');
              html = html.replace(/(^|[^~])~([^~\n]+)~/g, '$1<sub>$2</sub>');
              html = html.replace(/(^|[^^])\^([^^\n]+)\^/g, '$1<sup>$2</sup>');
              return html.replace(new RegExp(`${tokenMark}(\\d+)${tokenMark}`, 'g'), (_match, index) => tokens[Number(index)] || '');
            }

            function isFence(line) {
              return /^(```+|~~~+)/.test(line.trim());
            }

            function fenceInfo(line) {
              const trimmed = line.trim();
              const marker = trimmed.startsWith('~~~') ? '~~~' : '```';
              const language = trimmed.slice(marker.length).trim().split(/\s+/)[0] || '';
              return { marker, language };
            }

            function isTableDelimiter(line) {
              return /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(line);
            }

            function splitTableRow(line) {
              let value = line.trim();
              if (value.startsWith('|')) value = value.slice(1);
              if (value.endsWith('|')) value = value.slice(0, -1);
              return value.split('|').map(cell => cell.trim());
            }

            function tableAlignment(delimiter) {
              const trimmed = delimiter.trim();
              if (trimmed.startsWith(':') && trimmed.endsWith(':')) return 'center';
              if (trimmed.endsWith(':')) return 'right';
              return 'left';
            }

            function indentWidth(value) {
              return String(value || '').replace(/\t/g, '    ').length;
            }

            function listItemInfo(line) {
              const match = String(line || '').match(/^(\s*)([-*+]|\d+[.)])\s+([\s\S]*)$/);
              if (!match) return null;

              return {
                indent: indentWidth(match[1]),
                ordered: /^\d/.test(match[2]),
                body: match[3] || ''
              };
            }

            function nestedListHTML(lines, startIndex, baseIndent, ordered) {
              const tag = ordered ? 'ol' : 'ul';
              const items = [];
              let index = startIndex;

              while (index < lines.length) {
                const info = listItemInfo(lines[index]);
                if (!info || info.indent < baseIndent || info.ordered !== ordered) break;
                if (info.indent > baseIndent) break;

                let value = info.body;
                const task = value.match(/^\[([ xX])\]\s+(.*)$/);
                let itemAttrs = '';
                let checkbox = '';
                if (!ordered && task) {
                  const checked = task[1].toLowerCase() === 'x';
                  value = task[2];
                  itemAttrs = ` data-task="${checked ? 'checked' : 'unchecked'}"`;
                  checkbox = `<input type="checkbox" ${checked ? 'checked' : ''}>`;
                }

                index += 1;
                let children = '';
                while (index < lines.length) {
                  const child = listItemInfo(lines[index]);
                  if (!child || child.indent <= baseIndent) break;
                  const nested = nestedListHTML(lines, index, child.indent, child.ordered);
                  children += nested.html;
                  index = nested.nextIndex;
                }

                items.push(`<li${itemAttrs}>${checkbox}${parseInline(value)}${children}</li>`);
              }

              return { html: `<${tag}>${items.join('')}</${tag}>`, nextIndex: index };
            }

            function isBlockStart(lines, index) {
              const line = lines[index] ?? '';
              const trimmed = line.trim();
              if (!trimmed) return true;
              if (/^#{1,6}\s+/.test(trimmed)) return true;
              if (/^([-*_])\s*\1\s*\1\s*$/.test(trimmed)) return true;
              if (/^>\s?/.test(trimmed)) return true;
              if (listItemInfo(line)) return true;
              if (isFence(trimmed)) return true;
              if (parseMarkdownImageLine(trimmed)) return true;
              if (parseRawHTMLImage(trimmed)) return true;
              if (parseRawHTMLMedia(trimmed)) return true;
              if (parseReferenceDefinition(trimmed)) return true;
              if (/^\[\^([^\]]+)\]:\s*/.test(trimmed)) return true;
              if (trimmed === '$$') return true;
              if (trimmed.toLowerCase() === '[toc]') return true;
              if (index === 0 && trimmed === '---') return true;
              if (index + 1 < lines.length && isTableDelimiter(lines[index + 1]) && line.includes('|')) return true;
              return false;
            }

            function markdownToHtml(markdown) {
              const lines = String(markdown).replace(/\r\n/g, '\n').split('\n');
              const headings = [];
              const blocks = [];
              let i = 0;
              activeReferences = new Map();

              for (const line of lines) {
                const match = line.trim().match(/^(#{1,6})\s+(.+)$/);
                if (match) headings.push({ level: match[1].length, text: match[2] });
                const reference = parseReferenceDefinition(line);
                if (reference) activeReferences.set(reference.key, reference);
              }

              while (i < lines.length) {
                const line = lines[i] ?? '';
                const trimmed = line.trim();

                if (i === 0 && stripCaretToken(trimmed) === '---') {
                  const frontMatterStart = i;
                  const yamlLines = [];
                  let frontMatterHasCaret = trimmed.includes(CARET_TOKEN);
                  i += 1;
                  while (i < lines.length && !['---', '...'].includes(stripCaretToken(lines[i].trim()))) {
                    yamlLines.push(lines[i]);
                    i += 1;
                  }
                  if (i < lines.length) {
                    frontMatterHasCaret = frontMatterHasCaret || lines[i].includes(CARET_TOKEN);
                    i += 1;
                    blocks.push(`<pre data-md-block="front-matter" data-lang="yaml"><code>${escapeHtml(yamlLines.join('\n'))}</code></pre>${frontMatterHasCaret ? CARET_TOKEN : ''}`);
                    continue;
                  }

                  i = frontMatterStart + 1;
                  blocks.push('<hr>');
                  continue;
                }

                if (!trimmed) {
                  i += 1;
                  continue;
                }

                const heading = trimmed.match(/^(#{1,6})\s+(.+)$/);
                if (heading) {
                  const level = heading[1].length;
                  blocks.push(`<h${level}>${parseInline(heading[2])}</h${level}>`);
                  i += 1;
                  continue;
                }

                if (/^([-*_])\s*\1\s*\1\s*$/.test(trimmed)) {
                  blocks.push('<hr>');
                  i += 1;
                  continue;
                }

                if (trimmed.toLowerCase() === '[toc]') {
                  const items = headings.map(item => `<div style="padding-left:${(item.level - 1) * 14}px">${escapeHtml(item.text)}</div>`).join('');
                  blocks.push(`<div class="toc" data-md-block="toc">${items || 'Table of contents'}</div>`);
                  i += 1;
                  continue;
                }

                if (stripCaretToken(trimmed) === '$$') {
                  const mathLines = [];
                  let mathHasCaret = trimmed.includes(CARET_TOKEN);
                  i += 1;
                  while (i < lines.length && stripCaretToken(lines[i].trim()) !== '$$') {
                    mathLines.push(lines[i]);
                    i += 1;
                  }
                  if (i < lines.length) {
                    mathHasCaret = mathHasCaret || lines[i].includes(CARET_TOKEN);
                    i += 1;
                  }
                  const source = mathLines.join('\n');
                  blocks.push(`<figure data-md-block="math"><pre>${escapeHtml(source)}</pre><div class="math-render" contenteditable="false">${escapeHtml(source)}</div></figure>${mathHasCaret ? CARET_TOKEN : ''}`);
                  continue;
                }

                if (isFence(trimmed)) {
                  const info = fenceInfo(trimmed);
                  let fenceHasCaret = trimmed.includes(CARET_TOKEN);
                  const codeLines = [];
                  i += 1;
                  while (i < lines.length && !stripCaretToken(lines[i].trim()).startsWith(info.marker)) {
                    codeLines.push(lines[i]);
                    i += 1;
                  }
                  if (i < lines.length) {
                    fenceHasCaret = fenceHasCaret || lines[i].includes(CARET_TOKEN);
                    i += 1;
                  }
                  const source = codeLines.join('\n');
                  const lang = info.language.toLowerCase();
                  const caretSuffix = fenceHasCaret ? CARET_TOKEN : '';
                  if (['mermaid', 'sequence', 'flow'].includes(lang)) {
                    blocks.push(`<figure data-md-block="diagram" data-lang="${escapeAttr(info.language || 'mermaid')}"><pre>${escapeHtml(source)}</pre><div class="diagram-render" contenteditable="false">Rendering Mermaid...</div></figure>${caretSuffix}`);
                  } else {
                    blocks.push(`<pre data-md-block="code" data-lang="${escapeAttr(info.language)}"><code>${escapeHtml(source)}</code></pre>${caretSuffix}`);
                  }
                  continue;
                }

                const imageHasCaret = trimmed.includes(CARET_TOKEN);
                const image = parseMarkdownImageLine(trimmed);
                if (image) {
                  blocks.push(imageFigureHTML(image) + (imageHasCaret ? CARET_TOKEN : ''));
                  i += 1;
                  continue;
                }

                const rawImage = parseRawHTMLImage(trimmed);
                if (rawImage) {
                  blocks.push(imageFigureHTML(rawImage, true) + (imageHasCaret ? CARET_TOKEN : ''));
                  i += 1;
                  continue;
                }

                const rawMedia = parseRawHTMLMedia(trimmed);
                if (rawMedia) {
                  blocks.push(mediaFigureHTML(rawMedia) + (imageHasCaret ? CARET_TOKEN : ''));
                  i += 1;
                  continue;
                }

                const referenceDefinition = parseReferenceDefinition(trimmed);
                if (referenceDefinition) {
                  const title = referenceDefinition.title ? ` "${escapeHtml(referenceDefinition.title)}"` : '';
                  blocks.push(`<section class="link-reference" data-md-block="link-reference" data-label="${escapeAttr(referenceDefinition.label)}" data-src="${escapeAttr(referenceDefinition.source)}" data-title="${escapeAttr(referenceDefinition.title || '')}"><code>[${escapeHtml(referenceDefinition.label)}]: ${escapeHtml(referenceDefinition.source)}${title}</code></section>`);
                  i += 1;
                  continue;
                }

                if (i + 1 < lines.length && line.includes('|') && isTableDelimiter(lines[i + 1])) {
                  const headers = splitTableRow(line);
                  const alignments = splitTableRow(lines[i + 1]).map(tableAlignment);
                  i += 2;
                  const rows = [];
                  while (i < lines.length && lines[i].includes('|') && lines[i].trim()) {
                    rows.push(splitTableRow(lines[i]));
                    i += 1;
                  }
                  const headerHtml = headers.map((cell, index) => `<th style="text-align:${alignments[index] || 'left'}">${parseInline(cell)}</th>`).join('');
                  const rowHtml = rows.map(row => `<tr>${headers.map((_, index) => `<td style="text-align:${alignments[index] || 'left'}">${parseInline(row[index] || '')}</td>`).join('')}</tr>`).join('');
                  blocks.push(`<table data-md-block="table"><thead><tr>${headerHtml}</tr></thead><tbody>${rowHtml}</tbody></table>`);
                  continue;
                }

                if (/^>\s?/.test(trimmed)) {
                  const quoteLines = [];
                  while (i < lines.length && /^>\s?/.test(lines[i].trim())) {
                    quoteLines.push(lines[i].trim().replace(/^>\s?/, ''));
                    i += 1;
                  }
                  const first = quoteLines[0]?.match(/^\[!([A-Za-z]+)\]\s*(.*)$/);
                  if (first) {
                    const title = first[1].toUpperCase();
                    const body = [first[2], ...quoteLines.slice(1)].filter(Boolean).join('\n');
                    blocks.push(`<section class="callout" data-md-block="callout" data-title="${escapeAttr(title)}"><p class="callout-title">${escapeHtml(title)}</p><p>${parseInline(body)}</p></section>`);
                  } else {
                    blocks.push(`<blockquote>${quoteLines.map(value => `<p>${parseInline(value)}</p>`).join('')}</blockquote>`);
                  }
                  continue;
                }

                const footnote = trimmed.match(/^\[\^([^\]]+)\]:\s*(.*)$/);
                if (footnote) {
                  blocks.push(`<section class="footnote-def" data-md-block="footnote-def" data-label="${escapeAttr(footnote[1])}"><sup>${escapeHtml(footnote[1])}</sup><span>${parseInline(footnote[2] || '')}</span></section>`);
                  i += 1;
                  continue;
                }

                const listInfo = listItemInfo(line);
                if (listInfo) {
                  const list = nestedListHTML(lines, i, listInfo.indent, listInfo.ordered);
                  blocks.push(list.html);
                  i = list.nextIndex;
                  continue;
                }

                const paragraphLines = [trimmed];
                i += 1;
                while (i < lines.length && !isBlockStart(lines, i)) {
                  paragraphLines.push(lines[i].trim());
                  i += 1;
                }
                blocks.push(`<p>${parseInline(paragraphLines.join(' '))}</p>`);
              }

              return blocks.join('\n') || '<p><br></p>';
            }

            function serializeInline(node) {
              if (node.nodeType === Node.TEXT_NODE) return node.textContent || '';
              if (node.nodeType !== Node.ELEMENT_NODE) return '';

              const tag = node.tagName.toLowerCase();
              if (tag === 'br') return '\n';
              if (tag === 'input') return '';
              if (tag === 'img') {
                const alt = node.getAttribute('alt') || '';
                const src = node.getAttribute('data-md-src') || node.getAttribute('src') || '';
                const title = node.getAttribute('title') || '';
                const referenceLabel = node.dataset.mdReferenceLabel;
                if (referenceLabel) return `![${alt}][${referenceLabel}]`;
                return title ? `![${alt}](${src} "${title}")` : `![${alt}](${src})`;
              }
              if (tag === 'span' && node.dataset.mdInline === 'math') {
                const source = node.dataset.source || node.textContent || '';
                return `$${source}$`;
              }
              if (tag === 'sup' && node.dataset.mdFootnoteRef) {
                return `[^${node.dataset.mdFootnoteRef}]`;
              }

              const inner = Array.from(node.childNodes).map(serializeInline).join('');
              if (!inner && tag !== 'code') return '';

              if (tag === 'strong' || tag === 'b') return `**${inner}**`;
              if (tag === 'em' || tag === 'i') return `*${inner}*`;
              if (tag === 'code') return `\`${inner}\``;
              if (tag === 'u') return `<u>${inner}</u>`;
              if (tag === 'kbd') return `<kbd>${inner}</kbd>`;
              if (tag === 'del' || tag === 's') return `~~${inner}~~`;
              if (tag === 'mark') return `==${inner}==`;
              if (tag === 'sub') return `~${inner}~`;
              if (tag === 'sup') return `^${inner}^`;
              if (tag === 'a') {
                const href = node.getAttribute('href') || '';
                const referenceLabel = node.dataset.mdReferenceLabel;
                if (referenceLabel) return `[${inner}][${referenceLabel}]`;
                return href ? `[${inner}](${href})` : inner;
              }
              return inner;
            }

            function listMarkdown(list, indent = 0) {
              const ordered = list.tagName.toLowerCase() === 'ol';
              return Array.from(list.children)
                .filter(child => child.tagName?.toLowerCase() === 'li')
                .map((li, index) => listItemMarkdown(li, ordered, index, indent))
                .join('\n');
            }

            function listItemMarkdown(li, ordered, index, indent = 0) {
              const clone = li.cloneNode(true);
              clone.querySelectorAll('ul, ol').forEach(child => child.remove());
              const checkbox = clone.querySelector('input[type="checkbox"]');
              const isTask = Boolean(checkbox) || li.hasAttribute('data-task');
              if (checkbox) checkbox.remove();
              const value = serializeInline(clone).trim();
              const prefix = ' '.repeat(indent);
              const line = isTask
                ? `${prefix}- [${checkbox?.checked ? 'x' : ' '}] ${value}`
                : (ordered ? `${prefix}${index + 1}. ${value}` : `${prefix}- ${value}`);
              const children = Array.from(li.children)
                .filter(child => ['ul', 'ol'].includes(child.tagName?.toLowerCase()))
                .map(child => listMarkdown(child, indent + 2))
                .filter(Boolean);
              return [line, ...children].join('\n');
            }

            function tableMarkdown(table) {
              const headerCells = Array.from(table.querySelectorAll('thead th'));
              const headers = headerCells.map(cell => serializeInline(cell).trim());
              const bodyRows = Array.from(table.querySelectorAll('tbody tr')).map(row =>
                Array.from(row.children).map(cell => serializeInline(cell).trim())
              );
              if (!headers.length) return '';
              const delimiter = headerCells.map(cell => {
                const align = (cell.style.textAlign || '').toLowerCase();
                if (align === 'center') return ':---:';
                if (align === 'right' || align === 'end') return '---:';
                return '---';
              });
              const lines = [
                `| ${headers.join(' | ')} |`,
                `| ${delimiter.join(' | ')} |`,
                ...bodyRows.map(row => `| ${headers.map((_, index) => row[index] || '').join(' | ')} |`)
              ];
              return lines.join('\n');
            }

            function blockMarkdown(node) {
              if (node.nodeType !== Node.ELEMENT_NODE) return (node.textContent || '').trim();

              const tag = node.tagName.toLowerCase();
              if (/^h[1-6]$/.test(tag)) {
                return `${'#'.repeat(Number(tag[1]))} ${serializeInline(node).trim()}`;
              }
              if (tag === 'p') {
                const value = serializeInline(node).trim();
                return value === '\n' ? '' : value;
              }
              if (tag === 'blockquote') {
                return Array.from(node.children)
                  .map(child => serializeInline(child).trim())
                  .filter(Boolean)
                  .map(line => `> ${line}`)
                  .join('\n');
              }
              if (tag === 'section' && node.dataset.mdBlock === 'callout') {
                const title = node.dataset.title || node.querySelector('.callout-title')?.textContent?.trim() || 'NOTE';
                const body = Array.from(node.children)
                  .filter(child => !child.classList.contains('callout-title'))
                  .map(child => serializeInline(child).trim())
                  .filter(Boolean);
                return [`> [!${title}]`, ...body.map(line => `> ${line}`)].join('\n');
              }
              if (tag === 'ul' || tag === 'ol') {
                return listMarkdown(node);
              }
              if (tag === 'pre') {
                if (node.dataset.mdBlock === 'front-matter') {
                  const code = node.textContent?.replace(/\n$/, '') || '';
                  return `---\n${code}\n---`;
                }
                const language = node.dataset.lang || '';
                const code = node.textContent?.replace(/\n$/, '') || '';
                return `\`\`\`${language}\n${code}\n\`\`\``;
              }
              if (tag === 'table') {
                return tableMarkdown(node);
              }
              if (tag === 'figure' && node.dataset.mdBlock === 'image') {
                const image = node.querySelector('img');
                const alt = image?.getAttribute('alt') || node.dataset.alt || '';
                const src = node.dataset.src || image?.getAttribute('data-md-src') || image?.getAttribute('src') || '';
                const title = image?.getAttribute('title') || node.dataset.title || '';
                return title ? `![${alt}](${src} "${title}")` : `![${alt}](${src})`;
              }
              if (tag === 'figure' && node.dataset.mdBlock === 'html-image') {
                const rawHTML = node.dataset.rawHtml;
                if (rawHTML) return rawHTML;

                const image = node.querySelector('img');
                const src = node.dataset.src || image?.getAttribute('src') || '';
                const alt = image?.getAttribute('alt') || node.dataset.alt || '';
                const title = image?.getAttribute('title') || node.dataset.title || '';
                const style = image?.getAttribute('style') || node.dataset.style || '';
                const titleAttr = title ? ` title="${title.replace(/"/g, '&quot;')}"` : '';
                const styleAttr = style ? ` style="${style.replace(/"/g, '&quot;')}"` : '';
                return `<img src="${src.replace(/"/g, '&quot;')}" alt="${alt.replace(/"/g, '&quot;')}"${titleAttr}${styleAttr} />`;
              }
              if (tag === 'figure' && node.dataset.mdBlock === 'html-media') {
                const rawHTML = node.dataset.rawHtml;
                if (rawHTML) return rawHTML;

                const media = node.querySelector('video, audio, iframe');
                const mediaTag = media?.tagName?.toLowerCase() || node.dataset.tag || 'video';
                const src = node.dataset.src || media?.getAttribute('src') || '';
                const title = media?.getAttribute('title') || '';
                const titleAttr = title ? ` title="${title.replace(/"/g, '&quot;')}"` : '';
                const controlsAttr = mediaTag === 'iframe' ? '' : ' controls';
                return `<${mediaTag} src="${src.replace(/"/g, '&quot;')}"${titleAttr}${controlsAttr}></${mediaTag}>`;
              }
              if (tag === 'figure' && node.dataset.mdBlock === 'diagram') {
                const language = node.dataset.lang || 'mermaid';
                const code = node.querySelector('pre')?.textContent?.replace(/\n$/, '') || '';
                return `\`\`\`${language}\n${code}\n\`\`\``;
              }
              if (tag === 'figure' && node.dataset.mdBlock === 'math') {
                const code = node.querySelector('pre')?.textContent?.replace(/\n$/, '') || '';
                return `$$\n${code}\n$$`;
              }
              if (tag === 'section' && node.dataset.mdBlock === 'footnote-def') {
                const label = node.dataset.label || '';
                const body = serializeInline(node.querySelector('span') || node).trim();
                return `[^${label}]: ${body}`;
              }
              if (tag === 'section' && node.dataset.mdBlock === 'link-reference') {
                const label = node.dataset.label || '';
                const source = node.dataset.src || '';
                const title = node.dataset.title || '';
                return title ? `[${label}]: ${source} "${title}"` : `[${label}]: ${source}`;
              }
              if (tag === 'div' && node.dataset.mdBlock === 'toc') {
                return '[toc]';
              }
              if (tag === 'hr') {
                return '---';
              }
              return serializeInline(node).trim();
            }

            function htmlToMarkdown() {
              const blocks = [];
              let inlineBuffer = '';

              function flushInlineBuffer() {
                const value = inlineBuffer.trim();
                if (value) blocks.push(value);
                inlineBuffer = '';
              }

              for (const node of Array.from(editor.childNodes)) {
                if (isInlineRootNode(node)) {
                  inlineBuffer += serializeInline(node);
                  continue;
                }

                flushInlineBuffer();
                const value = blockMarkdown(node).trim();
                if (value) blocks.push(value);
              }

              flushInlineBuffer();

              return blocks
                .filter(value => value.length > 0)
                .join('\n\n')
                .replace(/\n{3,}/g, '\n\n');
            }

            function currentMarkdown() {
              return stripCaretToken(htmlToMarkdown());
            }

            function isInlineRootNode(node) {
              if (node.nodeType === Node.TEXT_NODE) return true;
              if (node.nodeType !== Node.ELEMENT_NODE) return false;

              return ['a', 'b', 'br', 'code', 'del', 'em', 'i', 'img', 'kbd', 'mark', 's', 'span', 'strong', 'sub', 'sup', 'u'].includes(node.tagName.toLowerCase());
            }

            function emitMarkdownChanged() {
              if (isSettingMarkdown) return;
              const markdown = currentMarkdown();
              if (markdown === lastPostedMarkdown) return;
              lastPostedMarkdown = markdown;
              post({ type: 'markdownChanged', markdown });
            }

            function scheduleEmit() {
              window.clearTimeout(emitTimer);
              emitTimer = window.setTimeout(emitMarkdownChanged, 80);
            }

            function scheduleEnhancementRender() {
              window.clearTimeout(renderTimer);
              renderTimer = window.setTimeout(renderEnhancements, 180);
            }

            function rawMarkdownNeedsRender(value) {
              const lines = String(value).replace(/\r\n/g, '\n').split('\n');
              const trimmed = String(value).trim();
              if (!trimmed) return false;

              if (/^#{1,6}\s+/.test(trimmed)) return true;
              if (/^([-*_])\s*\1\s*\1\s*$/.test(trimmed)) return true;
              if (parseMarkdownImageLine(trimmed)) return true;
              if (parseRawHTMLImage(trimmed)) return true;
              if (parseRawHTMLMedia(trimmed)) return true;
              if (parseReferenceDefinition(trimmed)) return true;
              if (trimmed === '$$' || trimmed.startsWith('$$\n')) return true;
              if (trimmed.startsWith('---\n')) return true;
              if (trimmed.toLowerCase() === '[toc]') return true;
              if (/^\[\^([^\]]+)\]:\s*/.test(trimmed)) return true;
              if (isFence(trimmed)) return true;
              if (/^>\s?/.test(trimmed)) return true;
              if (/^[-*+]\s+/.test(trimmed)) return true;
              if (/^\d+[.)]\s+/.test(trimmed)) return true;
              if (/!\[([^\]]*)\]\((.+?)\)/.test(trimmed)) return true;
              if (/!\[([^\]]*)\]\[([^\]]*)\]/.test(trimmed)) return true;
              if (/\[([^\]]+)\]\(([^)]+)\)/.test(trimmed)) return true;
              if (/\[([^\]]+)\]\[([^\]]*)\]/.test(trimmed)) return true;
              if (/<https?:\/\/[^>\s]+>/.test(trimmed)) return true;
              if (/\[\^([^\]]+)\]/.test(trimmed)) return true;
              if (/\$([^$\n]+)\$/.test(trimmed)) return true;
              if (/`([^`]+)`/.test(trimmed)) return true;
              if (/~~([^~\n]+)~~/.test(trimmed)) return true;
              if (/==([^=\n]+)==/.test(trimmed)) return true;
              if (/\*\*([^*\n]+)\*\*/.test(trimmed)) return true;
              if (/__([^_\n]+)__/.test(trimmed)) return true;
              if (/(^|[^*])\*([^*\n]+)\*/.test(trimmed)) return true;
              if (/(^|[^_])_([^_\n]+)_/.test(trimmed)) return true;
              if (/(^|[^~])~([^~\n]+)~/.test(trimmed)) return true;
              if (/(^|[^^])\^([^^\n]+)\^/.test(trimmed)) return true;

              return lines.some((line, index) => {
                const current = line.trim();
                if (!current) return false;
                if (isFence(current) || current === '$$') return true;
                if (parseRawHTMLImage(current)) return true;
                if (parseRawHTMLMedia(current)) return true;
                if (parseReferenceDefinition(current)) return true;
                if (/^\[\^([^\]]+)\]:\s*/.test(current)) return true;
                if (index === 0 && current === '---' && lines.slice(1).some(value => ['---', '...'].includes(value.trim()))) return true;
                if (index + 1 < lines.length && current.includes('|') && isTableDelimiter(lines[index + 1])) return true;
                return false;
              });
            }

            function editorNeedsMarkdownNormalization() {
              return Array.from(editor.childNodes).some(node => {
                if (node.nodeType === Node.TEXT_NODE) {
                  return rawMarkdownNeedsRender(node.textContent || '');
                }

                if (node.nodeType !== Node.ELEMENT_NODE) return false;

                const tag = node.tagName.toLowerCase();
                if (!['p', 'div'].includes(tag)) return false;
                if (node.dataset.mdBlock || node.classList.contains('toc')) return false;
                if (node.closest('blockquote, li, pre, table, figure, section')) return false;

                return rawMarkdownNeedsRender(node.innerText || node.textContent || '');
              });
            }

            function normalizeMarkdownIfNeeded() {
              if (isSettingMarkdown || !editorNeedsMarkdownNormalization()) return;

              const caretPayload = markdownWithCaretToken();
              const markdown = caretPayload.markdown;
              const cleanMarkdown = stripCaretToken(markdown);
              if (cleanMarkdown !== lastPostedMarkdown) {
                lastPostedMarkdown = cleanMarkdown;
                post({ type: 'markdownChanged', markdown: cleanMarkdown });
              }
              setMarkdown(markdown, {
                preserveCaretToken: caretPayload.hasCaret,
                preserveSelection: !caretPayload.hasCaret
              });
            }

            function scheduleMarkdownNormalization() {
              window.clearTimeout(normalizeTimer);
              normalizeTimer = window.setTimeout(normalizeMarkdownIfNeeded, 360);
            }

            async function loadMermaid() {
              if (!mermaidModulePromise) {
                mermaidModulePromise = import('https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs')
                  .then(module => {
                    module.default.initialize({ startOnLoad: false, theme: 'dark' });
                    return module.default;
                  });
              }
              return mermaidModulePromise;
            }

            async function renderDiagrams(serial) {
              const figures = Array.from(editor.querySelectorAll('figure[data-md-block="diagram"]'));
              if (!figures.length) return;

              for (const figure of figures) {
                const target = figure.querySelector('.diagram-render');
                const source = figure.querySelector('pre')?.textContent || '';
                if (!target || !source.trim()) continue;
                target.innerHTML = fallbackDiagramSVG(source, figure.dataset.lang || 'mermaid');
              }

              try {
                const mermaid = await loadMermaid();
                for (const figure of figures) {
                  if (serial !== renderSerial) return;
                  const target = figure.querySelector('.diagram-render');
                  const source = figure.querySelector('pre')?.textContent || '';
                  if (!target || !source.trim()) continue;
                  try {
                    const id = `simplelime-mermaid-${serial}-${Math.random().toString(36).slice(2)}`;
                    const result = await mermaid.render(id, source);
                    target.innerHTML = result.svg;
                  } catch (error) {
                    target.textContent = 'Mermaid render failed: ' + error.message;
                  }
                }
              } catch {
                return;
              }
            }

            function renderMath() {
              for (const figure of editor.querySelectorAll('figure[data-md-block="math"]')) {
                const target = figure.querySelector('.math-render');
                const source = figure.querySelector('pre')?.textContent || '';
                if (!target) continue;
                target.innerHTML = source.trim() ? fallbackMathHTML(source, true) : '';
                if (window.katex && source.trim()) {
                  try {
                    window.katex.render(source, target, { displayMode: true, throwOnError: false });
                  } catch {
                    target.innerHTML = fallbackMathHTML(source, true);
                  }
                }
              }

              for (const target of editor.querySelectorAll('.inline-math[data-md-inline="math"]')) {
                const source = target.dataset.source || target.textContent || '';
                target.innerHTML = source.trim() ? fallbackMathHTML(source, false) : '';
                if (window.katex && source.trim()) {
                  try {
                    window.katex.render(source, target, { displayMode: false, throwOnError: false });
                  } catch {
                    target.innerHTML = fallbackMathHTML(source, false);
                  }
                }
              }
            }

            function renderEnhancements() {
              renderSerial += 1;
              renderMath();
              renderDiagrams(renderSerial);
            }

            function selectionTextOffset() {
              const selection = window.getSelection();
              if (!selection || selection.rangeCount === 0) return null;

              const range = selection.getRangeAt(0);
              if (!editor.contains(range.startContainer)) return null;

              const originalRange = range.cloneRange();
              const tokenRange = range.cloneRange();
              tokenRange.collapse(true);
              const tokenNode = document.createTextNode(CARET_TOKEN);
              tokenRange.insertNode(tokenNode);
              const markdown = htmlToMarkdown();
              const markdownOffset = markdown.indexOf(CARET_TOKEN);
              tokenNode.parentNode?.removeChild(tokenNode);
              selection.removeAllRanges();
              selection.addRange(originalRange);
              if (markdownOffset >= 0) return markdownOffset;

              const prefix = range.cloneRange();
              prefix.selectNodeContents(editor);
              prefix.setEnd(range.startContainer, range.startOffset);
              return stripCaretToken(prefix.toString()).length;
            }

            function atomicSourceFigureForNode(node) {
              const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
              const pre = element?.closest?.('figure[data-md-block="diagram"] > pre, figure[data-md-block="math"] > pre');
              return pre?.parentElement || null;
            }

            function placeCaretAroundAtomicFigure(figure, after = true) {
              if (!figure) return false;

              const range = document.createRange();
              if (after) {
                range.setStartAfter(figure);
              } else {
                range.setStartBefore(figure);
              }
              range.collapse(true);

              focusEditor();
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              scrollElementIntoView(figure);
              return true;
            }

            function scrollRectIntoView(rect) {
              if (!rect || !Number.isFinite(rect.top) || !Number.isFinite(rect.bottom)) return;

              const topPadding = 90;
              const bottomPadding = 120;
              const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
              if (viewportHeight <= 0) return;

              if (rect.top < topPadding || rect.bottom > viewportHeight - bottomPadding) {
                const targetTop = window.scrollY + rect.top - Math.max(topPadding, viewportHeight * 0.36);
                const top = Math.max(0, targetTop);
                const scrollingElement = document.scrollingElement || document.documentElement || document.body;
                window.scrollTo(window.scrollX, top);
                scrollingElement.scrollTop = top;
                document.documentElement.scrollTop = top;
                document.body.scrollTop = top;
              }
            }

            function scrollElementIntoView(element) {
              if (!element?.getBoundingClientRect) return;
              const run = () => scrollRectIntoView(element.getBoundingClientRect());
              run();
              window.setTimeout(run, 0);
            }

            function scrollRangeIntoView(range) {
              if (!range) return;
              const run = () => {
                const node = range.startContainer;
                const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
                if (element?.scrollIntoView) {
                  element.scrollIntoView({ block: 'center', inline: 'nearest' });
                }

                const rect = range.getClientRects?.()[0] || range.getBoundingClientRect?.();
                if (rect && (rect.width || rect.height)) {
                  scrollRectIntoView(rect);
                  return;
                }

                if (element?.scrollIntoView) {
                  element.scrollIntoView({ block: 'center', inline: 'nearest' });
                } else {
                  scrollElementIntoView(element);
                }
              };
              run();
              window.setTimeout(run, 0);
            }

            function emitSelectionChanged() {
              if (isSettingMarkdown) return;
              const offset = selectionTextOffset();
              if (offset == null || offset === lastPostedSelectionOffset) return;
              lastPostedSelectionOffset = offset;
              post({ type: 'selectionChanged', location: offset });
            }

            function scheduleSelectionChanged() {
              window.clearTimeout(selectionTimer);
              selectionTimer = window.setTimeout(emitSelectionChanged, 60);
            }

            function setSelectionRenderedTextOffset(targetOffset) {
              const walker = document.createTreeWalker(
                editor,
                NodeFilter.SHOW_TEXT,
                {
                  acceptNode(node) {
                    const parent = node.parentElement;
                    if (parent?.closest?.('.diagram-render, .math-render')) {
                      return NodeFilter.FILTER_REJECT;
                    }
                    return NodeFilter.FILTER_ACCEPT;
                  }
                }
              );
              let remaining = targetOffset;
              let lastTextNode = null;

              while (walker.nextNode()) {
                const node = walker.currentNode;
                lastTextNode = node;
                const length = node.textContent.length;

                if (remaining <= length) {
                  const atomicFigure = atomicSourceFigureForNode(node);
                  if (atomicFigure && placeCaretAroundAtomicFigure(atomicFigure, remaining > 0)) {
                    lastRestoredCaretOffset = targetOffset - remaining + Math.min(remaining, length);
                    lastPostedSelectionOffset = lastRestoredCaretOffset;
                    return;
                  }

                  const range = document.createRange();
                  range.setStart(node, remaining);
                  range.collapse(true);

                  const selection = window.getSelection();
                  selection.removeAllRanges();
                  selection.addRange(range);
                  scrollRangeIntoView(range);
                  lastRestoredCaretOffset = targetOffset - remaining + Math.min(remaining, length);
                  lastPostedSelectionOffset = lastRestoredCaretOffset;
                  return;
                }

                remaining -= length;
              }

              const range = document.createRange();
              if (lastTextNode) {
                range.setStart(lastTextNode, lastTextNode.textContent.length);
              } else {
                range.selectNodeContents(editor);
                range.collapse(false);
              }
              range.collapse(true);

              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              scrollRangeIntoView(range);
              lastRestoredCaretOffset = targetOffset;
              lastPostedSelectionOffset = lastRestoredCaretOffset;
            }

            function setSelectionTextOffset(offset) {
              if (offset == null) return;

              focusEditor();

              const requestedOffset = Number(offset);
              const sourceMarkdown = currentMarkdown();
              const targetOffset = Number.isFinite(requestedOffset)
                ? Math.min(Math.max(0, requestedOffset), sourceMarkdown.length)
                : sourceMarkdown.length;
              const markdownWithSelectionToken =
                sourceMarkdown.slice(0, targetOffset) +
                CARET_TOKEN +
                sourceMarkdown.slice(targetOffset);

              if (setMarkdown(markdownWithSelectionToken, { preserveCaretToken: true })) {
                lastRestoredCaretOffset = targetOffset;
                lastPostedSelectionOffset = targetOffset;
                return;
              }

              setSelectionRenderedTextOffset(targetOffset);
            }

            function markdownWithCaretToken() {
              const fallback = { markdown: currentMarkdown(), hasCaret: false };
              const selection = window.getSelection();
              if (!selection || selection.rangeCount === 0) return fallback;

              const range = selection.getRangeAt(0);
              if (!editor.contains(range.startContainer)) return fallback;

              range.deleteContents();

              const tokenNode = document.createTextNode(CARET_TOKEN);
              range.insertNode(tokenNode);

              const nextRange = document.createRange();
              nextRange.setStartAfter(tokenNode);
              nextRange.collapse(true);
              selection.removeAllRanges();
              selection.addRange(nextRange);

              const markdown = htmlToMarkdown();
              return {
                markdown,
                hasCaret: markdown.includes(CARET_TOKEN)
              };
            }

            function restoreCaretToken() {
              let consumed = 0;
              const walker = document.createTreeWalker(editor, NodeFilter.SHOW_TEXT);

              while (walker.nextNode()) {
                const node = walker.currentNode;
                const index = node.textContent.indexOf(CARET_TOKEN);
                if (index === -1) {
                  consumed += stripCaretToken(node.textContent).length;
                  continue;
                }

                node.textContent = node.textContent.split(CARET_TOKEN).join('');
                const safeIndex = Math.min(index, node.textContent.length);
                const atomicFigure = atomicSourceFigureForNode(node);
                if (atomicFigure && placeCaretAroundAtomicFigure(atomicFigure, true)) {
                  lastRestoredCaretOffset = consumed + safeIndex;
                  lastPostedSelectionOffset = lastRestoredCaretOffset;
                  return true;
                }

                const range = document.createRange();
                range.setStart(node, safeIndex);
                range.collapse(true);

                focusEditor();
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
                scrollRangeIntoView(range);
                lastRestoredCaretOffset = consumed + safeIndex;
                lastPostedSelectionOffset = lastRestoredCaretOffset;
                return true;
              }

              return false;
            }

            function setMarkdown(markdown, options = {}) {
              const selectionOffset = options.preserveSelection ? selectionTextOffset() : null;
              const markdownForRender = String(markdown);
              const cleanMarkdown = stripCaretToken(markdownForRender);
              isSettingMarkdown = true;
              editor.innerHTML = markdownToHtml(markdownForRender);
              lastPostedMarkdown = cleanMarkdown;
              renderEnhancements();
              isSettingMarkdown = false;
              if (options.preserveCaretToken && restoreCaretToken()) {
                return true;
              }
              if (options.preserveSelection) {
                setSelectionTextOffset(selectionOffset);
              }
              return false;
            }

            function tableCellFromSelection() {
              const selection = window.getSelection();
              if (!selection || selection.rangeCount === 0) return activeTableCell;
              const node = selection.getRangeAt(0).startContainer;
              const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
              return element?.closest?.('td, th') || activeTableCell;
            }

            function tableColumnIndex(cell) {
              return Math.max(0, Array.from(cell.parentElement?.children || []).indexOf(cell));
            }

            function tableColumnAlignment(table, index) {
              const header = table.querySelectorAll('thead th')[index];
              return header?.style?.textAlign || 'left';
            }

            function tableSetCellAlignment(cell, align) {
              cell.style.textAlign = align;
            }

            function tableMakeCell(tagName, align, text = '') {
              const cell = document.createElement(tagName);
              tableSetCellAlignment(cell, align || 'left');
              cell.textContent = text;
              return cell;
            }

            function tableEnsureBody(table) {
              let body = table.querySelector('tbody');
              if (!body) {
                body = document.createElement('tbody');
                table.appendChild(body);
              }
              return body;
            }

            function tableEmitChange() {
              ensureTaskCheckboxes();
              scheduleEnhancementRender();
              emitMarkdownChanged();
              updateTableToolbar();
            }

            function tableAction(action) {
              const cell = tableCellFromSelection();
              const table = cell?.closest?.('table');
              if (!cell || !table) return false;

              activeTableCell = cell;
              const index = tableColumnIndex(cell);
              const headerCells = Array.from(table.querySelectorAll('thead th'));
              const columnCount = Math.max(1, headerCells.length || cell.parentElement.children.length);
              const body = tableEnsureBody(table);

              if (action === 'addRowAfter') {
                const row = document.createElement('tr');
                for (let i = 0; i < columnCount; i += 1) {
                  row.appendChild(tableMakeCell('td', tableColumnAlignment(table, i)));
                }

                const currentRow = cell.closest('tr');
                if (currentRow?.parentElement === body) {
                  currentRow.after(row);
                } else {
                  body.insertBefore(row, body.firstChild);
                }
                activeTableCell = row.children[Math.min(index, row.children.length - 1)] || activeTableCell;
                tableEmitChange();
                return true;
              }

              if (action === 'deleteRow') {
                const row = cell.closest('tr');
                if (row?.parentElement === body && body.rows.length > 1) {
                  const nextRow = row.nextElementSibling || row.previousElementSibling;
                  row.remove();
                  activeTableCell = nextRow?.children[Math.min(index, nextRow.children.length - 1)] || headerCells[index] || null;
                } else if (row?.parentElement === body) {
                  Array.from(row.children).forEach(child => child.textContent = '');
                }
                tableEmitChange();
                return true;
              }

              if (action === 'addColumnAfter') {
                const insertAt = index + 1;
                const headerRow = table.querySelector('thead tr');
                const align = tableColumnAlignment(table, index);
                if (headerRow) {
                  headerRow.insertBefore(tableMakeCell('th', align, 'Column'), headerRow.children[insertAt] || null);
                }
                for (const row of Array.from(body.rows)) {
                  row.insertBefore(tableMakeCell('td', align), row.children[insertAt] || null);
                }
                activeTableCell = headerRow?.children[insertAt] || activeTableCell;
                tableEmitChange();
                return true;
              }

              if (action === 'deleteColumn') {
                if (columnCount <= 1) return false;
                for (const row of Array.from(table.rows)) {
                  row.children[index]?.remove();
                }
                activeTableCell = table.querySelectorAll('thead th')[Math.max(0, index - 1)] || table.querySelector('td, th');
                tableEmitChange();
                return true;
              }

              const alignments = {
                alignLeft: 'left',
                alignCenter: 'center',
                alignRight: 'right'
              };
              if (alignments[action]) {
                for (const row of Array.from(table.rows)) {
                  const target = row.children[index];
                  if (target) tableSetCellAlignment(target, alignments[action]);
                }
                tableEmitChange();
                return true;
              }

              return false;
            }

            function updateTableToolbar() {
              const cell = tableCellFromSelection();
              const table = cell?.closest?.('table');
              if (!table || !tableToolbar) {
                tableToolbar?.classList.remove('is-visible');
                return;
              }

              activeTableCell = cell;
              const rect = table.getBoundingClientRect();
              tableToolbar.style.left = `${Math.max(8, rect.left)}px`;
              tableToolbar.style.top = `${Math.max(8, rect.top - tableToolbar.offsetHeight - 6)}px`;
              tableToolbar.classList.add('is-visible');
            }

            function focusEditor() {
              editor.focus({ preventScroll: true });
            }

            function wrapSelection(tagName) {
              focusEditor();
              const selection = window.getSelection();
              if (!selection || selection.rangeCount === 0) return;
              const range = selection.getRangeAt(0);
              const element = document.createElement(tagName);
              if (range.collapsed) {
                element.textContent = tagName === 'code' ? 'code' : 'text';
                range.insertNode(element);
                range.selectNodeContents(element);
              } else {
                element.appendChild(range.extractContents());
                range.insertNode(element);
                selection.removeAllRanges();
                const nextRange = document.createRange();
                nextRange.selectNodeContents(element);
                selection.addRange(nextRange);
              }
            }

            function ensureTaskCheckboxes() {
              for (const li of editor.querySelectorAll('li[data-task]')) {
                if (!li.querySelector('input[type="checkbox"]')) {
                  const input = document.createElement('input');
                  input.type = 'checkbox';
                  input.checked = li.dataset.task === 'checked';
                  li.prepend(input);
                }
              }
            }

            function listItemFromSelection() {
              const selection = window.getSelection();
              if (!selection || selection.rangeCount === 0) return null;
              const node = selection.getRangeAt(0).startContainer;
              const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
              return element?.closest?.('li') || null;
            }

            function listItemOwnText(li) {
              if (!li) return '';
              const clone = li.cloneNode(true);
              clone.querySelectorAll('ul, ol').forEach(child => child.remove());
              clone.querySelectorAll('input[type="checkbox"]').forEach(child => child.remove());
              return (clone.textContent || '').replace(/\u200B/g, '').trim();
            }

            function focusListItem(li) {
              if (!li) return;
              const cloneRange = document.createRange();
              const walker = document.createTreeWalker(
                li,
                NodeFilter.SHOW_TEXT,
                {
                  acceptNode(node) {
                    return node.parentElement?.closest?.('li') === li
                      ? NodeFilter.FILTER_ACCEPT
                      : NodeFilter.FILTER_REJECT;
                  }
                }
              );
              let lastTextNode = null;
              while (walker.nextNode()) {
                lastTextNode = walker.currentNode;
              }
              if (lastTextNode) {
                cloneRange.setStart(lastTextNode, lastTextNode.textContent.length);
              } else {
                cloneRange.selectNodeContents(li);
              }
              cloneRange.collapse(false);
              focusEditor();
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(cloneRange);
            }

            function indentListItem(li) {
              const list = li?.parentElement;
              const previous = li?.previousElementSibling;
              if (!li || !list || !previous || !['UL', 'OL'].includes(list.tagName)) return false;

              let nestedList = Array.from(previous.children).find(child => child.tagName === list.tagName);
              if (!nestedList) {
                nestedList = document.createElement(list.tagName.toLowerCase());
                previous.appendChild(nestedList);
              }
              nestedList.appendChild(li);
              focusListItem(li);
              return true;
            }

            function outdentListItem(li) {
              const list = li?.parentElement;
              const parentLi = list?.parentElement;
              const parentList = parentLi?.parentElement;
              if (!li || !list || parentLi?.tagName !== 'LI' || !['UL', 'OL'].includes(parentList?.tagName || '')) {
                return false;
              }

              const trailingSiblings = [];
              let sibling = li.nextElementSibling;
              while (sibling) {
                trailingSiblings.push(sibling);
                sibling = sibling.nextElementSibling;
              }

              parentLi.after(li);

              if (trailingSiblings.length) {
                let childList = Array.from(li.children).find(child => child.tagName === list.tagName);
                if (!childList) {
                  childList = document.createElement(list.tagName.toLowerCase());
                  li.appendChild(childList);
                }
                trailingSiblings.forEach(item => childList.appendChild(item));
              }

              if (!list.children.length) {
                list.remove();
              }

              focusListItem(li);
              return true;
            }

            function runListIndentCommand(command) {
              const li = listItemFromSelection();
              if (!li) return false;

              const changed = command === 'indent' ? indentListItem(li) : outdentListItem(li);
              if (!changed) {
                focusListItem(li);
                scheduleSelectionChanged();
                return true;
              }

              ensureTaskCheckboxes();
              scheduleEnhancementRender();
              emitMarkdownChanged();
              scheduleSelectionChanged();
              return true;
            }

            function insertListItemAfter(li) {
              const list = li?.parentElement;
              if (!li || !list || !['UL', 'OL'].includes(list.tagName)) return false;

              const nextItem = document.createElement('li');
              if (li.hasAttribute('data-task')) {
                nextItem.dataset.task = 'unchecked';
              }
              nextItem.appendChild(document.createElement('br'));
              li.after(nextItem);

              ensureTaskCheckboxes();
              scheduleEnhancementRender();
              focusListItem(nextItem);
              emitMarkdownChanged();
              scheduleSelectionChanged();
              return true;
            }

            function exitEmptyListItem() {
              const li = listItemFromSelection();
              if (!li || listItemOwnText(li)) return false;

              if (!outdentListItem(li)) {
                const list = li.parentElement;
                const paragraph = document.createElement('p');
                paragraph.appendChild(document.createElement('br'));
                list.after(paragraph);
                li.remove();
                if (!list.children.length) list.remove();

                const range = document.createRange();
                range.selectNodeContents(paragraph);
                range.collapse(true);
                focusEditor();
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
              }

              ensureTaskCheckboxes();
              scheduleEnhancementRender();
              emitMarkdownChanged();
              scheduleSelectionChanged();
              return true;
            }

            function insertSiblingListItemAfterEnter() {
              const li = listItemFromSelection();
              if (!li || !listItemOwnText(li)) return false;
              return insertListItemAfter(li);
            }

            function handleListKeydown(event) {
              const key = event.key;

              if (key === 'Tab') {
                const command = event.shiftKey ? 'outdent' : 'indent';
                if (runListIndentCommand(command)) {
                  event.preventDefault();
                  return true;
                }
              }

              if ((key === 'Enter' || key === 'NumpadEnter') && !event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey) {
                if (exitEmptyListItem() || insertSiblingListItemAfterEnter()) {
                  event.preventDefault();
                  return true;
                }
              }

              if (event.metaKey && !event.ctrlKey && !event.altKey && (key === ']' || key === '[')) {
                const command = key === ']' ? 'indent' : 'outdent';
                if (runListIndentCommand(command)) {
                  event.preventDefault();
                  return true;
                }
              }

              return false;
            }

            function simplelimeCommand(name) {
              focusEditor();
              switch (name) {
                case 'bold':
                  document.execCommand('bold');
                  break;
                case 'italic':
                  document.execCommand('italic');
                  break;
                case 'inlineCode':
                  wrapSelection('code');
                  break;
                case 'strikethrough':
                  wrapSelection('del');
                  break;
                case 'highlight':
                  wrapSelection('mark');
                  break;
                case 'subscript':
                  wrapSelection('sub');
                  break;
                case 'superscript':
                  wrapSelection('sup');
                  break;
                case 'heading1':
                  document.execCommand('formatBlock', false, 'H1');
                  break;
                case 'heading2':
                  document.execCommand('formatBlock', false, 'H2');
                  break;
                case 'heading3':
                  document.execCommand('formatBlock', false, 'H3');
                  break;
                case 'unorderedList':
                  document.execCommand('insertUnorderedList');
                  break;
                case 'orderedList':
                  document.execCommand('insertOrderedList');
                  break;
                case 'taskList':
                  document.execCommand('insertUnorderedList');
                  window.requestAnimationFrame(() => {
                    const selection = window.getSelection();
                    const li = selection?.anchorNode?.parentElement?.closest?.('li');
                    if (li) {
                      li.dataset.task = li.dataset.task === 'checked' ? 'unchecked' : 'unchecked';
                      ensureTaskCheckboxes();
                      emitMarkdownChanged();
                    }
                  });
                  break;
                case 'link':
                  insertLinkAtSelection();
                  break;
                case 'image':
                  insertImageMarkdown('image.png', 'image');
                  break;
                case 'table':
                  insertMarkdownAtSelection(['', '', '| Column 1 | Column 2 |', '| --- | --- |', '|  |  |', '', ''].join(String.fromCharCode(10)));
                  break;
                case 'quote':
                  document.execCommand('formatBlock', false, 'BLOCKQUOTE');
                  break;
                case 'codeFence':
                  document.execCommand('formatBlock', false, 'PRE');
                  break;
                case 'mathBlock':
                  insertMarkdownAtSelection(['', '', '$' + '$', 'x = y', '$' + '$', '', ''].join(String.fromCharCode(10)));
                  break;
                case 'mermaidDiagram':
                  insertMarkdownAtSelection(['', '', '```mermaid', 'graph TD', '  A-->B', '```', '', ''].join(String.fromCharCode(10)));
                  break;
                default:
                  return false;
              }
              ensureTaskCheckboxes();
              scheduleEnhancementRender();
              emitMarkdownChanged();
              return true;
            }

            function postShortcut(name) {
              post({ type: 'shortcut', name });
            }

            editor.addEventListener('input', () => {
              ensureTaskCheckboxes();
              scheduleEnhancementRender();
              scheduleMarkdownNormalization();
              scheduleEmit();
              updateTableToolbar();
            });

            editor.addEventListener('change', event => {
              if (event.target?.matches?.('input[type="checkbox"]')) {
                const li = event.target.closest('li');
                if (li) li.dataset.task = event.target.checked ? 'checked' : 'unchecked';
                emitMarkdownChanged();
              }
            });

            editor.addEventListener('pointerdown', event => {
              const cell = event.target?.closest?.('td, th');
              if (cell) {
                activeTableCell = cell;
                window.setTimeout(updateTableToolbar, 0);
              } else {
                activeTableCell = null;
                updateTableToolbar();
              }
            });

            editor.addEventListener('paste', event => {
              if (handleImageFileList(event.clipboardData?.files)) {
                event.preventDefault();
              }
            });

            editor.addEventListener('dragover', event => {
              if (Array.from(event.dataTransfer?.items || []).some(item => item.kind === 'file' && item.type.startsWith('image/'))) {
                event.preventDefault();
              }
            });

            editor.addEventListener('drop', event => {
              if (handleImageFileList(event.dataTransfer?.files)) {
                event.preventDefault();
              }
            });

            tableToolbar?.addEventListener('pointerdown', event => {
              const button = event.target?.closest?.('button[data-action]');
              if (!button) return;
              event.preventDefault();
              tableAction(button.dataset.action);
            });

            document.addEventListener('selectionchange', () => {
              if (document.activeElement === editor || editor.contains(document.activeElement)) {
                updateTableToolbar();
                scheduleSelectionChanged();
              }
            });

            editor.addEventListener('keydown', event => {
              if (handleListKeydown(event)) return;

              const key = event.key.toLowerCase();

              if (event.metaKey && !event.ctrlKey && !event.altKey && key === 'b') {
                event.preventDefault();
                simplelimeCommand('bold');
                return;
              }

              if (event.metaKey && !event.ctrlKey && !event.altKey && key === 'i') {
                event.preventDefault();
                simplelimeCommand('italic');
                return;
              }

              if (event.metaKey && event.shiftKey && !event.altKey && key === 'p') {
                event.preventDefault();
                postShortcut('showCommandPalette');
                return;
              }

              if (event.metaKey && event.shiftKey && !event.altKey && key === 'o') {
                event.preventDefault();
                postShortcut('openFolder');
                return;
              }

              if (event.metaKey && event.altKey && !event.ctrlKey) {
                const modeShortcuts = {
                  Digit1: 'showSourceMode',
                  Digit2: 'showMarkdownPreviewMode',
                  Digit3: 'showMarkdownWysiwygMode',
                  Digit4: 'toggleMiniMap'
                };
                if (modeShortcuts[event.code]) {
                  event.preventDefault();
                  postShortcut(modeShortcuts[event.code]);
                  return;
                }

                const shortcuts = {
                  d: 'toggleDocumentCatalog',
                  p: 'toggleMarkdownPreview',
                  o: 'toggleMarkdownOutline',
                  e: 'toggleWysiwygMode',
                  f: 'toggleFocusMode',
                  t: 'toggleTypewriterMode',
                  z: 'toggleWrapLines'
                };
                if (shortcuts[key]) {
                  event.preventDefault();
                  postShortcut(shortcuts[key]);
                  return;
                }
              }

              if (event.metaKey && !event.ctrlKey && !event.altKey) {
                if (event.shiftKey && key === 'f') {
                  event.preventDefault();
                  postShortcut('showGlobalFind');
                  return;
                }

                if (key === 'g') {
                  event.preventDefault();
                  postShortcut(event.shiftKey ? 'findPrevious' : 'findNext');
                  return;
                }

                const shortcuts = {
                  f: 'showFind',
                  r: 'showReplace'
                };
                if (shortcuts[key]) {
                  event.preventDefault();
                  postShortcut(shortcuts[key]);
                }
              }
            });

            window.simplelimeSetMarkdown = function(markdown) {
              setMarkdown(markdown);
            };
            window.simplelimeSetSelectionOffset = function(offset) {
              setSelectionTextOffset(offset);
            };
            window.simplelimeReceiveSavedImage = receiveSavedImage;

            window.simplelimeCommand = simplelimeCommand;
            window.simplelimeTest = {
              currentMarkdown,
              fallbackDiagramSVG,
              fallbackMathHTML,
              insertImageMarkdown,
              receiveSavedImage,
              tableAction,
              editorHTML() {
                return editor.innerHTML;
              },
              lastRestoredCaretOffset() {
                return lastRestoredCaretOffset;
              },
              normalizePlainTextWithCaretAtEnd(value) {
                isSettingMarkdown = true;
                editor.innerText = String(value) + CARET_TOKEN;
                isSettingMarkdown = false;
                const markdown = htmlToMarkdown();
                lastPostedMarkdown = stripCaretToken(markdown);
                setMarkdown(markdown, { preserveCaretToken: true });
              },
              normalizeMarkdownIfNeeded,
              selectText(selector, start, end) {
                const element = document.querySelector(selector);
                if (!element) return false;

                const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
                const textNode = walker.nextNode();
                if (!textNode) return false;

                const safeStart = Math.max(0, Math.min(Number(start) || 0, textNode.textContent.length));
                const requestedEnd = end == null ? textNode.textContent.length : Number(end);
                const safeEnd = Math.max(safeStart, Math.min(requestedEnd, textNode.textContent.length));
                const range = document.createRange();
                range.setStart(textNode, safeStart);
                range.setEnd(textNode, safeEnd);

                focusEditor();
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
                return true;
              },
              selectionTextOffset,
              setCaretToEnd() {
                setSelectionTextOffset(Number.MAX_SAFE_INTEGER);
              },
              setSelectionTextOffset,
              setCaretInListItem(index, atEnd = true) {
                const item = Array.from(editor.querySelectorAll('li'))[Number(index) || 0];
                if (!item) return false;

                const range = document.createRange();
                range.selectNodeContents(item);
                range.collapse(Boolean(atEnd));
                focusEditor();
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
                return true;
              },
              dispatchKey(key, options = {}) {
                const event = new KeyboardEvent('keydown', {
                  key,
                  bubbles: true,
                  cancelable: true,
                  metaKey: Boolean(options.metaKey),
                  shiftKey: Boolean(options.shiftKey),
                  altKey: Boolean(options.altKey),
                  ctrlKey: Boolean(options.ctrlKey)
                });
                editor.dispatchEvent(event);
                return event.defaultPrevented;
              },
              setPlainText(value) {
                isSettingMarkdown = true;
                editor.innerText = value;
                lastPostedMarkdown = value;
                isSettingMarkdown = false;
              }
            };
            window.simplelimeSetFontSize = function(fontSize) {
              document.documentElement.style.setProperty('--editor-font-size', `${fontSize}px`);
            };
            window.simplelimeSetTypewriter = function(enabled) {
              document.body.classList.toggle('typewriter', Boolean(enabled));
            };

            setMarkdown(initialMarkdown);
            window.addEventListener('load', renderEnhancements);
            window.setTimeout(renderEnhancements, 250);
          </script>
        </body>
        </html>
        """#
    }

    private static func javaScriptLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
           let encoded = String(data: data, encoding: .utf8),
           encoded.count >= 2 {
            return String(encoded.dropFirst().dropLast())
        }

        return "\"\""
    }

    static func savePastedImage(dataURL: String, originalName: String, mimeType: String, baseURL: URL?) throws -> String {
        guard let baseURL, baseURL.isFileURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        let marker = ";base64,"
        guard let markerRange = dataURL.range(of: marker),
              let data = Data(base64Encoded: String(dataURL[markerRange.upperBound...])) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let assetsURL = baseURL
            .standardizedFileURL
            .appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        let originalURL = URL(fileURLWithPath: originalName)
        let sourceExtension = imageFileExtension(originalExtension: originalURL.pathExtension, mimeType: mimeType)
        let baseName = sanitizedImageBaseName(originalURL.deletingPathExtension().lastPathComponent)
        let fileURL = uniqueImageURL(directoryURL: assetsURL, baseName: baseName, fileExtension: sourceExtension)
        try data.write(to: fileURL, options: .atomic)

        return "assets/\(fileURL.lastPathComponent)"
    }

    private static func imageFileExtension(originalExtension: String, mimeType: String) -> String {
        let sanitized = originalExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        if !sanitized.isEmpty {
            return sanitized
        }

        switch mimeType.lowercased() {
        case "image/apng": return "apng"
        case "image/avif": return "avif"
        case "image/gif": return "gif"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/svg+xml": return "svg"
        case "image/webp": return "webp"
        default: return "png"
        }
    }

    private static func sanitizedImageBaseName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = value
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" {
                    result.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))

        return sanitized.isEmpty ? "image" : sanitized
    }

    private static func uniqueImageURL(directoryURL: URL, baseName: String, fileExtension: String) -> URL {
        var index = 0
        while true {
            let suffix = index == 0 ? "" : "-\(index)"
            let candidate = directoryURL.appendingPathComponent("\(baseName)\(suffix).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownWYSIWYGEditorView
        weak var webView: WKWebView?
        var lastAppliedMarkdown = ""
        var lastAppliedSelectionRanges: [TextRange] = []
        private var isLoaded = false
        private var pendingMarkdown: String?
        private var pendingSelectionRanges: [TextRange]?

        init(_ parent: MarkdownWYSIWYGEditorView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let pendingMarkdown {
                self.pendingMarkdown = nil
                applyExternalMarkdown(pendingMarkdown)
            }
            if let pendingSelectionRanges {
                self.pendingSelectionRanges = nil
                applySelectionIfNeeded(pendingSelectionRanges, force: true)
            }
            applyEditorOptions(fontSize: parent.fontSize, typewriterModeEnabled: parent.typewriterModeEnabled)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "simplelime",
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else {
                return
            }

            switch type {
            case "markdownChanged":
                guard let markdown = payload["markdown"] as? String else { return }
                lastAppliedMarkdown = markdown
                parent.text = markdown
                let selection = [TextRange(location: min(parent.selectionRanges.first?.location ?? 0, markdown.utf16.count), length: 0)]
                lastAppliedSelectionRanges = selection
                parent.selectionRanges = selection

            case "selectionChanged":
                let location: Int
                if let value = payload["location"] as? Int {
                    location = value
                } else if let value = payload["location"] as? NSNumber {
                    location = value.intValue
                } else {
                    return
                }
                let selection = [TextRange(location: min(max(0, location), parent.text.utf16.count), length: 0)]
                guard selection != lastAppliedSelectionRanges else { return }
                lastAppliedSelectionRanges = selection
                parent.selectionRanges = selection

            case "shortcut":
                guard let name = payload["name"] as? String else { return }
                handleShortcut(named: name)

            case "savePastedImage":
                savePastedImage(from: payload)

            default:
                break
            }
        }

        func applyExternalMarkdown(_ markdown: String) {
            lastAppliedMarkdown = markdown

            guard isLoaded else {
                pendingMarkdown = markdown
                return
            }

            let script = "window.simplelimeSetMarkdown(\(MarkdownWYSIWYGEditorView.javaScriptLiteral(markdown)));"
            webView?.evaluateJavaScript(script)
        }

        func applySelectionIfNeeded(_ selectionRanges: [TextRange], force: Bool = false) {
            guard isLoaded else {
                pendingSelectionRanges = selectionRanges
                return
            }
            guard force || selectionRanges != lastAppliedSelectionRanges else { return }

            let location = min(max(0, selectionRanges.first?.location ?? 0), parent.text.utf16.count)
            lastAppliedSelectionRanges = [TextRange(location: location, length: 0)]
            let script = "window.simplelimeSetSelectionOffset(\(location));"
            webView?.evaluateJavaScript(script)
        }

        func applyEditorOptions(fontSize: Double, typewriterModeEnabled: Bool) {
            guard isLoaded else { return }

            let safeFontSize = max(10, min(32, fontSize))
            let typewriter = typewriterModeEnabled ? "true" : "false"
            let script = """
            window.simplelimeSetFontSize(\(safeFontSize));
            window.simplelimeSetTypewriter(\(typewriter));
            """
            webView?.evaluateJavaScript(script)
        }

        func perform(_ command: EditorCommand) -> Bool {
            guard isLoaded else { return false }

            switch command {
            case .markdown(let command):
                let script = "window.simplelimeCommand(\(MarkdownWYSIWYGEditorView.javaScriptLiteral(command.rawValue)));"
                webView?.evaluateJavaScript(script)
                return true

            default:
                return false
            }
        }

        private func handleShortcut(named name: String) {
            switch name {
            case "showCommandPalette":
                parent.onShortcut(.showCommandPalette)
            case "openFolder":
                parent.onShortcut(.openFolder)
            case "showFind":
                parent.onShortcut(.showFind)
            case "showReplace":
                parent.onShortcut(.showReplace)
            case "showGlobalFind":
                parent.onShortcut(.showGlobalFind)
            case "findNext":
                parent.onShortcut(.findNext)
            case "findPrevious":
                parent.onShortcut(.findPrevious)
            case "toggleWrapLines":
                parent.onShortcut(.toggleWrapLines)
            case "showSourceMode":
                parent.onShortcut(.showSourceMode)
            case "showMarkdownPreviewMode":
                parent.onShortcut(.showMarkdownPreviewMode)
            case "showMarkdownWysiwygMode":
                parent.onShortcut(.showMarkdownWysiwygMode)
            case "toggleMarkdownPreview":
                parent.onShortcut(.toggleMarkdownPreview)
            case "toggleMarkdownOutline":
                parent.onShortcut(.toggleMarkdownOutline)
            case "toggleDocumentCatalog":
                parent.onShortcut(.toggleDocumentCatalog)
            case "toggleWysiwygMode":
                parent.onShortcut(.toggleWysiwygMode)
            case "toggleFocusMode":
                parent.onShortcut(.toggleFocusMode)
            case "toggleTypewriterMode":
                parent.onShortcut(.toggleTypewriterMode)
            case "toggleMiniMap":
                parent.onShortcut(.toggleMiniMap)
            default:
                break
            }
        }

        private func savePastedImage(from payload: [String: Any]) {
            guard let id = payload["id"] as? String,
                  let dataURL = payload["dataURL"] as? String else {
                return
            }

            let name = payload["name"] as? String ?? "image"
            let mimeType = payload["mimeType"] as? String ?? ""
            let alt = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent

            do {
                let relativePath = try MarkdownWYSIWYGEditorView.savePastedImage(
                    dataURL: dataURL,
                    originalName: name,
                    mimeType: mimeType,
                    baseURL: parent.baseURL
                )
                finishPastedImage(id: id, source: relativePath, alt: alt, error: nil)
            } catch {
                finishPastedImage(id: id, source: "", alt: alt, error: error.localizedDescription)
            }
        }

        private func finishPastedImage(id: String, source: String, alt: String, error: String?) {
            let script = """
            window.simplelimeReceiveSavedImage(
              \(MarkdownWYSIWYGEditorView.javaScriptLiteral(id)),
              \(MarkdownWYSIWYGEditorView.javaScriptLiteral(source)),
              \(MarkdownWYSIWYGEditorView.javaScriptLiteral(alt)),
              \(MarkdownWYSIWYGEditorView.javaScriptLiteral(error ?? ""))
            );
            """
            webView?.evaluateJavaScript(script)
        }
    }
}

private final class MarkdownWYSIWYGWebView: WKWebView {
    var shortcutHandler: ((EditorShortcut) -> Bool)?

    @IBAction override func performTextFinderAction(_ sender: Any?) {
        let title = (sender as? NSMenuItem)?.title.lowercased() ?? ""
        if title.contains("previous") {
            _ = shortcutHandler?(.findPrevious)
        } else if title.contains("next") {
            _ = shortcutHandler?(.findNext)
        } else {
            _ = shortcutHandler?(.showFind)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control) else {
            return super.performKeyEquivalent(with: event)
        }

        let shortcut: EditorShortcut?
        switch event.keyCode {
        case 18 where flags.contains(.option):
            shortcut = .showSourceMode
        case 19 where flags.contains(.option):
            shortcut = .showMarkdownPreviewMode
        case 20 where flags.contains(.option):
            shortcut = .showMarkdownWysiwygMode
        case 21 where flags.contains(.option):
            shortcut = .toggleMiniMap
        case 35 where flags.contains(.shift):
            shortcut = .showCommandPalette
        case 31 where flags.contains(.shift):
            shortcut = .openFolder
        case 35 where flags.contains(.option):
            shortcut = .toggleMarkdownPreview
        case 31 where flags.contains(.option):
            shortcut = .toggleMarkdownOutline
        case 14 where flags.contains(.option):
            shortcut = .toggleWysiwygMode
        case 3 where flags.contains(.option):
            shortcut = .toggleFocusMode
        case 17 where flags.contains(.option) && !flags.contains(.shift):
            shortcut = .toggleTypewriterMode
        case 3 where flags.contains(.shift):
            shortcut = .showGlobalFind
        case 3:
            shortcut = .showFind
        case 15:
            shortcut = .showReplace
        case 2 where flags.contains(.option):
            shortcut = .toggleDocumentCatalog
        case 2:
            shortcut = .addNextOccurrence
        case 11:
            shortcut = .markdown(.bold)
        case 34:
            shortcut = .markdown(.italic)
        case 37 where flags.contains(.option):
            shortcut = .selectAllMatches
        case 5 where flags.contains(.option):
            shortcut = flags.contains(.shift) ? .addPreviousOccurrence : .addNextOccurrence
        case 5 where flags.contains(.shift):
            shortcut = .findPrevious
        case 5:
            shortcut = .findNext
        case 6 where flags.contains(.option):
            shortcut = .toggleWrapLines
        case 24, 69:
            shortcut = .increaseFontSize
        case 27, 78:
            shortcut = .decreaseFontSize
        default:
            shortcut = nil
        }

        if let shortcut, shortcutHandler?(shortcut) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 48, flags.contains(.control), !flags.contains(.command), !flags.contains(.option) {
            let shortcut: EditorShortcut = flags.contains(.shift) ? .previousTab : .nextTab
            if shortcutHandler?(shortcut) == true {
                return
            }
        }

        if event.keyCode == 53, shortcutHandler?(.escape) == true {
            return
        }

        super.keyDown(with: event)
    }
}
