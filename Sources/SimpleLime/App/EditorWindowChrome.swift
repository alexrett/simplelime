import AppKit
import SwiftUI

enum EditorWindowChrome {
    static let editorWindowIdentifier = NSUserInterfaceItemIdentifier("com.whitehappypony.simplelime.editor-window")
    static let trafficLightLayerZPosition: CGFloat = 10_000

    static func isEditorWindow(_ window: NSWindow) -> Bool {
        if window.identifier == editorWindowIdentifier {
            return true
        }

        if window.title == "SimpleLime" || window.title.hasPrefix("SimpleLime - ") {
            return true
        }

        let accessibilityLabel = window.accessibilityLabel() ?? ""
        return accessibilityLabel == "SimpleLime" || accessibilityLabel.hasPrefix("SimpleLime - ")
    }

    static func configure(_ window: NSWindow, logicalTitle: String? = nil) {
        let resolvedLogicalTitle = logicalTitle
            ?? (!window.title.isEmpty ? window.title : nil)
            ?? window.accessibilityLabel()

        if let resolvedLogicalTitle, !resolvedLogicalTitle.isEmpty {
            window.setAccessibilityLabel(resolvedLogicalTitle)
        }

        window.identifier = editorWindowIdentifier
        window.tabbingMode = .disallowed
        if !window.title.isEmpty {
            window.title = ""
        }
        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        window.styleMask.insert(.fullSizeContentView)
        if window.isMovableByWindowBackground {
            window.isMovableByWindowBackground = false
        }
        window.animationBehavior = .none
        restoreStandardWindowButtons(in: window)
    }

    private static func restoreStandardWindowButtons(in window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen) else { return }

        [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ].enumerated().forEach { index, buttonType in
            guard let button = window.standardWindowButton(buttonType) else { return }
            button.isHidden = false
            button.alphaValue = 1
            button.superview?.isHidden = false
            button.superview?.alphaValue = 1
            button.superview?.wantsLayer = true
            button.superview?.layer?.zPosition = trafficLightLayerZPosition
            button.wantsLayer = true
            button.layer?.zPosition = trafficLightLayerZPosition + CGFloat(index + 1)
        }
    }
}
