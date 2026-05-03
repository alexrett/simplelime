import AppKit

enum AppAbout {
    static let version = "0.1.0"
    static let build = "1"
    static let description = "Scratch-first text editor for temporary notes, Markdown, and code."

    @MainActor
    static func show() {
        let credits = NSAttributedString(
            string: description,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "SimpleLime",
                .applicationVersion: version,
                .version: build,
                .credits: credits
            ]
        )
    }
}
