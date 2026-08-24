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

}
