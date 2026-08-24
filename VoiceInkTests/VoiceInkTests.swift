//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Foundation
import Testing
@testable import VoiceInk

struct VoiceInkTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func defaultTranscriptionLanguageIsAutomatic() {
        #expect(AppDefaults.defaultTranscriptionLanguage == "auto")
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

    @Test func defaultLocalTranscriptionModelIsMultilingual() {
        let model = TranscriptionModelRegistry.models.first {
            $0.name == StarterModeFactory.defaultTranscriptionModelName
        }

        #expect(model != nil)
        #expect(model?.isMultilingualModel == true)
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

    @Test func openAITranscriptionProviderUsesOpenAIWhisperEndpointDefaults() {
        let provider = OpenAIProvider()

        #expect(provider.modelProvider == .openAI)
        #expect(provider.providerKey == "OpenAI")
        #expect(provider.models.map(\.name) == ["whisper-1"])
        #expect(provider.models.first?.isMultilingualModel == true)
    }

    @Test func defaultRefinementPresetsHaveStableTitlesAndIDs() {
        let prompts = PromptTemplates.seedPrompts
        let titlesByID = Dictionary(uniqueKeysWithValues: prompts.map { ($0.id, $0.title) })

        #expect(titlesByID[PromptTemplates.fillerRemovalPromptId] == "去除贅詞")
        #expect(titlesByID[PromptTemplates.businessPolishPromptId] == "商業整理")
        #expect(titlesByID[PromptTemplates.defaultPromptId] == "智慧模式")
    }

    @Test func seedingAnyStarterModeIncludesAllRefinementPresets() {
        let result = StarterModePromptSeeder.ensurePrompts(for: [.clean], in: [])
        let seededIDs = Set(result.prompts.map(\.id))

        #expect(result.didChange)
        #expect(seededIDs.contains(PromptTemplates.fillerRemovalPromptId))
        #expect(seededIDs.contains(PromptTemplates.businessPolishPromptId))
        #expect(seededIDs.contains(PromptTemplates.defaultPromptId))
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

}
