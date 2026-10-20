import Foundation

enum OllamaRefinementError: Error {
    case inputTooLong
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
}

/// One inference request, no redirects/retries, and no partial or thinking-only result.
enum OllamaRefinementClient {
    static func makeRequest(baseURL: URL, model: String, prompt: String, system: String,
                            temperature: Double, timeout: TimeInterval) throws -> URLRequest {
        guard let base = CustomEndpointPolicy.validatedURL(baseURL.absoluteString),
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              model.rangeOfCharacter(from: .controlCharacters) == nil,
              timeout.isFinite, timeout > 0 else { throw OllamaRefinementError.invalidRequest }
        var options: [String: Any] = ["temperature": temperature]
        if model == "qwen3.5:9b" {
            // UTF-8 bytes conservatively bound Qwen byte-level input tokens. Reserve space
            // for the model's envelope and output, rather than letting Ollama truncate input.
            guard prompt.utf8.count + system.utf8.count <= 12_000 else {
                throw OllamaRefinementError.inputTooLong
            }
            options["num_ctx"] = 16_384
            options["num_predict"] = 2_048
        }
        let body: [String: Any] = ["model": model, "prompt": prompt, "system": system,
                                   "stream": false, "think": false, "options": options]
        var request = URLRequest(url: base.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func completedText(_ data: Data) throws -> String {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              body["done"] as? Bool == true, body["done_reason"] as? String == "stop",
              let text = body["response"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OllamaRefinementError.invalidResponse
        }
        return text
    }

    static func generate(baseURL: URL, model: String, prompt: String, system: String,
                         temperature: Double, timeout: TimeInterval) async throws -> String {
        let request = try makeRequest(baseURL: baseURL, model: model, prompt: prompt,
                                      system: system, temperature: temperature, timeout: timeout)
        let (data, response) = try await SingleRequestHTTPTransport.send(request)
        guard let http = response as? HTTPURLResponse else { throw OllamaRefinementError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw OllamaRefinementError.httpStatus(http.statusCode) }
        return try completedText(data)
    }
}
