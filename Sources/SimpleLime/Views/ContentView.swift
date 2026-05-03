import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: EditorStore
    @StateObject private var chromeState = WindowChromeState()
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(store: store, isFullScreen: chromeState.isFullScreen)
                .zIndex(20)

            if store.findPanelMode != .hidden {
                SearchPanelView(store: store)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }

            if let buffer = store.selectedBuffer {
                EditorWorkspaceView(store: store, buffer: buffer)
                    .id(buffer.id)
                    .clipped()
                    .zIndex(0)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Buffer")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(0)
            }
        }
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .background(WindowChromeReader(state: chromeState).frame(width: 0, height: 0))
        .ignoresSafeArea(.container, edges: ignoredSafeAreaEdges)
        .alert(
            "SimpleLime",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { isPresented in
                    if !isPresented {
                        store.lastError = nil
                    }
                }
            )
        ) {
            Button("OK") {
                store.lastError = nil
            }
        } message: {
            Text(store.lastError ?? "")
        }
        .alert(
            "Close Tab?",
            isPresented: Binding(
                get: { store.pendingCloseBuffer != nil },
                set: { isPresented in
                    if !isPresented {
                        store.cancelPendingClose()
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                store.cancelPendingClose()
            }
            Button("Close", role: .destructive) {
                store.confirmPendingClose()
            }
        } message: {
            Text("“\(store.pendingCloseBuffer?.displayTitle ?? "Untitled")” contains text. Closing it removes this tab from the restored session.")
        }
    }

    private var ignoredSafeAreaEdges: Edge.Set {
        chromeState.isFullScreen ? [] : .top
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event: event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handle(event: NSEvent) -> NSEvent? {
        if event.keyCode == 53, store.findPanelMode != .hidden {
            store.hideFindPanel()
            return nil
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 48, flags.contains(.control), !flags.contains(.command), !flags.contains(.option) {
            if flags.contains(.shift) {
                store.selectPreviousTab()
            } else {
                store.selectNextTab()
            }
            return nil
        }

        guard flags.contains(.command),
              !flags.contains(.control) else {
            return event
        }

        switch event.keyCode {
        case 34 where flags.contains(.shift):
            store.toggleAIPanel()
            return nil
        case 3 where flags.contains(.shift):
            store.showGlobalFind()
            return nil
        case 3:
            store.showFind()
            return nil
        case 15:
            store.showReplace()
            return nil
        case 2:
            store.performTextTransform(.duplicateLine)
            return nil
        case 37 where flags.contains(.shift):
            store.selectAllMatches()
            return nil
        case 32 where flags.contains(.option) && flags.contains(.shift):
            store.performTextTransform(.uniqueLines)
            return nil
        case 32 where flags.contains(.shift):
            store.performTextTransform(.uppercase)
            return nil
        case 32 where flags.contains(.option):
            store.performTextTransform(.lowercase)
            return nil
        case 17 where flags.contains(.option):
            store.performTextTransform(.titlecase)
            return nil
        case 1 where flags.contains(.option):
            store.performTextTransform(.sortLines)
            return nil
        case 13 where flags.contains(.option):
            store.performTextTransform(.trimTrailingWhitespace)
            return nil
        case 38:
            store.performTextTransform(.joinLines)
            return nil
        case 24, 69:
            store.increaseFontSize()
            return nil
        case 27, 78:
            store.decreaseFontSize()
            return nil
        default:
            return event
        }
    }
}
