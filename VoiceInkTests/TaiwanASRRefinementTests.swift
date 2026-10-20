import Testing
@testable import VoiceInk

struct TaiwanASRRefinementTests {
    @Test func newRefinementModelsAreSelectableWithoutChangingDefaults() {
        #expect(AIProvider.gemini.availableModels.contains("gemini-3.8-flash"))
        #expect(AIProvider.anthropic.availableModels.contains("claude-haiku-5-5"))
        #expect(AIProvider.gemini.defaultModel == "gemini-3.6-flash")
        #expect(AIProvider.gemini.availableModels.first == "gemini-3.6-flash")
        #expect(AIProvider.anthropic.availableModels.contains("claude-haiku-4-5"))
    }

    @Test func flash38UsesSupportedLowThinkingWithoutChangingOlderModels() {
        #expect(ReasoningConfig.geminiThinkingLevel(for: "gemini-3.8-flash")?.rawValue == "low")
        #expect(ReasoningConfig.geminiThinkingLevel(for: "gemini-3.6-flash")?.rawValue == "minimal")
        #expect(ReasoningConfig.geminiThinkingLevel(for: "unknown-future-model") == nil)
    }
}
