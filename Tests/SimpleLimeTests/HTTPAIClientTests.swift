import Foundation
import XCTest
@testable import SimpleLime

final class HTTPAIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSendsOpenAICompatibleChatCompletionsRequest() async throws {
        let configuration = try HTTPAIConfiguration(
            baseURLString: "https://example.com/v1",
            apiKey: "test-key",
            model: "test-model",
            temperature: 0.4
        )
        let client = HTTPAIClient(configuration: configuration, urlSession: mockSession())
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data("""
            {"choices":[{"message":{"content":"Assistant reply"}}]}
            """.utf8)
            return (response, data)
        }

        let response = try await client.complete(
            messages: [HTTPAIChatMessage(role: "user", content: "Hello")],
            systemPrompt: "System prompt"
        )

        XCTAssertEqual(response, "Assistant reply")
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try requestBody(from: request)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "test-model")
        let temperature = try XCTUnwrap(payload["temperature"] as? NSNumber)
        XCTAssertEqual(temperature.doubleValue, 0.4, accuracy: 0.001)

        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "System prompt")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "Hello")
    }

    func testOmitsAuthorizationHeaderWhenAPIKeyIsEmpty() async throws {
        let configuration = try HTTPAIConfiguration(
            baseURLString: "http://localhost:11434/v1",
            apiKey: "",
            model: "local-model"
        )
        let client = HTTPAIClient(configuration: configuration, urlSession: mockSession())
        var authorizationHeader: String?

        MockURLProtocol.requestHandler = { request in
            authorizationHeader = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data("""
            {"choices":[{"message":{"content":"Local reply"}}]}
            """.utf8)
            return (response, data)
        }

        _ = try await client.complete(
            messages: [HTTPAIChatMessage(role: "user", content: "Hello")],
            systemPrompt: "System prompt"
        )

        XCTAssertNil(authorizationHeader)
    }

    func testSendsAnthropicMessagesRequest() async throws {
        let configuration = try HTTPAIConfiguration(
            provider: .anthropic,
            baseURLString: "https://api.anthropic.test/v1",
            apiKey: "anthropic-key",
            model: "claude-test",
            temperature: 0.3
        )
        let client = HTTPAIClient(configuration: configuration, urlSession: mockSession())
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data("""
            {"content":[{"type":"text","text":"Claude reply"}]}
            """.utf8)
            return (response, data)
        }

        let response = try await client.complete(
            messages: [HTTPAIChatMessage(role: "user", content: "Hello")],
            systemPrompt: "System prompt"
        )

        XCTAssertEqual(response, "Claude reply")
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.test/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try requestBody(from: request)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "claude-test")
        XCTAssertEqual(payload["system"] as? String, "System prompt")
        XCTAssertEqual(payload["max_tokens"] as? Int, 4096)
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "Hello")
    }

    func testSendsGeminiGenerateContentRequest() async throws {
        let configuration = try HTTPAIConfiguration(
            provider: .gemini,
            baseURLString: "https://generativelanguage.test/v1beta",
            apiKey: "gemini-key",
            model: "gemini-test",
            temperature: 0.6
        )
        let client = HTTPAIClient(configuration: configuration, urlSession: mockSession())
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data("""
            {"candidates":[{"content":{"parts":[{"text":"Gemini reply"}]}}]}
            """.utf8)
            return (response, data)
        }

        let response = try await client.complete(
            messages: [
                HTTPAIChatMessage(role: "user", content: "Hello"),
                HTTPAIChatMessage(role: "assistant", content: "Hi")
            ],
            systemPrompt: "System prompt"
        )

        XCTAssertEqual(response, "Gemini reply")
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.test/v1beta/models/gemini-test:generateContent")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-key")

        let body = try requestBody(from: request)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let systemInstruction = try XCTUnwrap(payload["systemInstruction"] as? [String: Any])
        let systemParts = try XCTUnwrap(systemInstruction["parts"] as? [[String: Any]])
        XCTAssertEqual(systemParts.first?["text"] as? String, "System prompt")
        let contents = try XCTUnwrap(payload["contents"] as? [[String: Any]])
        XCTAssertEqual(contents[0]["role"] as? String, "user")
        XCTAssertEqual(contents[1]["role"] as? String, "model")
        let generationConfig = try XCTUnwrap(payload["generationConfig"] as? [String: Any])
        let temperature = try XCTUnwrap(generationConfig["temperature"] as? NSNumber)
        XCTAssertEqual(temperature.doubleValue, 0.6, accuracy: 0.001)
    }

    func testSurfacesProviderErrorMessage() async throws {
        let configuration = try HTTPAIConfiguration(
            baseURLString: "https://example.com/v1",
            apiKey: "bad-key",
            model: "test-model"
        )
        let client = HTTPAIClient(configuration: configuration, urlSession: mockSession())

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data("""
            {"error":{"message":"bad API key"}}
            """.utf8)
            return (response, data)
        }

        do {
            _ = try await client.complete(
                messages: [HTTPAIChatMessage(role: "user", content: "Hello")],
                systemPrompt: "System prompt"
            )
            XCTFail("Expected request failure.")
        } catch let error as HTTPAIClientError {
            XCTAssertEqual(error, .requestFailed(statusCode: 401, message: "bad API key"))
        }
    }

    func testUsesExplicitChatCompletionsEndpointAsIs() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://example.com/v1/chat/completions"))

        XCTAssertEqual(
            HTTPAIClient.chatCompletionsURL(from: baseURL).absoluteString,
            "https://example.com/v1/chat/completions"
        )
    }

    func testUsesExplicitProviderEndpointsAsIs() throws {
        let anthropicURL = try XCTUnwrap(URL(string: "https://example.com/v1/messages"))
        let geminiURL = try XCTUnwrap(URL(string: "https://example.com/v1beta/models/gemini-test:generateContent"))

        XCTAssertEqual(
            HTTPAIClient.anthropicMessagesURL(from: anthropicURL).absoluteString,
            "https://example.com/v1/messages"
        )
        XCTAssertEqual(
            HTTPAIClient.geminiGenerateContentURL(from: geminiURL, model: "ignored").absoluteString,
            "https://example.com/v1beta/models/gemini-test:generateContent"
        )
    }

    func testConfigurationTrimsAndClampsValues() throws {
        let configuration = try HTTPAIConfiguration(
            baseURLString: " https://example.com/v1 ",
            apiKey: " test-key ",
            model: " test-model ",
            temperature: 9
        )

        XCTAssertEqual(configuration.baseURL.absoluteString, "https://example.com/v1")
        XCTAssertEqual(configuration.apiKey, "test-key")
        XCTAssertEqual(configuration.model, "test-model")
        XCTAssertEqual(configuration.temperature, 2)
    }

    func testLoadsProviderSpecificConfigurationFromDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SimpleLimeHTTPAIClientTests-\(UUID().uuidString)"))
        defaults.set(HTTPAIProvider.gemini.rawValue, forKey: HTTPAIConfiguration.providerDefaultsKey)
        defaults.set("https://gemini.example/v1beta", forKey: HTTPAIConfiguration.baseURLDefaultsKey(for: .gemini))
        defaults.set("gemini-key", forKey: HTTPAIConfiguration.apiKeyDefaultsKey(for: .gemini))
        defaults.set("gemini-model", forKey: HTTPAIConfiguration.modelDefaultsKey(for: .gemini))
        defaults.set(0.7, forKey: HTTPAIConfiguration.temperatureDefaultsKey(for: .gemini))

        let configuration = try HTTPAIConfiguration.current(defaults: defaults)

        XCTAssertEqual(configuration.provider, .gemini)
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://gemini.example/v1beta")
        XCTAssertEqual(configuration.apiKey, "gemini-key")
        XCTAssertEqual(configuration.model, "gemini-model")
        XCTAssertEqual(configuration.temperature, 0.7)
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func requestBody(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
