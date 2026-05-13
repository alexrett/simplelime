import Foundation

struct HTTPAIChatMessage: Equatable, Sendable {
    var role: String
    var content: String
}

protocol HTTPAICompleting: Sendable {
    func complete(messages: [HTTPAIChatMessage], systemPrompt: String) async throws -> String
}

enum HTTPAIClientError: LocalizedError, Equatable {
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "HTTP LLM returned an invalid response."
        case .requestFailed(let statusCode, let message):
            "HTTP LLM request failed with status \(statusCode): \(message)"
        case .emptyResponse:
            "HTTP LLM returned an empty response."
        }
    }
}

final class HTTPAIClient: HTTPAICompleting, @unchecked Sendable {
    private let configuration: HTTPAIConfiguration
    private let urlSession: URLSession

    init(configuration: HTTPAIConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func complete(messages: [HTTPAIChatMessage], systemPrompt: String) async throws -> String {
        switch configuration.provider {
        case .openAICompatible:
            return try await completeWithOpenAICompatibleProvider(messages: messages, systemPrompt: systemPrompt)
        case .anthropic:
            return try await completeWithAnthropic(messages: messages, systemPrompt: systemPrompt)
        case .gemini:
            return try await completeWithGemini(messages: messages, systemPrompt: systemPrompt)
        }
    }

    private func completeWithOpenAICompatibleProvider(
        messages: [HTTPAIChatMessage],
        systemPrompt: String
    ) async throws -> String {
        let payload = ChatCompletionsRequest(
            model: configuration.model,
            messages: [ChatMessage(role: "system", content: systemPrompt)]
                + messages.map { ChatMessage(role: $0.role, content: $0.content) },
            temperature: configuration.temperature
        )

        var request = URLRequest(url: Self.chatCompletionsURL(from: configuration.baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPAIClientError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw HTTPAIClientError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: data)
            )
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !content.isEmpty else {
            throw HTTPAIClientError.emptyResponse
        }

        return content
    }

    private func completeWithAnthropic(messages: [HTTPAIChatMessage], systemPrompt: String) async throws -> String {
        let payload = AnthropicMessagesRequest(
            model: configuration.model,
            maxTokens: 4096,
            system: systemPrompt,
            messages: messages.map {
                AnthropicMessage(
                    role: $0.role == "assistant" ? "assistant" : "user",
                    content: $0.content
                )
            },
            temperature: configuration.temperature
        )

        var request = URLRequest(url: Self.anthropicMessagesURL(from: configuration.baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !configuration.apiKey.isEmpty {
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPAIClientError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw HTTPAIClientError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: data)
            )
        }

        let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        let content = decoded.content
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw HTTPAIClientError.emptyResponse
        }

        return content
    }

    private func completeWithGemini(messages: [HTTPAIChatMessage], systemPrompt: String) async throws -> String {
        let payload = GeminiGenerateContentRequest(
            systemInstruction: GeminiContent(parts: [GeminiPart(text: systemPrompt)]),
            contents: messages.map {
                GeminiContent(
                    role: $0.role == "assistant" ? "model" : "user",
                    parts: [GeminiPart(text: $0.content)]
                )
            },
            generationConfig: GeminiGenerationConfig(temperature: configuration.temperature)
        )

        var request = URLRequest(url: Self.geminiGenerateContentURL(from: configuration.baseURL, model: configuration.model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !configuration.apiKey.isEmpty {
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPAIClientError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw HTTPAIClientError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: data)
            )
        }

        let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        let content = decoded.candidates
            .first?
            .content
            .parts
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let content, !content.isEmpty else {
            throw HTTPAIClientError.emptyResponse
        }

        return content
    }

    static func chatCompletionsURL(from baseURL: URL) -> URL {
        let trimmedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.hasSuffix("chat/completions") {
            return baseURL
        }
        return baseURL.appendingPathComponent("chat/completions")
    }

    static func anthropicMessagesURL(from baseURL: URL) -> URL {
        let trimmedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.hasSuffix("messages") {
            return baseURL
        }
        return baseURL.appendingPathComponent("messages")
    }

    static func geminiGenerateContentURL(from baseURL: URL, model: String) -> URL {
        let absoluteString = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if absoluteString.hasSuffix(":generateContent") {
            return baseURL
        }

        let trimmedModel = model.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let modelPath = trimmedModel.hasPrefix("models/") ? trimmedModel : "models/\(trimmedModel)"
        return URL(string: "\(absoluteString)/\(modelPath):generateContent")!
    }

    private static func errorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(ChatCompletionsErrorResponse.self, from: data),
           let message = decoded.error.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty {
            return text
        }

        return "No response body."
    }
}

private struct ChatCompletionsRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }

        var message: Message
    }

    var choices: [Choice]
}

private struct ChatCompletionsErrorResponse: Decodable {
    struct APIError: Decodable {
        var message: String?
    }

    var error: APIError
}

private struct AnthropicMessagesRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case temperature
    }

    var model: String
    var maxTokens: Int
    var system: String
    var messages: [AnthropicMessage]
    var temperature: Double
}

private struct AnthropicMessage: Codable {
    var role: String
    var content: String
}

private struct AnthropicMessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        var type: String?
        var text: String?
    }

    var content: [ContentBlock]
}

private struct GeminiGenerateContentRequest: Encodable {
    var systemInstruction: GeminiContent
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Codable {
    var role: String?
    var parts: [GeminiPart]

    init(role: String? = nil, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }
}

private struct GeminiPart: Codable {
    var text: String?
}

private struct GeminiGenerationConfig: Codable {
    var temperature: Double
}

private struct GeminiGenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        var content: GeminiContent
    }

    var candidates: [Candidate]
}
