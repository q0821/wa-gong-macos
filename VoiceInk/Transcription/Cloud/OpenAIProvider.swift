import Foundation
import LLMkit
import SwiftData

struct OpenAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .openAI
    let providerKey: String = "OpenAI"
    let languageCodes: [String]? = nil
    let includesAutoDetect: Bool = false

    var models: [CloudModel] {
        [
            CloudModel(
                name: "whisper-1",
                displayName: "Whisper 1",
                description: "OpenAI's multilingual Whisper transcription model",
                provider: .openAI,
                speed: 0.7,
                accuracy: 0.93,
                isMultilingual: true,
                supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .openAI)
            )
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?, customVocabulary: [String]
    ) async throws -> String {
        try await OpenAITranscriptionClient.transcribe(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? { nil }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        await OpenAITranscriptionClient.verifyAPIKey(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: key
        )
    }
}
