import Foundation

enum AIAgentProvider: String, CaseIterable, Codable, Identifiable {
    case copilot
    case codex
    case openAICompatible
    case anthropic
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copilot: "Copilot"
        case .codex: "Codex"
        case .openAICompatible: "HTTP LLM"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        }
    }

    var usesACP: Bool {
        switch self {
        case .copilot, .codex:
            true
        case .openAICompatible, .anthropic, .gemini:
            false
        }
    }

    var httpProvider: HTTPAIProvider? {
        switch self {
        case .copilot, .codex:
            nil
        case .openAICompatible:
            .openAICompatible
        case .anthropic:
            .anthropic
        case .gemini:
            .gemini
        }
    }

    var defaultExecutable: String {
        switch self {
        case .copilot:
            if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/copilot") {
                return "/opt/homebrew/bin/copilot"
            }
            return "copilot"
        case .codex:
            if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/codex-acp") {
                return "/opt/homebrew/bin/codex-acp"
            }
            return "codex-acp"
        case .openAICompatible, .anthropic, .gemini:
            return ""
        }
    }

    var defaultArguments: String {
        switch self {
        case .copilot: "--acp --stdio"
        case .codex: ""
        case .openAICompatible, .anthropic, .gemini: ""
        }
    }

    var settingsExecutableKey: String {
        "ai.\(rawValue).executable"
    }

    var settingsArgumentsKey: String {
        "ai.\(rawValue).arguments"
    }
}

enum AIChatRole: String, Codable {
    case user
    case assistant
    case system
}

struct AIChatMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var role: AIChatRole
    var text: String
    var createdAt: Date

    static func user(_ text: String) -> AIChatMessage {
        AIChatMessage(id: UUID(), role: .user, text: text, createdAt: Date())
    }

    static func assistant(_ text: String) -> AIChatMessage {
        AIChatMessage(id: UUID(), role: .assistant, text: text, createdAt: Date())
    }

    static func system(_ text: String) -> AIChatMessage {
        AIChatMessage(id: UUID(), role: .system, text: text, createdAt: Date())
    }
}

struct AIChatSession: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var provider: AIAgentProvider
    var agentSessionID: String?
    var messages: [AIChatMessage]
    var createdAt: Date
    var updatedAt: Date

    static func new(provider: AIAgentProvider, index: Int) -> AIChatSession {
        let now = Date()
        return AIChatSession(
            id: UUID(),
            title: "\(provider.displayName) \(index)",
            provider: provider,
            agentSessionID: nil,
            messages: [],
            createdAt: now,
            updatedAt: now
        )
    }
}
