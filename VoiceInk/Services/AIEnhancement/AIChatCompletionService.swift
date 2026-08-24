import Foundation
import LLMkit

extension AIService {
    private func announceExternalChatRequest(
        provider: AIProvider,
        modelName: String,
        hasSystemPrompt: Bool,
        hasMessages: Bool
    ) async {
        guard provider != .voiceInkRefine, provider != .ollama, provider != .localCLI else {
            return
        }

        let destination: String
        if provider == .custom {
            guard
                let customConfiguration = CustomAIProviderManager.shared.requestConfiguration(forModel: modelName)
            else {
                return
            }
            destination = customConfiguration.baseURL
        } else {
            destination = provider.baseURL
        }

        var dataTypes: [PrivacyRequestSummary.DataType] = []
        if hasMessages {
            dataTypes.append(.conversation)
        }
        if hasSystemPrompt {
            dataTypes.append(.prompt)
        }

        let summary = PrivacyRequestSummary(
            destination: destination,
            modelName: modelName,
            dataTypes: dataTypes
        )

        await MainActor.run {
            PrivacyHUD.show(summary)
        }
    }

    func completeChat(
        provider: AIProvider,
        modelName: String?,
        messages: [ChatMessage],
        systemPrompt: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> String {
        let resolvedModel = modelName?.isEmpty == false ? modelName! : selectedModel(for: provider)

        await announceExternalChatRequest(
            provider: provider,
            modelName: resolvedModel,
            hasSystemPrompt: !(systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
            hasMessages: !messages.isEmpty
        )

        let result: String
        switch provider {
        case .gemini:
            result = try await GeminiLLMClient.chatCompletion(
                apiKey: try chatAPIKey(for: provider, modelName: resolvedModel),
                model: resolvedModel,
                messages: messages,
                systemPrompt: systemPrompt,
                thinkingLevel: ReasoningConfig.geminiThinkingLevel(for: resolvedModel),
                store: false,
                timeout: timeout
            )
        case .anthropic:
            result = try await AnthropicLLMClient.chatCompletion(
                apiKey: try chatAPIKey(for: provider, modelName: resolvedModel),
                model: resolvedModel,
                messages: messages,
                systemPrompt: systemPrompt,
                timeout: timeout
            )
        case .custom:
            guard
                let customConfiguration = CustomAIProviderManager.shared.requestConfiguration(forModel: resolvedModel),
                let baseURL = URL(string: customConfiguration.baseURL)
            else {
                throw EnhancementError.notConfigured
            }
            result = try await OpenAILLMClient.chatCompletion(
                baseURL: baseURL,
                apiKey: customConfiguration.apiKey,
                model: customConfiguration.modelName,
                messages: messages,
                systemPrompt: systemPrompt,
                temperature: 0.3,
                timeout: timeout
            )
        case .voiceInkRefine:
            throw EnhancementError.customError(
                String(localized: "VoiceInk Refine only supports transcript cleanup.")
            )
        case .ollama:
            result = try await enhanceWithOllama(
                text: chatPrompt(from: messages),
                systemPrompt: systemPrompt ?? "",
                model: resolvedModel,
                timeout: timeout
            )
        case .localCLI:
            result = try await enhanceWithLocalCLI(
                systemPrompt: systemPrompt ?? "",
                userPrompt: chatPrompt(from: messages)
            )
        default:
            guard let baseURL = URL(string: provider.baseURL) else {
                throw EnhancementError.notConfigured
            }
            let temperature = resolvedModel.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3
            let reasoningEffort = ReasoningConfig.getReasoningParameter(
                for: provider,
                modelName: resolvedModel
            )
            let extraBody = ReasoningConfig.getExtraBodyParameters(
                for: provider,
                modelName: resolvedModel
            )
            result = try await OpenAILLMClient.chatCompletion(
                baseURL: baseURL,
                apiKey: try chatAPIKey(for: provider, modelName: resolvedModel),
                model: resolvedModel,
                messages: messages,
                systemPrompt: systemPrompt,
                temperature: temperature,
                reasoningEffort: reasoningEffort,
                extraBody: extraBody,
                timeout: timeout
            )
        }

        return AIEnhancementOutputFilter.filter(result)
    }

    private func chatAPIKey(for provider: AIProvider, modelName: String) throws -> String {
        if provider == .custom {
            guard let customConfiguration = CustomAIProviderManager.shared.requestConfiguration(forModel: modelName)
            else {
                throw EnhancementError.notConfigured
            }
            return customConfiguration.apiKey
        }

        guard let key = APIKeyManager.shared.getAPIKey(forProvider: provider.rawValue), !key.isEmpty else {
            throw EnhancementError.notConfigured
        }
        return key
    }

    private func chatPrompt(from messages: [ChatMessage]) -> String {
        let formattedMessages = messages.map { message in
            let label: String
            switch message.role {
            case "assistant":
                label = "assistant"
            case "user":
                label = "user"
            case "system":
                label = "system"
            default:
                label = "other"
            }
            return """
                <message role="\(label)">
                \(message.content)
                </message>
                """
        }
        .joined(separator: "\n\n")

        return """
            <conversation>
            \(formattedMessages)
            </conversation>
            """
    }
}
