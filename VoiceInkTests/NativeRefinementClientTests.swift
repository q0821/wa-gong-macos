import Foundation
import LLMkit
import Testing
@testable import VoiceInk

struct NativeRefinementClientTests {
    @Test func flash38UsesNativeStatelessRequestAndLowThinking() throws {
        let request = try NativeRefinementClient.makeRequest(
            provider: .gemini, apiKey: "test-key", model: "gemini-3.8-flash",
            messages: [ChatMessage(role: "user", content: "固定測試句")], systemPrompt: "只整理文字", timeout: 20
        )
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1/interactions")
        #expect(body["store"] as? Bool == false)
        #expect((body["generation_config"] as? [String: Any])?["thinking_level"] as? String == "low")
        #expect(body["temperature"] == nil)
        #expect(body["previous_interaction_id"] == nil)
    }

    @Test func haiku55UsesMessagesAndKeepsSystemInstructionSeparate() throws {
        let request = try NativeRefinementClient.makeRequest(
            provider: .anthropic, apiKey: "test-key", model: "claude-haiku-5-5",
            messages: [ChatMessage(role: "system", content: "只整理文字"), ChatMessage(role: "user", content: "固定測試句")],
            systemPrompt: nil, timeout: 20
        )
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(body["system"] as? String == "只整理文字")
        #expect((body["messages"] as? [[String: String]])?.count == 1)
        #expect(body["temperature"] == nil)
    }

    @Test(arguments: ["incomplete", "failed", "in_progress", "requires_action"])
    func incompleteGeminiTextIsNeverReturned(_ status: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["status": status, "steps": [
            ["type": "model_output", "content": [["type": "text", "text": "partial"]]],
        ]])
        #expect(throws: (any Error).self) { try NativeRefinementClient.completedText(provider: .gemini, data: data) }
    }

    @Test(arguments: ["max_tokens", "refusal", "tool_use", "pause_turn", "model_context_window_exceeded"])
    func incompleteClaudeTextIsNeverReturned(_ reason: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["stop_reason": reason, "content": [["type": "text", "text": "partial"]]])
        #expect(throws: (any Error).self) { try NativeRefinementClient.completedText(provider: .anthropic, data: data) }
    }

    @Test func completedTextBlocksAreJoinedAndEmptyResponsesAreRejected() throws {
        let data = Data(#"{"stop_reason":"end_turn","content":[{"type":"text","text":"語音"},{"type":"text","text":"測試"}]}"#.utf8)
        #expect(try NativeRefinementClient.completedText(provider: .anthropic, data: data) == "語音測試")
        let gemini = Data(#"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"語音測試"}]}]}"#.utf8)
        #expect(try NativeRefinementClient.completedText(provider: .gemini, data: gemini) == "語音測試")
        let empty = Data(#"{"stop_reason":"end_turn","content":[]}"#.utf8)
        #expect(throws: (any Error).self) { try NativeRefinementClient.completedText(provider: .anthropic, data: empty) }
    }
}

private final class InferenceCountingProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedCount = 0
    static var count: Int { lock.withLock { storedCount } }
    static func reset() { lock.withLock { storedCount = 0 } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.storedCount += 1 }
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct SingleRequestHTTPTransportTests {
    @MainActor
    @Test(arguments: [AIProvider.gemini, .anthropic, .ollama])
    func nativeTimeoutDoesNotRetryEvenWithLegacyOptIn(_ provider: AIProvider) async {
        var attempts = 0
        await #expect(throws: EnhancementError.self) {
            let _: String = try await EnhancementRequestRetry.run(
                retryOnTimeout: true, provider: provider, request: {
                    attempts += 1
                    throw EnhancementError.timeout
                }, onRetry: { _, _ in Issue.record("Inference timeout must not be retried") }
            )
        }
        #expect(attempts == 1)
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InferenceCountingProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func serverFailureDoesNotSendAgain() async throws {
        InferenceCountingProtocol.reset()
        let session = session()
        defer { session.invalidateAndCancel() }
        let (_, response) = try await SingleRequestHTTPTransport.send(
            URLRequest(url: URL(string: "https://inference.invalid/test")!), session: session
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 503)
        #expect(InferenceCountingProtocol.count == 1)
    }

    @Test func canceledOperationDoesNotStartARequest() async throws {
        InferenceCountingProtocol.reset()
        let session = session()
        defer { session.invalidateAndCancel() }
        let gate = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate.stream { break }
            return try await SingleRequestHTTPTransport.send(
                URLRequest(url: URL(string: "https://inference.invalid/test")!), session: session
            )
        }
        task.cancel()
        gate.continuation.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(InferenceCountingProtocol.count == 0)
    }
}
