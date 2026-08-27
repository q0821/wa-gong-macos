import Foundation
import LLMkit
import SwiftData

struct OpenAIProvider: CloudProvider {
    // LLMkit appends `v1/models` and `v1/audio/transcriptions` to this URL.
    static let apiBaseURL = URL(string: "https://api.openai.com")!
    private static let transcriptionTimeout: TimeInterval = 30

    let modelProvider: ModelProvider = .openAI
    let providerKey: String = "OpenAI"
    let languageCodes: [String]? = nil
    let includesAutoDetect: Bool = false

    var models: [CloudModel] {
        let supportedLanguages = LanguageDictionary.forProvider(isMultilingual: true, provider: .openAI)
        return [
            CloudModel(
                name: "gpt-4o-mini-transcribe",
                displayName: "GPT-4o Mini Transcribe",
                description: "Fast, multilingual OpenAI transcription for everyday dictation",
                provider: .openAI,
                speed: 0.95,
                accuracy: 0.96,
                isMultilingual: true,
                supportedLanguages: supportedLanguages
            ),
            CloudModel(
                name: "gpt-transcribe",
                displayName: "GPT Transcribe",
                description: "OpenAI's latest high-accuracy multilingual transcription model",
                provider: .openAI,
                speed: 0.85,
                accuracy: 0.99,
                isMultilingual: true,
                supportedLanguages: supportedLanguages
            ),
            CloudModel(
                name: "gpt-4o-transcribe",
                displayName: "GPT-4o Transcribe",
                description: "High-accuracy multilingual transcription powered by GPT-4o",
                provider: .openAI,
                speed: 0.8,
                accuracy: 0.98,
                isMultilingual: true,
                supportedLanguages: supportedLanguages
            ),
            CloudModel(
                name: "gpt-4o-transcribe-diarize",
                displayName: "GPT-4o Transcribe Diarize",
                description: "Multilingual transcription with speaker labels",
                provider: .openAI,
                speed: 0.7,
                accuracy: 0.98,
                isMultilingual: true,
                supportedLanguages: supportedLanguages
            ),
            CloudModel(
                name: "whisper-1",
                displayName: "Whisper 1",
                description: "OpenAI's multilingual Whisper transcription model",
                provider: .openAI,
                speed: 0.7,
                accuracy: 0.93,
                isMultilingual: true,
                supportedLanguages: supportedLanguages
            )
        ]
    }

    func transcribe(
        audioData: Data, fileName: String, apiKey: String, model: String, language: String?, customVocabulary: [String]
    ) async throws -> String {
        if model == OpenAITranscriptionService.diarizationModel {
            return try await OpenAITranscriptionService.transcribeWithSpeakerLabels(
                audioData: audioData,
                fileName: fileName,
                apiKey: apiKey,
                language: language
            )
        }

        return try await OpenAITranscriptionClient.transcribe(
            baseURL: Self.apiBaseURL,
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language,
            prompt: customVocabulary.isEmpty ? nil : customVocabulary.joined(separator: ", "),
            timeout: Self.transcriptionTimeout
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? { nil }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        await OpenAITranscriptionClient.verifyAPIKey(
            baseURL: Self.apiBaseURL,
            apiKey: key
        )
    }
}
