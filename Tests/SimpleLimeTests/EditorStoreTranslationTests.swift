import Foundation
import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreTranslationTests: XCTestCase {
    func testTranslateSelectedTextReplacesSelectionsWithHTTPTranslation() async throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "Hello and world"
        buffer.selectionRanges = [
            TextRange(location: 0, length: 5),
            TextRange(location: 10, length: 5)
        ]
        let client = FakeHTTPAICompleting(response: #"["Hallo","Welt"]"#)
        let store = try makeStore(buffer: buffer, client: client)

        store.translateSelectedText(targetLanguage: "German")
        await waitForTranslation(in: store)

        XCTAssertEqual(store.selectedBuffer?.text, "Hallo and Welt")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [
            TextRange(location: 0, length: 5),
            TextRange(location: 10, length: 4)
        ])
        XCTAssertEqual(store.translationStatus, "Translated 2 selections to German.")
        XCTAssertEqual(client.requestedTargetLanguage, "German")
        XCTAssertEqual(client.systemPrompt, AITranslationRequest.systemPrompt)
    }

    func testTranslateSelectedTextRequiresSelection() throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "Hello"
        buffer.selectionRanges = [.zero]
        let store = try makeStore(buffer: buffer, client: FakeHTTPAICompleting(response: "Hallo"))

        store.translateSelectedText(targetLanguage: "German")

        XCTAssertEqual(store.lastError, "Select text to translate first.")
    }

    private func makeStore(buffer: EditorBuffer, client: FakeHTTPAICompleting) throws -> EditorStore {
        let configuration = try HTTPAIConfiguration(baseURLString: "https://example.com/v1", model: "test-model")
        return EditorStore(
            initialBuffers: [buffer],
            persistence: nil,
            httpAIClientFactory: { _ in client },
            httpAIConfigurationProvider: { configuration },
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func waitForTranslation(in store: EditorStore) async {
        for _ in 0..<100 where store.isTranslationRunning {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class FakeHTTPAICompleting: HTTPAICompleting, @unchecked Sendable {
    private let response: String
    private let lock = NSLock()
    private var messages: [HTTPAIChatMessage] = []
    private var capturedSystemPrompt: String?

    init(response: String) {
        self.response = response
    }

    var requestedTargetLanguage: String? {
        lock.withLock {
            messages.first?.content.components(separatedBy: .newlines).first?
                .replacingOccurrences(of: "Target language: ", with: "")
        }
    }

    var systemPrompt: String? {
        lock.withLock { capturedSystemPrompt }
    }

    func complete(messages: [HTTPAIChatMessage], systemPrompt: String) async throws -> String {
        lock.withLock {
            self.messages = messages
            self.capturedSystemPrompt = systemPrompt
        }
        return response
    }
}
