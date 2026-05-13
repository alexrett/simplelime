import Foundation

enum HTTPAIProvider: String, CaseIterable, Identifiable {
    case openAICompatible
    case anthropic
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        }
    }

    var defaultBaseURLString: String {
        switch self {
        case .openAICompatible: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAICompatible: "gpt-4.1-mini"
        case .anthropic: "claude-sonnet-4-5"
        case .gemini: "gemini-2.5-flash"
        }
    }
}

struct HTTPAIConfiguration: Equatable {
    static let providerDefaultsKey = "ai.http.provider"
    static let baseURLDefaultsKey = "ai.http.baseURL"
    static let apiKeyDefaultsKey = "ai.http.apiKey"
    static let modelDefaultsKey = "ai.http.model"
    static let temperatureDefaultsKey = "ai.http.temperature"

    static let defaultProvider = HTTPAIProvider.openAICompatible
    static let defaultBaseURLString = defaultProvider.defaultBaseURLString
    static let defaultModel = defaultProvider.defaultModel
    static let defaultTemperature = 0.2

    var provider: HTTPAIProvider
    var baseURL: URL
    var apiKey: String
    var model: String
    var temperature: Double

    init(
        provider: HTTPAIProvider = Self.defaultProvider,
        baseURLString: String = Self.defaultBaseURLString,
        apiKey: String = "",
        model: String = Self.defaultModel,
        temperature: Double = Self.defaultTemperature
    ) throws {
        let trimmedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedBaseURL), url.scheme != nil, url.host != nil else {
            throw HTTPAIConfigurationError.invalidBaseURL
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw HTTPAIConfigurationError.missingModel
        }

        self.provider = provider
        self.baseURL = url
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmedModel
        self.temperature = min(max(temperature, 0), 2)
    }

    static func current(defaults: UserDefaults = .standard) throws -> HTTPAIConfiguration {
        let provider = HTTPAIProvider(rawValue: defaults.string(forKey: providerDefaultsKey) ?? "") ?? defaultProvider
        return try current(provider: provider, defaults: defaults)
    }

    static func current(provider: HTTPAIProvider, defaults: UserDefaults = .standard) throws -> HTTPAIConfiguration {
        try HTTPAIConfiguration(
            provider: provider,
            baseURLString: defaults.string(forKey: baseURLDefaultsKey(for: provider)) ?? provider.defaultBaseURLString,
            apiKey: defaults.string(forKey: apiKeyDefaultsKey(for: provider)) ?? "",
            model: defaults.string(forKey: modelDefaultsKey(for: provider)) ?? provider.defaultModel,
            temperature: defaults.object(forKey: temperatureDefaultsKey(for: provider)) as? Double ?? defaultTemperature
        )
    }

    static func baseURLDefaultsKey(for provider: HTTPAIProvider) -> String {
        provider == .openAICompatible ? baseURLDefaultsKey : "ai.http.\(provider.rawValue).baseURL"
    }

    static func apiKeyDefaultsKey(for provider: HTTPAIProvider) -> String {
        provider == .openAICompatible ? apiKeyDefaultsKey : "ai.http.\(provider.rawValue).apiKey"
    }

    static func modelDefaultsKey(for provider: HTTPAIProvider) -> String {
        provider == .openAICompatible ? modelDefaultsKey : "ai.http.\(provider.rawValue).model"
    }

    static func temperatureDefaultsKey(for provider: HTTPAIProvider) -> String {
        provider == .openAICompatible ? temperatureDefaultsKey : "ai.http.\(provider.rawValue).temperature"
    }
}

enum HTTPAIConfigurationError: LocalizedError {
    case invalidBaseURL
    case missingModel

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "HTTP LLM base URL is invalid."
        case .missingModel:
            "HTTP LLM model is required."
        }
    }
}
