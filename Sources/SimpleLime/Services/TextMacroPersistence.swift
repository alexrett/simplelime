import Foundation

struct StoredTextMacros: Codable {
    var macros: [TextMacro]
    var actionMacros: [ActionMacro]
    var pinnedMacros: [PinnedMacroReference]

    private enum CodingKeys: String, CodingKey {
        case macros
        case actionMacros
        case pinnedMacros
    }

    init(macros: [TextMacro], actionMacros: [ActionMacro] = [], pinnedMacros: [PinnedMacroReference] = []) {
        self.macros = macros
        self.actionMacros = actionMacros
        self.pinnedMacros = pinnedMacros
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        macros = try container.decodeIfPresent([TextMacro].self, forKey: .macros) ?? []
        actionMacros = try container.decodeIfPresent([ActionMacro].self, forKey: .actionMacros) ?? []
        pinnedMacros = try container.decodeIfPresent([PinnedMacroReference].self, forKey: .pinnedMacros) ?? []
    }
}

final class TextMacroPersistence {
    private let fileManager: FileManager
    private let macrosURL: URL

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager

        macrosURL = Self.defaultMacrosURL(fileManager: fileManager, defaults: defaults)
    }

    init(fileManager: FileManager = .default, macrosURL: URL) {
        self.fileManager = fileManager
        self.macrosURL = macrosURL
    }

    func load() -> [TextMacro] {
        guard let data = try? Data(contentsOf: macrosURL),
              let stored = try? JSONDecoder.textMacroDecoder.decode(StoredTextMacros.self, from: data) else {
            return []
        }

        return stored.macros.filter { !$0.isBuiltIn }
    }

    func loadActionMacros() -> [ActionMacro] {
        guard let data = try? Data(contentsOf: macrosURL),
              let stored = try? JSONDecoder.textMacroDecoder.decode(StoredTextMacros.self, from: data) else {
            return []
        }

        return stored.actionMacros.filter { !$0.steps.isEmpty }
    }

    func loadPinnedMacros() -> [PinnedMacroReference] {
        guard let data = try? Data(contentsOf: macrosURL),
              let stored = try? JSONDecoder.textMacroDecoder.decode(StoredTextMacros.self, from: data) else {
            return []
        }

        var seen = Set<String>()
        return stored.pinnedMacros.filter { reference in
            seen.insert(reference.id).inserted
        }
    }

    func save(_ macros: [TextMacro]) throws {
        try save(textMacros: macros, actionMacros: loadActionMacros(), pinnedMacros: loadPinnedMacros())
    }

    static func defaultMacrosURL(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> URL {
        AppDataStorage.currentRootURL(fileManager: fileManager, defaults: defaults)
            .appendingPathComponent("macros.json", isDirectory: false)
    }

    func save(
        textMacros: [TextMacro],
        actionMacros: [ActionMacro],
        pinnedMacros: [PinnedMacroReference] = []
    ) throws {
        try fileManager.createDirectory(at: macrosURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let customTextMacros = textMacros.filter { !$0.isBuiltIn }
        let customActionMacros = actionMacros.filter { !$0.steps.isEmpty }
        let validTextMacroIDs = Set(TextMacro.builtIns.map(\.id) + customTextMacros.map(\.id))
        let validActionMacroIDs = Set(customActionMacros.map(\.id))
        var seenPinnedIDs = Set<String>()
        let validPinnedMacros = pinnedMacros.filter { reference in
            let isKnown: Bool
            switch reference.kind {
            case .text:
                isKnown = validTextMacroIDs.contains(reference.macroID)
            case .action:
                isKnown = validActionMacroIDs.contains(reference.macroID)
            }
            return isKnown && seenPinnedIDs.insert(reference.id).inserted
        }
        let data = try JSONEncoder.textMacroEncoder.encode(
            StoredTextMacros(
                macros: customTextMacros,
                actionMacros: customActionMacros,
                pinnedMacros: validPinnedMacros
            )
        )
        try data.write(to: macrosURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var textMacroEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var textMacroDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
