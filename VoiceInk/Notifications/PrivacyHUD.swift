import Foundation

struct PrivacyRequestSummary: Equatable, Sendable {
    enum DataType: String, CaseIterable, Sendable {
        case transcript
        case prompt
        case conversation
        case audio
        case selectedText
        case screenOCR
        case customVocabulary

        var displayName: String {
            switch self {
            case .transcript:
                return "Transcript"
            case .prompt:
                return "Prompt"
            case .conversation:
                return "Chat messages"
            case .audio:
                return "Audio"
            case .selectedText:
                return "Selected text"
            case .screenOCR:
                return "Screen OCR"
            case .customVocabulary:
                return "Custom vocabulary"
            }
        }
    }

    let destination: String
    let modelName: String
    let dataTypes: [DataType]

    init(destination: String, modelName: String, dataTypes: [DataType]) {
        self.destination = Self.sanitizedDestination(destination)
        self.modelName = modelName
        self.dataTypes = dataTypes.reduce(into: []) { result, dataType in
            if !result.contains(dataType) {
                result.append(dataType)
            }
        }
    }

    var displayText: String {
        let dataDescription = dataTypes.map(\.displayName).joined(separator: ", ")
        return "External AI request\nDestination: \(destination)\nModel: \(modelName)\nData: \(dataDescription)"
    }

    static func sanitizedDestination(_ rawDestination: String) -> String {
        guard var components = URLComponents(string: rawDestination) else {
            return rawDestination
        }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? rawDestination
    }

    static func transcriptionDestination(for provider: ModelProvider) -> String? {
        switch provider {
        case .openAI:
            return "https://api.openai.com/v1/audio/transcriptions"
        case .groq:
            return "https://api.groq.com/openai/v1/audio/transcriptions"
        case .elevenLabs:
            return "https://api.elevenlabs.io/v1/speech-to-text"
        case .deepgram:
            return "https://api.deepgram.com/v1/listen"
        case .mistral:
            return "https://api.mistral.ai/v1/audio/transcriptions"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/models"
        case .soniox:
            return "https://api.soniox.com/v1"
        case .speechmatics:
            return "https://asr.api.speechmatics.com/v2"
        case .assemblyAI:
            return "https://api.assemblyai.com"
        case .xai:
            return "https://api.x.ai/v1/stt"
        case .cartesia:
            return "wss://api.cartesia.ai/stt/turns/websocket"
        case .whisper, .fluidAudio, .transcribeCpp, .nativeApple, .custom:
            return nil
        }
    }
}

@MainActor
enum PrivacyHUD {
    static func show(_ summary: PrivacyRequestSummary) {
        NotificationManager.shared.showNotification(
            title: summary.displayText,
            type: .info,
            duration: 4.0
        )
    }
}
