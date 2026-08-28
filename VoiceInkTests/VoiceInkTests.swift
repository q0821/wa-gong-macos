//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Foundation
import AppKit
import Carbon.HIToolbox
import SwiftData
import Testing
@testable import VoiceInk

struct VoiceInkTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func defaultTranscriptionLanguageIsAutomatic() {
        #expect(AppDefaults.defaultTranscriptionLanguage == "auto")
    }

    @Test func miniRecorderPositionDefaultsToTopAndPersistsBottomSelection() {
        let suiteName = "WaGongMiniRecorderPosition-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(MiniRecorderPosition.stored(defaults: defaults) == .top)

        defaults.set(MiniRecorderPosition.bottom.rawValue, forKey: RecorderDisplaySettingsKeys.miniRecorderPosition)

        #expect(MiniRecorderPosition.stored(defaults: defaults) == .bottom)
    }

    @Test func miniRecorderCoordinatesRespectVisibleScreenEdges() {
        let visibleFrame = NSRect(x: 0, y: 40, width: 1440, height: 860)
        let windowHeight: CGFloat = 430
        let padding: CGFloat = 24

        #expect(
            MiniRecorderPanel.yPosition(
                in: visibleFrame,
                windowHeight: windowHeight,
                padding: padding,
                position: .top
            ) == 446
        )
        #expect(
            MiniRecorderPanel.yPosition(
                in: visibleFrame,
                windowHeight: windowHeight,
                padding: padding,
                position: .bottom
            ) == 64
        )
    }

    @Test func privacyNotificationStacksBelowTopRecorderAndAboveBottomRecorder() {
        let visibleFrame = NSRect(x: 0, y: 40, width: 1440, height: 860)
        let notificationSize = NSSize(width: 452, height: 80)

        let topOrigin = PrivacyNotificationLayout.origin(
            in: visibleFrame,
            notificationSize: notificationSize,
            recorderHeight: 40,
            edgePadding: 24,
            spacing: 16,
            position: .top
        )
        let bottomOrigin = PrivacyNotificationLayout.origin(
            in: visibleFrame,
            notificationSize: notificationSize,
            recorderHeight: 40,
            edgePadding: 24,
            spacing: 16,
            position: .bottom
        )

        #expect(topOrigin == NSPoint(x: 494, y: 740))
        #expect(bottomOrigin == NSPoint(x: 494, y: 120))
    }

    @Test func explicitAppLanguageProvidesMatchingFloatingPanelLocale() {
        let systemLocale = Locale(identifier: "en_US")
        let traditionalChineseLocale = AppLanguagePreference.locale(
            for: "zh-Hant",
            systemLocale: systemLocale
        )

        #expect(traditionalChineseLocale.identifier == "zh-Hant")
        #expect(String(localized: "Transcribing", locale: traditionalChineseLocale) == "正在轉錄")
        #expect(String(localized: "Enhancing", locale: traditionalChineseLocale) == "正在潤飾")
        #expect(
            AppLanguagePreference.locale(
                for: AppLanguagePreference.systemValue,
                systemLocale: systemLocale
            ).identifier == systemLocale.identifier
        )
    }

    @Test func legacyEnglishDefaultMigratesToAutomatic() {
        let suiteName = "WaGongLanguageMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("en", forKey: "SelectedLanguage")

        AppDefaults.migrateLegacyTranscriptionLanguageIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: "SelectedLanguage") == "auto")
    }

    @Test func multilingualLanguagesUseTaiwanFirstOrdering() {
        let languages = LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper)

        #expect(
            LanguageDictionary.orderedLanguageCodes(from: languages).prefix(5)
                == ["auto", "zh-TW", "en", "ja", "ko"]
        )
    }

    @Test func taiwanChineseUsesWhisperChineseApiCode() {
        #expect(LanguageDictionary.whisperLanguageCode(for: "zh-TW") == "zh")
        #expect(LanguageDictionary.whisperLanguageCode(for: "auto") == "auto")
    }

    @Test func englishOnlyModelFallsBackToEnglish() {
        let model = WhisperModel(
            name: "test-english-only",
            displayName: "Test English",
            size: "1 MB",
            supportedLanguages: ["en": "English"],
            description: "Test model",
            speed: 1,
            accuracy: 1,
            ramUsage: 1
        )

        #expect(TranscriptionLanguageSupport.validLanguageOrFallback("zh-TW", for: model) == "en")
    }

    @Test func defaultLocalTranscriptionModelIsChineseCapableWhisper() {
        #expect(StarterModeFactory.defaultLocalTranscriptionModelName == "ggml-base")

        let model = TranscriptionModelRegistry.models.first {
            $0.name == StarterModeFactory.defaultLocalTranscriptionModelName
        }

        #expect(model != nil)
        #expect(model?.provider == .whisper)
        #expect(model?.supportedLanguages["zh-TW"] == "Chinese (Taiwan)")
    }

    @Test func defaultTranscriptionModelIsCloudFirst() {
        #expect(StarterModeFactory.defaultCloudTranscriptionProviderKey == "AssemblyAI")
        #expect(StarterModeFactory.defaultTranscriptionModelName == "universal-3-5-pro")

        let model = TranscriptionModelRegistry.models.first {
            $0.name == StarterModeFactory.defaultTranscriptionModelName
        }

        #expect(model?.provider == .assemblyAI)
        #expect(model?.supportsChinese == true)
    }

    @Test @MainActor func onboardingDefaultsToCloudTranscriptionSetup() {
        let suiteName = "WaGongCloudFirstOnboarding-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = OnboardingCoordinator(defaults: defaults)

        #expect(coordinator.transcriptionSetupKind == .cloud)
        #expect(coordinator.selectedOnboardingTranscriptionModel?.provider == .assemblyAI)
    }

    @Test func modelLanguageLabelsStateWhetherChineseIsSupported() {
        let base = TranscriptionModelRegistry.models.first { $0.name == "ggml-base" }
        let englishOnly = TranscriptionModelRegistry.models.first { $0.name == "ggml-base.en" }
        let europeanMultilingual = TranscriptionModelRegistry.models.first {
            $0.name == "parakeet-tdt-0.6b-v3"
        }

        #expect(base?.supportsChinese == true)
        #expect(base?.language == String(localized: "Multilingual, includes Chinese"))
        #expect(englishOnly?.supportsChinese == false)
        #expect(englishOnly?.language == String(localized: "English only"))
        #expect(europeanMultilingual?.supportsChinese == false)
        #expect(
            europeanMultilingual?.language == String(localized: "Multilingual, Chinese not supported")
        )
    }

    @Test func legacyRefineProviderNameMigratesToWaGong() {
        #expect(AIProvider(rawValue: "VoiceInk Refine") == .waGongRefine)
        #expect(AIProvider.waGongRefine.rawValue == "Wa-Gong Refine")
    }

    @Test func trustIsFinalOnboardingStageWithoutLicenseStep() {
        #expect(OnboardingStage.allCases.last == .trust)
        #expect(!OnboardingStage.allCases.contains { $0.rawValue == "license" })
    }

    @Test @MainActor func removedLicenseStageResumesAtTrust() {
        let suiteName = "WaGongOnboardingMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("license", forKey: OnboardingStorageKeys.stage)

        let coordinator = OnboardingCoordinator(defaults: defaults)

        #expect(coordinator.stage == .trust)
    }

    @Test func existingStarterModesMigrateToCloudFirstTranscription() {
        let starterConfig = ModeConfig(
            id: StarterModeCatalog.templates[0].id,
            name: "Dictation",
            isAIEnhancementEnabled: false,
            selectedTranscriptionModelName: ModeDataMigration.legacyDefaultTranscriptionModelName
        )
        let customConfig = ModeConfig(
            name: "Custom",
            isAIEnhancementEnabled: false,
            selectedTranscriptionModelName: ModeDataMigration.legacyDefaultTranscriptionModelName
        )

        #expect(
            ModeDataMigration.migratedStarterTranscriptionModelName(for: starterConfig)
                == StarterModeFactory.defaultTranscriptionModelName
        )
        let previousLocalDefaultConfig = ModeConfig(
            id: StarterModeCatalog.templates[0].id,
            name: "Dictation",
            isAIEnhancementEnabled: false,
            selectedTranscriptionModelName: StarterModeFactory.defaultLocalTranscriptionModelName
        )
        #expect(
            ModeDataMigration.migratedStarterTranscriptionModelName(for: previousLocalDefaultConfig)
                == StarterModeFactory.defaultTranscriptionModelName
        )
        #expect(
            ModeDataMigration.migratedStarterTranscriptionModelName(for: customConfig)
                == ModeDataMigration.legacyDefaultTranscriptionModelName
        )
    }

    @Test func llmContextExcludesClipboardWhileKeepingEnabledContexts() {
        let blocks = AIEnhancementContextPolicy.contextBlocks(
            selectedText: "selected-secret",
            clipboardText: "clipboard-secret",
            screenText: "screen-secret",
            useSelectedText: true,
            useScreenCapture: true
        )
        let context = blocks.joined(separator: "\n")

        #expect(context.contains("selected-secret"))
        #expect(context.contains("screen-secret"))
        #expect(!context.contains("clipboard-secret"))
        #expect(!context.contains("CLIPBOARD_CONTEXT"))
    }

    @Test func modeConfigurationCannotEnableClipboardContext() {
        let mode = ModeConfig(
            name: "Privacy Test",
            isAIEnhancementEnabled: true,
            useClipboardContext: true
        )

        #expect(mode.useClipboardContext == false)
    }

    @Test func openAITranscriptionProviderUsesOpenAIEndpointAndDefaultsToMiniTranscribe() {
        let provider = OpenAIProvider()

        #expect(OpenAIProvider.apiBaseURL.absoluteString == "https://api.openai.com")
        #expect(
            OpenAIProvider.apiBaseURL.appendingPathComponent("v1/models").absoluteString
                == "https://api.openai.com/v1/models"
        )
        #expect(
            OpenAIProvider.apiBaseURL.appendingPathComponent("v1/audio/transcriptions").absoluteString
                == "https://api.openai.com/v1/audio/transcriptions"
        )
        #expect(provider.modelProvider == .openAI)
        #expect(provider.providerKey == "OpenAI")
        #expect(
            provider.models.map(\.name) == [
                "gpt-4o-mini-transcribe",
                "gpt-transcribe",
                "gpt-4o-transcribe",
                "gpt-4o-transcribe-diarize",
                "whisper-1",
            ]
        )
        #expect(provider.models.first?.name == "gpt-4o-mini-transcribe")
        #expect(provider.models.first?.isMultilingualModel == true)
    }

    @Test func openAIDiarizationUsesRequiredRequestFieldsAndReturnsSpeakerLabels() throws {
        let request = try OpenAITranscriptionService.makeDiarizedRequest(
            audioData: Data("audio".utf8),
            fileName: "recording.wav",
            apiKey: "test-key",
            language: "zh"
        )
        let body = try #require(request.httpBody)
        let multipart = try #require(String(data: body, encoding: .utf8))

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(multipart.contains("name=\"model\"\r\n\r\ngpt-4o-transcribe-diarize"))
        #expect(multipart.contains("name=\"response_format\"\r\n\r\ndiarized_json"))
        #expect(multipart.contains("name=\"chunking_strategy\"\r\n\r\nauto"))
        #expect(multipart.contains("name=\"language\"\r\n\r\nzh"))

        let response = Data(
            """
            {"segments":[
              {"speaker":"A","text":"你好","start":0,"end":1},
              {"speaker":"A","text":"歡迎使用聲筆","start":1,"end":2},
              {"speaker":"B","text":"謝謝","start":2,"end":3}
            ]}
            """.utf8
        )

        #expect(
            try OpenAITranscriptionService.speakerLabeledText(from: response)
                == "A: 你好 歡迎使用聲筆\nB: 謝謝"
        )
    }

    @Test func geminiDefaultsToWorkingGenerateContentModel() {
        let provider = GeminiProvider()

        #expect(provider.models.map(\.name) == ["gemini-3.5-flash-lite"])
        #expect(AIProvider.gemini.defaultModel == "gemini-3.6-flash")
        #expect(AIProvider.gemini.availableModels.first == "gemini-3.6-flash")
        #expect(!AIProvider.gemini.availableModels.contains("gemini-3.7-flash"))
    }

    @Test func geminiTranscriptionRequestPreservesSpokenLanguageAndMinimizesThinking() throws {
        let request = try GeminiTranscriptionService.makeRequest(
            audioData: Data([0x52, 0x49, 0x46, 0x46]),
            apiKey: "test-key",
            model: "gemini-3.5-flash-lite",
            language: nil,
            customVocabulary: ["蓋婭科技"]
        )
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let generationConfig = try #require(json["generationConfig"] as? [String: Any])
        let thinkingConfig = try #require(generationConfig["thinkingConfig"] as? [String: Any])
        let contents = try #require(json["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let prompt = try #require(parts.first?["text"] as? String)

        #expect(thinkingConfig["thinkingLevel"] as? String == "minimal")
        #expect(prompt.contains("Do not translate"))
        #expect(prompt.contains("Traditional Chinese as used in Taiwan"))
        #expect(prompt.contains("蓋婭科技"))
    }

    @Test func unavailableGeminiModelSelectionsMigrateToWorkingModel() {
        let suiteName = "WaGongGeminiModelMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("gemini-3.6-flash", forKey: "CurrentTranscriptionModel")
        defaults.set("gemini-3.7-flash", forKey: "GeminiSelectedModel")

        AppDefaults.migrateUnavailableGeminiModelIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: "CurrentTranscriptionModel") == "gemini-3.5-flash-lite")
        #expect(defaults.string(forKey: "GeminiSelectedModel") == "gemini-3.6-flash")
    }

    @Test func unavailableGeminiModelsMigrateInsideEveryModeConfiguration() {
        var config = ModeConfig(
            name: "Gemini Migration",
            isAIEnhancementEnabled: true,
            selectedTranscriptionModelName: "gemini-3.6-flash",
            selectedAIProvider: AIProvider.gemini.rawValue,
            selectedAIModel: "gemini-3.7-flash"
        )

        config.selectedTranscriptionModelName = AppDefaults.migratedGeminiTranscriptionModelName(
            config.selectedTranscriptionModelName
        )
        config.selectedAIModel = AppDefaults.migratedGeminiAIModelName(config.selectedAIModel)

        #expect(config.selectedTranscriptionModelName == "gemini-3.5-flash-lite")
        #expect(config.selectedAIModel == "gemini-3.6-flash")
    }

    @Test func defaultRefinementPresetsHaveStableTitlesAndIDs() {
        let prompts = PromptTemplates.seedPrompts
        let titlesByID = Dictionary(uniqueKeysWithValues: prompts.map { ($0.id, $0.title) })

        #expect(titlesByID[PromptTemplates.defaultPromptId] == "智慧模式")
        #expect(titlesByID[PromptTemplates.chatPromptId] == String(localized: "Chat"))
        #expect(titlesByID[PromptTemplates.emailPromptId] == String(localized: "Email"))
        #expect(titlesByID[PromptTemplates.rewritePromptId] == String(localized: "Rewrite"))
        #expect(titlesByID[PromptTemplates.assistantPromptId] == String(localized: "Assistant"))
    }

    @Test func seedingStarterModesExcludesRetiredDuplicatePrompts() {
        let result = StarterModePromptSeeder.ensurePrompts(for: [.clean], in: [])
        let seededIDs = Set(result.prompts.map(\.id))

        #expect(result.didChange)
        #expect(seededIDs.contains(PromptTemplates.defaultPromptId))
        #expect(seededIDs.contains(PromptTemplates.chatPromptId))
        #expect(!seededIDs.contains(PromptTemplates.fillerRemovalPromptId))
        #expect(!seededIDs.contains(PromptTemplates.businessPolishPromptId))
    }

    @Test func unchangedRetiredDuplicatePromptsAreRemovedButCustomizedOnesRemain() {
        let unchanged = PromptTemplates.legacyFillerRemovalPrompt
        let customized = CustomPrompt(
            id: PromptTemplates.businessPolishPromptId,
            title: "我的商業提示詞",
            promptText: "保留這份自訂內容",
            useSystemInstructions: true
        )

        let result = StarterModePromptSeeder.ensurePrompts(
            for: [],
            in: [unchanged, customized]
        )

        #expect(result.didChange)
        #expect(!result.prompts.contains { $0.id == unchanged.id })
        #expect(result.prompts.contains(customized))
    }

    @Test func legacyEnglishStarterModeNamesUseLocalizedTitlesWithoutRenamingCustomNames() {
        let dictationTemplate = StarterModeCatalog.templates.first { $0.kind == .clean }!
        let legacyStarter = ModeConfig(
            id: dictationTemplate.id,
            name: "Dictation",
            isAIEnhancementEnabled: false
        )
        let renamedStarter = ModeConfig(
            id: dictationTemplate.id,
            name: "我的聽寫",
            isAIEnhancementEnabled: false
        )

        #expect(
            ModeDataMigration.migratedStarterModeName(for: legacyStarter)
                == String(localized: "Dictation")
        )
        #expect(ModeDataMigration.migratedStarterModeName(for: renamedStarter) == "我的聽寫")
    }

    @Test func legacyDefaultPromptGetsSmartModeTitleWithoutLosingCustomText() {
        let legacyPrompt = CustomPrompt(
            id: PromptTemplates.defaultPromptId,
            title: "Default",
            promptText: "Keep this user text",
            useSystemInstructions: false
        )

        let result = StarterModePromptSeeder.ensurePrompts(for: [], in: [legacyPrompt])
        let migratedPrompt = result.prompts.first { $0.id == PromptTemplates.defaultPromptId }

        #expect(migratedPrompt?.title == "智慧模式")
        #expect(migratedPrompt?.promptText == "Keep this user text")
        #expect(migratedPrompt?.useSystemInstructions == false)
    }

    @Test func enhancementPromptsPreserveSourceLanguageAndTaiwanChinese() {
        #expect(AIPrompts.enhancementSystemTemplate.contains("Keep the output in the same language"))
        #expect(AIPrompts.enhancementSystemTemplate.contains("Traditional Chinese as used in Taiwan"))

        let directPrompts = PromptTemplates.seedPrompts.filter { !$0.useSystemInstructions }
        #expect(!directPrompts.isEmpty)
        #expect(
            directPrompts.allSatisfy {
                $0.promptText.contains("Traditional Chinese as used in Taiwan")
            }
        )
    }

    @Test func unchangedLegacySmartPromptMigratesWithoutChangingItsStableID() {
        let legacyPrompt = CustomPrompt(
            id: PromptTemplates.defaultPromptId,
            title: "智慧模式",
            promptText: PromptTemplates.legacyDefaultPromptText,
            useSystemInstructions: true
        )

        let result = StarterModePromptSeeder.ensurePrompts(for: [], in: [legacyPrompt])
        let migratedPrompt = result.prompts.first { $0.id == PromptTemplates.defaultPromptId }

        #expect(result.didChange)
        #expect(migratedPrompt?.id == PromptTemplates.defaultPromptId)
        #expect(migratedPrompt?.promptText == PromptTemplates.defaultPrompt.promptText)
    }

    @Test func olderGeneralPurposeSmartPromptAlsoMigratesSafely() {
        let legacyPrompt = CustomPrompt(
            id: PromptTemplates.defaultPromptId,
            title: "智慧模式",
            promptText: PromptTemplates.legacyGeneralPurposePromptText,
            useSystemInstructions: true
        )

        let result = StarterModePromptSeeder.ensurePrompts(for: [], in: [legacyPrompt])
        let migratedPrompt = result.prompts.first { $0.id == PromptTemplates.defaultPromptId }

        #expect(result.didChange)
        #expect(migratedPrompt?.promptText == PromptTemplates.defaultPrompt.promptText)
    }

    @Test func unchangedDirectPromptsGainTaiwanLanguageRules() {
        let legacyRewrite = CustomPrompt(
            id: PromptTemplates.rewritePromptId,
            title: "Rewrite",
            promptText: PromptTemplates.legacyRewritePromptText,
            useSystemInstructions: false
        )
        let legacyAssistant = CustomPrompt(
            id: PromptTemplates.assistantPromptId,
            title: "Assistant",
            promptText: PromptTemplates.legacyAssistantPromptText,
            useSystemInstructions: false
        )

        let result = StarterModePromptSeeder.ensurePrompts(
            for: [],
            in: [legacyRewrite, legacyAssistant]
        )

        #expect(result.didChange)
        #expect(
            result.prompts.first { $0.id == PromptTemplates.rewritePromptId }?.promptText
                == PromptTemplates.template(for: PromptTemplates.rewritePromptId)?.promptText
        )
        #expect(
            result.prompts.first { $0.id == PromptTemplates.assistantPromptId }?.promptText
                == PromptTemplates.template(for: PromptTemplates.assistantPromptId)?.promptText
        )
    }

    @Test func customizedBuiltInPromptIsNotOverwrittenByMigration() {
        let customizedPrompt = CustomPrompt(
            id: PromptTemplates.defaultPromptId,
            title: "我的智慧模式",
            promptText: "保留我的自訂內容",
            useSystemInstructions: false
        )

        let result = StarterModePromptSeeder.ensurePrompts(for: [], in: [customizedPrompt])
        let preservedPrompt = result.prompts.first { $0.id == PromptTemplates.defaultPromptId }

        #expect(preservedPrompt == customizedPrompt)
    }

    @Test func promptTemplatesIdentifyBuiltInPromptsForDeleteProtection() {
        #expect(PromptTemplates.isBuiltInPrompt(id: PromptTemplates.defaultPromptId))
        #expect(!PromptTemplates.isBuiltInPrompt(id: UUID()))
    }

    @Test func localWhisperContextIncludesCustomVocabularyWithoutReplacingPrompt() {
        let context = TranscriptionRequestContext(
            language: "auto",
            prompt: "Use Taiwan wording."
        )

        let enrichedContext = context.appendingCustomVocabulary(["聲筆", "Wa-Gong"])

        #expect(enrichedContext.language == "auto")
        #expect(enrichedContext.prompt?.contains("Use Taiwan wording.") == true)
        #expect(enrichedContext.prompt?.contains("<CUSTOM_VOCABULARY>") == true)
        #expect(enrichedContext.prompt?.contains("聲筆, Wa-Gong") == true)
    }

    @Test func shortcutValidatorRejectsPlainTypingKey() {
        let shortcut = Shortcut.key(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [])

        #expect(
            ShortcutValidator.validationError(for: shortcut, action: .primaryRecording)
                == .plainKeyRequiresModifier
        )
    }

    @Test func shortcutValidatorAllowsFunctionKeyWithoutModifier() {
        let shortcut = Shortcut.key(keyCode: UInt16(kVK_F6), modifierFlags: [])

        #expect(ShortcutValidator.validationError(for: shortcut, action: .primaryRecording) == nil)
    }

    @Test func wordReplacementPrefersLongerTermsAndRespectsWordBoundaries() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WordReplacement.self, configurations: configuration)
        let context = ModelContext(container)
        context.insert(WordReplacement(originalText: "Voice Ink, Voice Ink Pro", replacementText: "聲筆"))
        try context.save()

        let result = WordReplacementService.shared.applyReplacements(
            to: "Voice Ink Pro Voice Ink Voice Inkish",
            using: context
        )

        #expect(result == "聲筆 聲筆 Voice Inkish")
    }

    @Test func privacyRequestSummaryRedactsURLQueryItems() {
        let summary = PrivacyRequestSummary(
            destination: "https://example.com/v1/chat?api_key=sk-test",
            modelName: "custom-model",
            dataTypes: [.transcript]
        )

        #expect(summary.destination == "https://example.com/v1/chat")
        let displayText = summary.displayText(locale: Locale(identifier: "en"))
        #expect(!displayText.contains("api_key"))
        #expect(!displayText.contains("sk-test"))
    }

    @Test func privacyRequestSummaryUsesOpenAITranscriptionDestination() {
        #expect(
            PrivacyRequestSummary.transcriptionDestination(for: .openAI)
                == "https://api.openai.com/v1/audio/transcriptions"
        )
        #expect(PrivacyRequestSummary.transcriptionDestination(for: .whisper) == nil)
    }

    @Test func anthropicUsesClaudeForModelBrandAndAnthropicForAPIService() {
        #expect(AIProvider.anthropic.rawValue == "Anthropic")
        #expect(AIProvider.anthropic.displayName == "Claude")
        #expect(AIProvider.anthropic.apiProviderName == "Anthropic")

        let descriptor = ProviderDescriptor(
            displayName: AIProvider.anthropic.displayName,
            providerKey: AIProvider.anthropic.rawValue,
            aiProvider: .anthropic,
            cloudProvider: nil
        )

        #expect(descriptor.displayName == "Claude")
        #expect(descriptor.apiDisplayName == "Anthropic")
    }

    @Test @MainActor func canceledDeliveryDoesNotPasteOrAutoSend() async {
        var isCanceled = false
        var didPaste = false
        var didAutoSend = false
        let transcription = Transcription(
            text: "transcript",
            duration: 1,
            transcriptionStatus: .completed
        )
        let output = OutputRuntimeConfiguration(
            mode: nil,
            outputMode: .paste,
            autoSendKey: .enter,
            customCommand: nil
        )
        let delivery = TranscriptionDelivery()

        await delivery.deliver(
            TranscriptionDelivery.Request(
                transcription: transcription,
                text: "transcript",
                output: output,
                responseConfig: nil,
                responseError: nil,
                isAssistantFollowUp: false,
                isCanceled: { isCanceled }
            ),
            actions: TranscriptionDelivery.Actions(
                setState: { _ in },
                dismiss: {
                    isCanceled = true
                },
                sendFollowUp: { _, _ in },
                showResponse: { _, _ in },
                failResponse: { _ in },
                pasteAtCursor: { _, _ in
                    didPaste = true
                    return .commandPosted
                },
                autoSend: { _ in
                    didAutoSend = true
                }
            )
        )

        #expect(!didPaste)
        #expect(!didAutoSend)
    }

}

@Suite
struct PrivacyRequestSummaryLocalizationTests {
    @Test func showsDestinationAndDataKindsWithoutPayload() {
        let summary = PrivacyRequestSummary(
            destination: "https://api.openai.com/v1/chat/completions",
            modelName: "gpt-4.1-mini",
            dataTypes: [.transcript, .prompt, .selectedText]
        )

        let displayText = summary.displayText(locale: Locale(identifier: "en"))

        #expect(displayText.contains("api.openai.com/v1/chat/completions"))
        #expect(displayText.contains("gpt-4.1-mini"))
        #expect(displayText.contains("Transcript"))
        #expect(displayText.contains("Selected text"))
        #expect(!displayText.contains("clipboard-secret"))
        #expect(!displayText.contains("sk-test"))
    }

    @Test func usesTraditionalChineseAppLanguage() {
        let summary = PrivacyRequestSummary(
            destination: "https://api.openai.com/v1/audio/transcriptions",
            modelName: "gpt-4o-transcribe",
            dataTypes: [.audio]
        )

        let displayText = summary.displayText(locale: Locale(identifier: "zh-Hant"))

        #expect(displayText.contains("外部 AI 傳送提示"))
        #expect(displayText.contains("傳送位置：https://api.openai.com/v1/audio/transcriptions"))
        #expect(displayText.contains("模型：gpt-4o-transcribe"))
        #expect(displayText.contains("傳送內容：音訊"))
    }
}
