import AppKit
import SwiftUI
import SwiftTerm

struct TerminalPanelView: View {
    @ObservedObject var store: EditorStore

    private var selectedSession: TerminalSession? {
        store.selectedTerminalSession
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.terminalSessions.isEmpty {
                emptyState
            } else {
                terminalStack
            }
        }
        .frame(minHeight: 120, idealHeight: 240, maxHeight: 420)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var terminalStack: some View {
        ZStack {
            ForEach(store.terminalSessions) { session in
                let isActive = session.id == store.selectedTerminalSessionID
                TerminalEmulatorView(session: session, store: store, isActive: isActive)
                    .id(session.id)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .accessibilityHidden(!isActive)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.terminalSessions) { session in
                        terminalTab(session)
                    }
                }
                .padding(.vertical, 5)
            }

            if let selectedSession {
                Text(selectedSession.workingDirectoryPath)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 260, alignment: .trailing)
                    .help(selectedSession.workingDirectoryPath)
            }

            Button {
                store.createTerminalSession()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("New terminal")

            if let selectedSession {
                Button {
                    store.runTerminalDiagnostics(selectedSession.id)
                } label: {
                    Image(systemName: "waveform.path.ecg")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(!selectedSession.isRunning)
                .help("Run terminal diagnostics")

                Button {
                    store.interruptTerminalSession(selectedSession.id)
                } label: {
                    Image(systemName: "xmark.circle")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(!selectedSession.isRunning)
                .help("Interrupt command")

                Button {
                    store.resetTerminalSession(selectedSession.id)
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(!selectedSession.isRunning)
                .help("Reset terminal state")

                Button {
                    store.restartTerminalSession(selectedSession.id)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Restart terminal process")

                Button {
                    store.clearTerminalOutput(selectedSession.id)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Clear terminal")
            }

            Button {
                store.hideTerminalPanel()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Hide terminal")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func terminalTab(_ session: TerminalSession) -> some View {
        HStack(spacing: 4) {
            Button {
                store.selectTerminalSession(session.id)
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(session.isRunning ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(session.title)
                        .lineLimit(1)
                }
                .font(.caption)
                .padding(.leading, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            Button {
                store.closeTerminalSession(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Close \(session.title)")
        }
        .padding(.trailing, 4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(store.selectedTerminalSessionID == session.id
                    ? Color.accentColor.opacity(0.17)
                    : Color(nsColor: .controlBackgroundColor)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No terminal")
                .font(.headline)
            Button {
                store.createTerminalSession()
            } label: {
                Label("New Terminal", systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.secondary)
    }
}

private struct TerminalEmulatorView: NSViewRepresentable {
    let session: TerminalSession
    let store: EditorStore
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sessionID: session.id,
            store: store,
            clearGeneration: session.clearGeneration,
            isActive: isActive
        )
    }

    func makeNSView(context: Context) -> TerminalView {
        let terminal = TerminalView(
            frame: .zero,
            font: .monospacedSystemFont(ofSize: 12, weight: .regular)
        )
        terminal.terminalDelegate = context.coordinator
        terminal.nativeForegroundColor = .textColor
        terminal.nativeBackgroundColor = .textBackgroundColor
        terminal.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        terminal.caretColor = .controlAccentColor
        terminal.getTerminal().setCursorStyle(.steadyBlock)
        do {
            try terminal.setUseMetal(false)
        } catch {
            // The CoreText renderer is enough here; Metal is only an optimization.
        }
        context.coordinator.attach(to: terminal)
        DispatchQueue.main.async {
            guard isActive else { return }
            terminal.window?.makeFirstResponder(terminal)
        }
        return terminal
    }

    func updateNSView(_ terminal: TerminalView, context: Context) {
        context.coordinator.update(session: session, terminal: terminal, isActive: isActive)
    }

    static func dismantleNSView(_ terminal: TerminalView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        private let sessionID: UUID
        private weak var store: EditorStore?
        private var outputObserverID: UUID?
        private var clearGeneration: Int
        private var isActive: Bool
        private weak var terminal: TerminalView?
        private var lastReportedSize: (columns: Int, rows: Int)?
        private let outputFeedPump = TerminalOutputFeedPump()

        init(sessionID: UUID, store: EditorStore, clearGeneration: Int, isActive: Bool) {
            self.sessionID = sessionID
            self.store = store
            self.clearGeneration = clearGeneration
            self.isActive = isActive
        }

        @MainActor
        func attach(to terminal: TerminalView) {
            self.terminal = terminal
            outputFeedPump.attach(to: terminal)
            outputObserverID = store?.registerTerminalOutputObserver(for: sessionID) { [weak self] output in
                self?.outputFeedPump.enqueue(output)
            }
            syncTerminalSize(terminal)
        }

        @MainActor
        func detach() {
            if let outputObserverID {
                store?.unregisterTerminalOutputObserver(outputObserverID, for: sessionID)
            }
            outputObserverID = nil
            outputFeedPump.detach()
            terminal = nil
        }

        func update(session: TerminalSession, terminal: TerminalView, isActive nextIsActive: Bool) {
            if clearGeneration != session.clearGeneration {
                clearGeneration = session.clearGeneration
                outputFeedPump.reset()
                terminal.getTerminal().resetToInitialState()
                terminal.needsDisplay = true
            }
            let becameActive = !isActive && nextIsActive
            isActive = nextIsActive
            if becameActive {
                DispatchQueue.main.async { [weak terminal] in
                    terminal?.window?.makeFirstResponder(terminal)
                }
            }
            syncTerminalSize(terminal)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            reportTerminalSize(columns: newCols, rows: newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {
            Task { @MainActor [weak store, sessionID, title] in
                store?.updateTerminalSessionTitle(sessionID, title: title)
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            Task { @MainActor [weak store, sessionID, directory] in
                store?.updateTerminalSessionWorkingDirectory(sessionID, directory: directory)
            }
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let input = Array(data)
            Task { @MainActor [weak store, sessionID] in
                store?.sendInputToTerminal(sessionID, data: input[...])
            }
        }

        func scrolled(source: TerminalView, position: Double) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link) else { return }
            NSWorkspace.shared.open(url)
        }

        func bell(source: TerminalView) {
            NSSound.beep()
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            guard let text = String(data: content, encoding: .utf8) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        func clipboardRead(source: TerminalView) -> Data? {
            NSPasteboard.general.string(forType: .string)?.data(using: .utf8)
        }

        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

        private func syncTerminalSize(_ terminal: TerminalView) {
            let dimensions = terminal.getTerminal().getDims()
            reportTerminalSize(columns: dimensions.cols, rows: dimensions.rows)
        }

        private func reportTerminalSize(columns: Int, rows: Int) {
            guard columns > 0, rows > 0 else { return }
            guard lastReportedSize?.columns != columns || lastReportedSize?.rows != rows else { return }
            lastReportedSize = (columns, rows)
            Task { @MainActor [weak store, sessionID] in
                store?.resizeTerminalSession(sessionID, columns: columns, rows: rows)
            }
        }
    }
}

private final class TerminalOutputFeedPump {
    private weak var terminal: TerminalView?
    private var pendingOutput: [UInt8] = []
    private var isFlushScheduled = false
    private let maxBytesPerFlush = 64 * 1024

    func attach(to terminal: TerminalView) {
        self.terminal = terminal
    }

    func detach() {
        terminal = nil
        reset()
    }

    func reset() {
        pendingOutput.removeAll(keepingCapacity: true)
        isFlushScheduled = false
    }

    func enqueue(_ output: [UInt8]) {
        guard !output.isEmpty else { return }
        pendingOutput.append(contentsOf: output)
        scheduleFlushIfNeeded()
    }

    private func scheduleFlushIfNeeded() {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        isFlushScheduled = false
        guard let terminal else {
            pendingOutput.removeAll(keepingCapacity: true)
            return
        }
        guard !pendingOutput.isEmpty else { return }

        let batch: [UInt8]
        if pendingOutput.count > maxBytesPerFlush {
            batch = Array(pendingOutput.prefix(maxBytesPerFlush))
            pendingOutput.removeFirst(batch.count)
        } else {
            batch = pendingOutput
            pendingOutput.removeAll(keepingCapacity: true)
        }

        terminal.feed(byteArray: batch[...])

        if !pendingOutput.isEmpty {
            scheduleFlushIfNeeded()
        }
    }
}
