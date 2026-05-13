import Foundation

struct PinnedMacroReference: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text
        case action
    }

    var kind: Kind
    var macroID: String

    var id: String {
        "\(kind.rawValue):\(macroID)"
    }

    static func text(_ id: String) -> PinnedMacroReference {
        PinnedMacroReference(kind: .text, macroID: id)
    }

    static func action(_ id: String) -> PinnedMacroReference {
        PinnedMacroReference(kind: .action, macroID: id)
    }
}

struct PinnedMacroButton: Identifiable, Equatable {
    var reference: PinnedMacroReference
    var title: String
    var systemName: String
    var help: String

    var id: String {
        reference.id
    }
}
