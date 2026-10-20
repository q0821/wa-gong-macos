import Foundation
@testable import VoiceInk

/// Links actual App code without initializing its services, stores, Keychain or @main.
@main
struct LocalFixAcceptance {
    static func main() async throws {
        let env = ProcessInfo.processInfo.environment
        let endpoint = env["WAGONG_LOCAL_ENDPOINT"] ?? ""
        guard let url = URL(string: endpoint), url.scheme == "http", url.host == "127.0.0.1" else { throw URLError(.badURL) }
        if CommandLine.arguments.contains("--audit") {
            let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tools/local-model-probe/.runtime")
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("app-combined-") && !$0.lastPathComponent.contains("summary") }
            var audits: [[String: Any]] = []
            for file in files {
                guard let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]] else { continue }
                let decisions = rows.map { row -> [String: Any] in
                    let source = row["transcript"] as! String, output = row["output"] as! String
                    return ["asr": row["asr"]!, "fixture": row["fixture"]!,
                            "accepted_by_final_policy": LocalCleanupOutputPolicy.accepts(source: source, output: output)]
                }
                audits.append(["source_file": file.lastPathComponent, "decisions": decisions])
            }
            try JSONSerialization.data(withJSONObject: audits, options: .prettyPrinted).write(
                to: directory.appendingPathComponent("final-content-audit.json"), options: .withoutOverwriting)
            print("Actual final App policy audited preserved synthetic model outputs; no inference sent")
            return
        }
        if CommandLine.arguments.contains("--combined") {
            guard let endpoint = env["WAGONG_ASR_ENDPOINT"], let asrURL = URL(string: endpoint),
                  asrURL.scheme == "http", asrURL.host == "127.0.0.1",
                  let token = env["WAGONG_LOCAL_TOKEN"] else { throw URLError(.badURL) }
            let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tools/local-model-probe/.runtime")
            var rows: [[String: Any]] = []
            for model in ["tea-gguf", "qwen3-asr-0.6b-gguf"] {
                for name in ["english", "mixed", "zh", "numbers"] {
                    let start = ContinuousClock.now
                    let request = try OpenAICompatibleTranscriptionService.makeRequest(
                        audioData: Data(contentsOf: directory.appendingPathComponent(name + ".wav")),
                        endpoint: endpoint, apiKey: token, modelName: model, language: name == "english" ? "en" : "zh-TW")
                    let text = try await OpenAICompatibleTranscriptionService.send(request)
                    let protected = CleanupProtectedText(text)
                    let system = AIEnhancementContextPolicy.systemMessage(
                        prompt: PromptTemplates.defaultPrompt.toCustomPrompt(), contextBlocks: []
                    ) + "\n\n" + LocalCleanupOutputPolicy.instruction(for: text) + "\n" + protected.instruction
                    let generated = try await OllamaRefinementClient.generate(baseURL: url, model: "qwen3.5:9b",
                        prompt: "\n<TRANSCRIPT>\n\(protected.text)\n</TRANSCRIPT>", system: system, temperature: 0.3, timeout: 90)
                    let restored = protected.restore(generated)
                    let output = restored ?? generated
                    let accepted = restored != nil && LocalCleanupOutputPolicy.accepts(source: text, output: output)
                    let d = start.duration(to: .now).components
                    rows.append(["asr": model, "fixture": name, "transcript": text, "output": output,
                                 "accepted": accepted, "seconds": Double(d.seconds) + Double(d.attoseconds) / 1e18])
                    print("Combined actual App clients: \(model) \(name) accepted=\(accepted)")
                }
            }
            try JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted).write(
                to: directory.appendingPathComponent("app-combined-\(UUID().uuidString).json"), options: .withoutOverwriting)
            guard rows.allSatisfy({ $0["accepted"] as? Bool == true }) else { throw URLError(.cannotParseResponse) }
            return
        }
        if CommandLine.arguments.contains("--asr") {
            guard let audio = env["WAGONG_LOCAL_AUDIO"], let token = env["WAGONG_LOCAL_TOKEN"] else { throw URLError(.badURL) }
            let request = try OpenAICompatibleTranscriptionService.makeRequest(audioData: Data(contentsOf: URL(fileURLWithPath: audio)),
                endpoint: endpoint, apiKey: token, modelName: "tea-gguf", language: "zh-TW")
            let text = try await OpenAICompatibleTranscriptionService.send(request)
            guard text.filter({ $0.isLetter || $0.isNumber }) == "今天下午三點開會請保留原始資料不要刪除" else { throw URLError(.cannotParseResponse) }
            print("Actual App ASR request/transport/parser passed against corrected TEA GGUF worker")
            return
        }
        let fixtures = [
            ("english", "Please review the API tomorrow. Do not delete the original data."),
            ("mixed", "請幫我 review 這個 api，今天先不要 deploy。"),
            ("zh", "今天下午三點開會，請保留原始資料，不要刪除。"),
            ("numbers", "訂單金額是一萬兩千五百元，不是一千兩百五十元。")
        ]
        var rows: [[String: Any]] = []
        for (name, text) in fixtures {
            let protected = CleanupProtectedText(text)
            let system = AIEnhancementContextPolicy.systemMessage(
                prompt: PromptTemplates.defaultPrompt.toCustomPrompt(), contextBlocks: []
            ) + "\n\n" + LocalCleanupOutputPolicy.instruction(for: text) + "\n" + protected.instruction
            let start = ContinuousClock.now
            let generated = try await OllamaRefinementClient.generate(baseURL: url, model: "qwen3.5:9b",
                prompt: "\n<TRANSCRIPT>\n\(protected.text)\n</TRANSCRIPT>", system: system, temperature: 0.3, timeout: 90)
            let restored = protected.restore(generated)
            let result = restored ?? generated
            let accepted = restored != nil && LocalCleanupOutputPolicy.accepts(source: text, output: result)
            let d = start.duration(to: .now).components
            rows.append(["fixture": name, "source": text, "result": result, "accepted": accepted,
                         "seconds": Double(d.seconds) + Double(d.attoseconds) / 1e18])
            print("Actual App local cleanup fixture=\(name) accepted=\(accepted)")
        }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tools/local-model-probe/.runtime")
        try JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted).write(
            to: directory.appendingPathComponent("app-ollama-fix-\(UUID().uuidString).json"), options: .withoutOverwriting)
        guard rows.allSatisfy({ $0["accepted"] as? Bool == true }) else { throw URLError(.cannotParseResponse) }
    }
}
