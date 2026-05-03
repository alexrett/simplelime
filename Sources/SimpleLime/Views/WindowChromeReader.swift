import AppKit
import SwiftUI

@MainActor
final class WindowChromeState: ObservableObject {
    @Published var isFullScreen = false
}

struct WindowChromeReader: NSViewRepresentable {
    @ObservedObject var state: WindowChromeState

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ReaderView)?.state = state
        (nsView as? ReaderView)?.updateState()
    }

    final class ReaderView: NSView {
        weak var state: WindowChromeState?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
            installObservers()
            updateState()
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func updateState() {
            guard let window else { return }
            let isFullScreen = window.styleMask.contains(.fullScreen)
            if state?.isFullScreen != isFullScreen {
                state?.isFullScreen = isFullScreen
            }
        }

        private func configureWindow() {
            guard let window else { return }
            window.tabbingMode = .disallowed
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }

        private func installObservers() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()

            guard let window else { return }
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.willEnterFullScreenNotification,
                NSWindow.willExitFullScreenNotification
            ]

            observers = names.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.updateState()
                }
            }
        }
    }
}
