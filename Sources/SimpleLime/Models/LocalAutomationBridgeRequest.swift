import Foundation

indirect enum LocalAutomationJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: LocalAutomationJSONValue])
    case array([LocalAutomationJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([LocalAutomationJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: LocalAutomationJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct LocalAutomationJSONRPCRequest: Codable, Equatable {
    var jsonrpc: String?
    var method: String
    var params: LocalAutomationJSONValue?
    var id: LocalAutomationJSONValue?
}

struct LocalAutomationJSONRPCErrorBody: Codable, Equatable {
    var code: Int
    var message: String
}

struct LocalAutomationJSONRPCSuccessResponse: Codable, Equatable {
    var jsonrpc = "2.0"
    var id: LocalAutomationJSONValue
    var result: LocalAutomationBridgeResponse
}

struct LocalAutomationJSONRPCErrorResponse: Codable, Equatable {
    var jsonrpc = "2.0"
    var id: LocalAutomationJSONValue
    var error: LocalAutomationJSONRPCErrorBody
}

struct LocalAutomationSocketRequest: Codable, Equatable {
    enum Kind: String, Codable {
        case health
        case scribe
        case command
    }

    var type: Kind
    var payload: LocalAutomationJSONValue?
}

struct LocalAutomationScribeRequest: Codable, Equatable {
    enum Mode: String, Codable {
        case append
        case newBuffer
    }

    var title: String?
    var text: String
    var speaker: String?
    var timestamp: String?
    var language: EditorLanguage?
    var mode: Mode?

    var normalizedTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Scribe Transcript" : trimmed
    }

    var formattedTranscriptLine: String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSpeaker = speaker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedTimestamp = timestamp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedSpeaker.isEmpty, !trimmedTimestamp.isEmpty {
            return "[\(trimmedTimestamp)] **\(trimmedSpeaker)**: \(body)"
        }

        if !trimmedSpeaker.isEmpty {
            return "**\(trimmedSpeaker)**: \(body)"
        }

        if !trimmedTimestamp.isEmpty {
            return "[\(trimmedTimestamp)] \(body)"
        }

        return body
    }
}

enum LocalAutomationCommand: String, Codable, Equatable {
    case newScratch
    case save
    case close
    case forceClose
    case forceClosePath
    case toggleCompanion
    case runCompanionScan
    case toggleTasks
    case toggleTerminal
    case toggleMacros
    case toggleStats
    case toggleActivityWatch
    case toggleScribe
    case showCommandPalette
    case insertText
    case replaceLargeFileLine
    case insertLargeFileLine
    case deleteLargeFileLine
    case replaceLargeFileLines
    case insertLargeFileLines
    case deleteLargeFileLines
}

struct LocalAutomationCommandRequest: Codable, Equatable {
    var command: LocalAutomationCommand
    var text: String?
    var lineNumber: Int? = nil
    var endLineNumber: Int? = nil
}

struct LocalAutomationBridgeResponse: Codable, Equatable {
    var ok: Bool
    var message: String
    var bufferTitle: String?
}
