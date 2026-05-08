import AppKit
import SwiftUI

@MainActor
final class WindowChromeState: ObservableObject {
    @Published var isFullScreen = false
}

struct WindowChromeReader: NSViewRepresentable {
    @ObservedObject var state: WindowChromeState
    var onBecomeMain: () -> Void = {}

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.state = state
        view.onBecomeMain = onBecomeMain
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let reader = nsView as? ReaderView
        reader?.state = state
        reader?.onBecomeMain = onBecomeMain
        reader?.updateState()
    }

    final class ReaderView: NSView {
        weak var state: WindowChromeState?
        var onBecomeMain: () -> Void = {}
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
            window.isMovableByWindowBackground = false
            window.animationBehavior = .none
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

            observers.append(
                center.addObserver(forName: NSWindow.didBecomeMainNotification, object: window, queue: .main) { [weak self] _ in
                    self?.onBecomeMain()
                }
            )
        }
    }
}
