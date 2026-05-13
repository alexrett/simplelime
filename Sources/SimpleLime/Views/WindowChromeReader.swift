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
        reader?.configureWindow()
        reader?.updateState()
    }

    final class ReaderView: NSView {
        weak var state: WindowChromeState?
        var onBecomeMain: () -> Void = {}
        private var observers: [NSObjectProtocol] = []
        private weak var observedTitleWindow: NSWindow?
        private var titleObservation: NSKeyValueObservation?

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
            publishFullScreenState(isFullScreen)
        }

        func configureWindow() {
            guard let window else { return }
            EditorWindowChrome.configure(window)
            installTitleObserver(for: window)
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
                    self?.configureWindow()
                    self?.publishBecomeMain()
                }
            )
            installTitleObserver(for: window)
        }

        private func installTitleObserver(for window: NSWindow) {
            guard observedTitleWindow !== window else { return }
            titleObservation?.invalidate()
            observedTitleWindow = window
            titleObservation = window.observe(\.title, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.configureWindow()
                }
            }
        }

        private func publishFullScreenState(_ isFullScreen: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state?.isFullScreen != isFullScreen else { return }
                self.state?.isFullScreen = isFullScreen
            }
        }

        private func publishBecomeMain() {
            DispatchQueue.main.async { [weak self] in
                self?.onBecomeMain()
            }
        }
    }
}
