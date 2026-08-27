import Foundation
import LLMkit
import SwiftData

struct GeminiProvider: CloudProvider {
    let modelProvider: ModelProvider = .gemini
    let providerKey: String = "Gemini"
    let languageCodes: [String]? = nil
    let includesAutoDetect: Bool = false

    var models: [CloudModel] {
        [
            CloudModel(
                name: AppDefaults.workingGeminiTranscriptionModel,
                displayName: "Gemini 3.5 Flash-Lite",
                description: "Google's low-latency model for multilingual transcription",
                provider: .gemini,
                speed: 0.92,
                accuracy: 0.96,
                isMultilingual: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .gemini)
            ),
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?, customVocabulary: [String]
    ) async throws -> String {
        return try await GeminiTranscriptionService.transcribe(
            audioData: audioData,
            apiKey: apiKey,
            model: model,
            language: language,
            customVocabulary: customVocabulary
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? { nil }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await GeminiTranscriptionClient.verifyAPIKey(key)
    }
}
