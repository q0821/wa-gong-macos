import Foundation
import LLMkit

/// Native Gemini/Anthropic text requests with explicit completion validation.
enum NativeRefinementClient {
    static func chatCompletion(
        provider: AIProvider, apiKey: String, model: String, messages: [ChatMessage],
        systemPrompt: String?, timeout: TimeInterval
    ) async throws -> String {
        let request = try makeRequest(
            provider: provider, apiKey: apiKey, model: model, messages: messages,
            systemPrompt: systemPrompt, timeout: timeout
        )
        do {
            let (data, response) = try await SingleRequestHTTPTransport.send(request)
            guard let http = response as? HTTPURLResponse else { throw LLMKitError.noResultReturned }
            guard (200...299).contains(http.statusCode) else {
                throw LLMKitError.httpError(statusCode: http.statusCode, message: "AI request rejected")
            }
            return try completedText(provider: provider, data: data)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMKitError.timeout
        }
    }

    static func makeRequest(
        provider: AIProvider, apiKey: String, model: String, messages: [ChatMessage],
        systemPrompt: String?, timeout: TimeInterval
    ) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              apiKey.rangeOfCharacter(from: .controlCharacters) == nil else { throw LLMKitError.missingAPIKey }
        let usable = messages.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let conversation = usable.filter { $0.role != "system" }
        guard !conversation.isEmpty, conversation.last?.role == "user",
              conversation.allSatisfy({ ["user", "assistant", "model"].contains($0.role) }) else {
            throw LLMKitError.encodingError
        }
        let system = systemPrompt ?? usable.filter { $0.role == "system" }.map(\.content).joined(separator: "\n")
        let endpoint: URL
        var body: [String: Any]
        switch provider {
        case .gemini:
            let version = model.contains("-preview") ? "v1beta" : "v1"
            endpoint = URL(string: "https://generativelanguage.googleapis.com/\(version)/interactions")!
            body = [
                "model": model, "store": false,
                "input": conversation.map { message in
                    ["type": message.role == "user" ? "user_input" : "model_output",
                     "content": [["type": "text", "text": message.content]]] as [String: Any]
                },
            ]
            if let thinking = ReasoningConfig.geminiThinkingLevel(for: model) {
                body["generation_config"] = ["thinking_level": thinking.rawValue]
            }
            if !system.isEmpty { body["system_instruction"] = system }
        case .anthropic:
            endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
            body = [
                "model": model, "max_tokens": 8192,
                "messages": conversation.map { ["role": $0.role == "model" ? "assistant" : $0.role, "content": $0.content] },
            ]
            if !system.isEmpty { body["system"] = system }
        default:
            throw LLMKitError.encodingError
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider == .gemini {
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func completedText(provider: AIProvider, data: Data) throws -> String {
        guard let response = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw LLMKitError.noResultReturned
        }
        let blocks: [[String: Any]]
        switch provider {
        case .gemini:
            guard response["status"] as? String == "completed",
                  let steps = response["steps"] as? [[String: Any]],
                  let final = steps.last, final["type"] as? String == "model_output",
                  let content = final["content"] as? [[String: Any]],
                  content.allSatisfy({ $0["type"] as? String == "text" }) else { throw LLMKitError.noResultReturned }
            blocks = content
        case .anthropic:
            guard response["stop_reason"] as? String == "end_turn",
                  let content = response["content"] as? [[String: Any]],
                  content.allSatisfy({ ["text", "thinking", "redacted_thinking"].contains($0["type"] as? String ?? "") }) else {
                throw LLMKitError.noResultReturned
            }
            blocks = content
        default:
            throw LLMKitError.noResultReturned
        }
        let result = blocks.filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LLMKitError.noResultReturned }
        return result
    }
}
