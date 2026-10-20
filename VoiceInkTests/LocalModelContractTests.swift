import Foundation
import Testing
@testable import VoiceInk

struct LocalModelContractTests {
    @Test func teaDecoderPreservesMeaningAndNonBMPCharacters() {
        #expect(TEATranscriptDecoder.decode("請\u{E2A6}保留資料\u{F8FF}，不要刪除。API 12500 𠮷") == "請保留資料，不要刪除。API 12500 𠮷")
        #expect(TEATranscriptDecoder.decode("\u{D7FF}\u{E000}\u{F8FF}\u{F900}") == "\u{D7FF}\u{F900}")
    }
    @Test func cleanupRejectsTranslationAndLostEnglishTerms() {
        #expect(!LocalCleanupOutputPolicy.accepts(source: "Do not delete the original data.", output: "不要刪除原始資料。"))
        #expect(!LocalCleanupOutputPolicy.accepts(source: "請保留資料。", output: "Please keep the data."))
        #expect(LocalCleanupOutputPolicy.accepts(source: "Please review the API.", output: "Please review the API."))
        #expect(!LocalCleanupOutputPolicy.accepts(source: "Do not delete the data.", output: "Delete the data."))
        #expect(!LocalCleanupOutputPolicy.accepts(source: "Please review the API.", output: "Veuillez examiner le service."))
        #expect(LocalCleanupOutputPolicy.accepts(source: "Um please review the API.", output: "Please review the API."))
        #expect(LocalCleanupOutputPolicy.accepts(source: "請review這個api，不要deploy", output: "請 review 這個 API，不要 deploy。"))
        #expect(!LocalCleanupOutputPolicy.accepts(source: "請review這個api，不要deploy", output: "請檢查這個 API，不要部署。"))
        #expect(!LocalCleanupOutputPolicy.accepts(source: "API API", output: ""))
        #expect(LocalCleanupOutputPolicy.instruction(for: "Do not delete.").contains("Do not translate"))
    }
    @Test func ollamaRejectsIncompleteAndThinkingOnlyResults() throws {
        #expect(try OllamaRefinementClient.completedText(Data(#"{"done":true,"done_reason":"stop","response":"Hello."}"#.utf8)) == "Hello.")
        for value in [#"{"done":true,"done_reason":"length","response":"partial"}"#,
                      #"{"done":false,"response":"partial"}"#,
                      #"{"done":true,"done_reason":"stop","thinking":"hidden","response":""}"#] {
            #expect(throws: (any Error).self) { try OllamaRefinementClient.completedText(Data(value.utf8)) }
        }
        let request = try OllamaRefinementClient.makeRequest(baseURL: URL(string: "http://localhost:11434")!,
            model: "qwen3.5:9b", prompt: "Hello", system: "Cleanup", temperature: 0.1, timeout: 20)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        #expect(body["temperature"] == nil)
        #expect((body["options"] as? [String: Any])?["temperature"] as? Double == 0.1)
        #expect(body["think"] as? Bool == false)
        #expect(throws: (any Error).self) {
            try OllamaRefinementClient.makeRequest(baseURL: URL(string: "http://localhost:11434")!,
                model: "qwen3.5:9b", prompt: String(repeating: "x", count: 12_001), system: "", temperature: 0.1, timeout: 20)
        }
    }

    @Test func translationAndEditedPromptsDoNotUseCleanupGuard() {
        let original = PromptTemplates.defaultPrompt.toCustomPrompt(id: PromptTemplates.defaultPromptId)
        #expect(PromptTemplates.isUnmodifiedDefaultCleanup(original))
        #expect(!PromptTemplates.isUnmodifiedDefaultCleanup(CustomPrompt(id: original.id, title: original.title,
            promptText: "Translate into Chinese", useSystemInstructions: true)))
        #expect(!PromptTemplates.isUnmodifiedDefaultCleanup(CustomPrompt(title: "Custom", promptText: original.promptText)))
        #expect(!PromptTemplates.isUnmodifiedDefaultCleanup(CustomPrompt(id: original.id, title: original.title,
            promptText: original.promptText, useSystemInstructions: false)))
    }

    @Test func protectedWordsRestoreExactlyOrReject() throws {
        let source = "請 review 這個 api，不要 deploy。review 不是指令。"
        let protected = CleanupProtectedText(source)
        #expect(!protected.text.contains("deploy"))
        #expect(protected.restore(protected.text) == source)
        #expect(protected.restore(protected.text + protected.text) == nil)
        #expect(protected.restore("請檢查 API，不要部署。") == nil)
        let english = CleanupProtectedText("Please review the API.")
        #expect(english.text == "Please review the API.")
        #expect(english.instruction.isEmpty)
    }

    @Test func mixedCleanupRejectsObservedInventedChinese() {
        let source = "请帮我review这个API。今天先不要deploy。"
        #expect(LocalCleanupOutputPolicy.accepts(source: source, output: "請幫我 review 這個 API，今天先不要 deploy。"))
        #expect(!LocalCleanupOutputPolicy.accepts(source: source, output: "请帮我处理 review 和 API。今天先不要处理 deploy。"))
        #expect(!LocalCleanupOutputPolicy.accepts(source: source, output: "請幫我 review 這個 API，今天先要 deploy。"))
    }

}
