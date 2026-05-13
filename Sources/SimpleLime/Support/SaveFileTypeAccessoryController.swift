import AppKit

final class SaveFileTypeAccessoryController: NSObject {
    typealias AISuggestionHandler = (_ fileType: SaveFileType, _ completion: @escaping (Result<String, Error>) -> Void) -> Void

    let view: NSView

    private weak var panel: NSSavePanel?
    private let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let aiButton = NSButton(title: "AI Name", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private var lastFileName: String
    private let aiSuggestionHandler: AISuggestionHandler?

    var selectedFileType: SaveFileType {
        let index = popUp.indexOfSelectedItem
        guard SaveFileType.allCases.indices.contains(index) else {
            return .plain
        }
        return SaveFileType.allCases[index]
    }

    init(
        panel: NSSavePanel,
        initialFileName: String,
        initialType: SaveFileType,
        aiSuggestionHandler: AISuggestionHandler? = nil
    ) {
        self.panel = panel
        self.lastFileName = initialFileName
        self.aiSuggestionHandler = aiSuggestionHandler

        let label = NSTextField(labelWithString: "File Type")
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.lineBreakMode = .byTruncatingTail

        for fileType in SaveFileType.allCases {
            popUp.addItem(withTitle: fileType.displayName)
        }
        popUp.selectItem(at: SaveFileType.allCases.firstIndex(of: initialType) ?? 0)

        aiButton.bezelStyle = .rounded
        aiButton.isEnabled = aiSuggestionHandler != nil

        let row = NSStackView(views: [label, popUp, aiButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        popUp.widthAnchor.constraint(equalToConstant: 190).isActive = true
        aiButton.widthAnchor.constraint(equalToConstant: 82).isActive = true

        let stack = NSStackView(views: [row, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.frame = NSRect(x: 0, y: 0, width: 368, height: 48)
        view = stack

        super.init()

        popUp.target = self
        popUp.action = #selector(fileTypeChanged)
        aiButton.target = self
        aiButton.action = #selector(suggestAIName)
        applySelectedType()
    }

    @objc private func fileTypeChanged() {
        applySelectedType()
    }

    private func applySelectedType() {
        guard let panel else { return }

        let current = panel.nameFieldStringValue.isEmpty ? lastFileName : panel.nameFieldStringValue
        let updated = EditorStore.fileName(current, changingExtensionTo: selectedFileType.fileExtension)
        panel.nameFieldStringValue = updated
        panel.allowedContentTypes = [selectedFileType.contentType]
        lastFileName = updated
    }

    @objc private func suggestAIName() {
        guard let aiSuggestionHandler else { return }

        aiButton.isEnabled = false
        statusLabel.stringValue = "Asking AI for a file name..."
        aiSuggestionHandler(selectedFileType) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.aiButton.isEnabled = true
                switch result {
                case .success(let fileName):
                    let updated = EditorStore.fileName(fileName, changingExtensionTo: self.selectedFileType.fileExtension)
                    self.panel?.nameFieldStringValue = updated
                    self.lastFileName = updated
                    self.statusLabel.stringValue = "AI name applied."
                case .failure(let error):
                    self.statusLabel.stringValue = "AI name unavailable: \(error.localizedDescription)"
                    NSSound.beep()
                }
            }
        }
    }
}
