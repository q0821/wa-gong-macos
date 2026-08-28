import Foundation

private enum PrivacyHUDLocalization {
    static func string(_ key: String, locale: Locale, bundle: Bundle = .main) -> String {
        let localization = Bundle.preferredLocalizations(
            from: bundle.localizations,
            forPreferences: [locale.identifier]
        ).first

        guard
            let localization,
            let path = bundle.path(forResource: localization, ofType: "lproj"),
            let localizedBundle = Bundle(path: path)
        else {
            return key
        }

        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }
}

struct PrivacyRequestSummary: Equatable, Sendable {
    enum DataType: String, CaseIterable, Sendable {
        case transcript
        case prompt
        case conversation
        case audio
        case selectedText
        case screenOCR
        case customVocabulary

        func displayName(locale: Locale) -> String {
            switch self {
            case .transcript:
                return PrivacyHUDLocalization.string("Transcript", locale: locale)
            case .prompt:
                return PrivacyHUDLocalization.string("Prompt", locale: locale)
            case .conversation:
                return PrivacyHUDLocalization.string("Chat messages", locale: locale)
            case .audio:
                return PrivacyHUDLocalization.string("Audio", locale: locale)
            case .selectedText:
                return PrivacyHUDLocalization.string("Selected text", locale: locale)
            case .screenOCR:
                return PrivacyHUDLocalization.string("Screen OCR", locale: locale)
            case .customVocabulary:
                return PrivacyHUDLocalization.string("Custom vocabulary", locale: locale)
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
        displayText(locale: AppLanguagePreference.locale)
    }

    func displayText(locale: Locale) -> String {
        let dataDescription = dataTypes.map { $0.displayName(locale: locale) }.joined(separator: ", ")
        return String(
            format: PrivacyHUDLocalization.string(
                "External AI request\nDestination: %@\nModel: %@\nData: %@",
                locale: locale
            ),
            locale: locale,
            destination,
            modelName,
            dataDescription
        )
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
            duration: 4.0,
            placement: .recorderAdjacent(.stored())
        )
    }
}
