import Foundation
import Security
import LLMkit
@testable import VoiceInk

/// Prepared acceptance runner. Default mode never reads keys or sends requests.
@main
struct RefinementAcceptance {
    static let instruction = "請將語音轉錄整理成台灣繁體中文。只修正標點與繁簡字，不改變詞序及用字，保留原意、否定、時間與數字，不得新增事實。只輸出整理後的文字。"

    /// Reads existing App items without invoking migration, writes, or interactive prompts.
    static func readExistingKey(account: String) -> String? {
        for (service, protected) in [("com.jackie-yeh.wagong.Local", false),
                                     ("com.jackie-yeh.wagong", true)] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
            ]
            if protected {
                query[kSecUseDataProtectionKeychain as String] = true
                query[kSecAttrSynchronizable as String] = true
            }
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data,
               let key = String(data: data, encoding: .utf8), !key.isEmpty {
                print("Existing App credential available: \(account)")
                return key
            }
            print("Read-only App credential lookup: \(account), protected=\(protected), status=\(status)")
        }
        return nil
    }

    static func main() async {
        do {
            try await run()
        } catch {
            // Never print Error descriptions: a transport error can contain a credential URL.
            print("Acceptance stopped; no automatic retry. Failure type: \(type(of: error))")
            exit(1)
        }
    }

    static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WAGONG_ALLOW_BILLABLE_VALIDATION"] == "yes" else {
            print("Prepared: four requests, two synthetic ASR transcripts, Gemini 3.8 Flash and Claude Haiku 5.5.")
            print("Disabled: no API keys read, no cloud requests sent. Explicit approval is required.")
            return
        }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tools/taiwan-asr/.runtime")
        let clock = ContinuousClock()
        var results: [[String: Any]] = []
        // Resolve both keys before the first request. Never print key values.
        guard let geminiKey = readExistingKey(account: "geminiAPIKey"),
              let claudeKey = readExistingKey(account: "anthropicAPIKey"),
              !geminiKey.isEmpty, !claudeKey.isEmpty else {
            throw EnhancementError.notConfigured
        }
        let sources = try ["breeze", "tea"].map { name -> (String, String) in
            let data = try Data(contentsOf: directory.appendingPathComponent("\(name)-torch214-zh.json"))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let runs = json?["runs"] as? [[String: Any]], let text = runs.last?["text"] as? String,
                  text.filter({ $0.isLetter || $0.isNumber }).replacingOccurrences(of: "3", with: "三")
                    == "今天下午三點開會請保留原始資料不要刪除" else { throw EnhancementError.invalidResponse }
            return (name, text)
        }
        for (asr, text) in sources {
            for provider in [AIProvider.gemini, .anthropic] {
                let model = provider == .gemini ? "gemini-3.8-flash" : "claude-haiku-5-5"
                var request = try NativeRefinementClient.makeRequest(
                    provider: provider, apiKey: provider == .gemini ? geminiKey : claudeKey,
                    model: model, messages: [ChatMessage(role: "user", content: text)],
                    systemPrompt: instruction, timeout: 45
                )
                // Explicit test caps; these do not change production settings.
                guard let data = request.httpBody,
                      var body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw EnhancementError.invalidResponse
                }
                if provider == .gemini {
                    body["generation_config"] = ["thinking_level": "low", "max_output_tokens": 2048]
                } else {
                    body["max_tokens"] = 512
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let started = clock.now
                print("Sending approved synthetic-text combination: \(asr), \(model)")
                let (responseData, response) = try await SingleRequestHTTPTransport.send(request)
                if let http = response as? HTTPURLResponse {
                    print("Provider HTTP status: \(http.statusCode)")
                }
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    // Fail immediately. Do not retry or print the remote body.
                    throw EnhancementError.enhancementFailed
                }
                let output = try NativeRefinementClient.completedText(provider: provider, data: responseData)
                let normalized = output.filter { $0.isLetter || $0.isNumber }.replacingOccurrences(of: "3", with: "三")
                guard normalized == "今天下午三點開會請保留原始資料不要刪除" else {
                    throw EnhancementError.invalidResponse
                }
                let duration = started.duration(to: clock.now).components
                let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                results.append(["asr": asr, "refinement": model, "seconds": seconds,
                                "fixture_preserved": true])
                print("Validated approved combination: \(asr), \(model)")
            }
        }
        let output = directory.appendingPathComponent("approved-cloud-acceptance-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: results, options: .prettyPrinted).write(to: output, options: .withoutOverwriting)
        print("Four approved combinations passed; no tokens or full responses written to logs")
    }
}
