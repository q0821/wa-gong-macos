import Testing
@testable import VoiceInk

struct LocalSpeechModelFilterTests {
    @Test func chineseFilterUsesLanguageCapabilitiesRatherThanMultilingualLabel() throws {
        let registry = TranscriptionModelRegistry.models
        let tea = TranscriptionModelRegistry.teaModel
        let english = try #require(registry.first { $0.name == "ggml-base.en" })
        let european = try #require(registry.first { $0.name == "parakeet-tdt-0.6b-v3" })
        let chinese = try #require(registry.first { $0.name == "ggml-base" })
        #expect(european.isMultilingualModel)
        #expect(LocalSpeechModelFilter.chinese.includes(tea, isInstalled: false))
        #expect(LocalSpeechModelFilter.chinese.includes(chinese, isInstalled: false))
        #expect(!LocalSpeechModelFilter.chinese.includes(english, isInstalled: true))
        #expect(!LocalSpeechModelFilter.chinese.includes(european, isInstalled: true))
        #expect(LocalSpeechModelFilter.all.includes(english, isInstalled: false))
        #expect(LocalSpeechModelFilter.all.includes(european, isInstalled: false))
    }

    @Test func installedFilterStillShowsInstalledEnglishModels() throws {
        let english = try #require(TranscriptionModelRegistry.models.first { $0.name == "ggml-base.en" })
        #expect(LocalSpeechModelFilter.installed.includes(english, isInstalled: true))
        #expect(!LocalSpeechModelFilter.installed.includes(english, isInstalled: false))
        #expect(!LocalSpeechModelFilter.installed.includes(TranscriptionModelRegistry.teaModel, isInstalled: false))
    }

    @Test func storedFilterRestoresSelectionAndFallsBackConservatively() {
        #expect(LocalSpeechModelFilter(storedValue: "") == .chinese)
        #expect(LocalSpeechModelFilter(storedValue: "unknown") == .chinese)
        #expect(LocalSpeechModelFilter(storedValue: "installed") == .installed)
        #expect(LocalSpeechModelFilter(storedValue: "all") == .all)
    }
}
