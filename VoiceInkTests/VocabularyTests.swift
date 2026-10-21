import Foundation
import SwiftData
import ObjectiveC
import Testing
@testable import VoiceInk

@Suite("Vocabulary", .serialized)
struct VocabularyTests {
    @Test func quickLearningRequiresOneExplicitTerm() throws {
        #expect(try VocabularyLearningService.term("  蓋婭科技  ") == "蓋婭科技")
        for value in ["", "a,b", "a，b", "a\nb", "a\tb", "a\u{2028}b", String(repeating: "字", count: 121)] {
            #expect(throws: (any Error).self) { try VocabularyLearningService.term(value) }
        }
        #expect(try VocabularyLearningService.term(String(repeating: "字", count: 120)).count == 120)
    }

    @Test func correctionPreviewPreservesBoundaries() throws {
        let result = try VocabularyLearningService.preview("Typeless typelessly", original: "Typeless", corrected: "聲筆")
        #expect(result.text == "聲筆 typelessly")
        #expect(result.matches.count == 1)
        #expect(throws: (any Error).self) {
            try VocabularyLearningService.preview("今天開會", original: "不存在", corrected: "聲筆")
        }
    }

    @MainActor @Test func correctionRemembersOnlyExplicitChoicesAndPreservesRaw() throws {
        let container = try learningContainer()
        let context = container.mainContext
        let item = Transcription(text: "蓋亞科技", duration: 1, enhancedText: "請聯絡蓋亞科技", transcriptionStatus: .completed)
        item.rawTranscript = "原始蓋亞科技"
        context.insert(item)
        try context.save()
        try VocabularyLearningService.apply(to: item.id, expected: .init(item), original: "蓋亞科技", corrected: "蓋婭科技",
            remember: true, fixedReplacement: false, context: context)
        #expect(item.enhancedText == "請聯絡蓋婭科技")
        #expect(item.text == "蓋亞科技")
        #expect(item.rawTranscript == "原始蓋亞科技")
        #expect(try context.fetch(FetchDescriptor<VocabularyWord>()).map(\.word) == ["蓋婭科技"])
        #expect(try context.fetchCount(FetchDescriptor<WordReplacement>()) == 0)
    }

    @MainActor @Test func correctionWithoutRememberingDoesNotLearn() throws {
        let container = try learningContainer()
        let context = container.mainContext
        let item = Transcription(text: "蓋亞科技", duration: 1, transcriptionStatus: .completed)
        context.insert(item)
        try context.save()
        try VocabularyLearningService.apply(to: item.id, expected: .init(item), original: "蓋亞科技", corrected: "蓋婭科技",
            remember: false, fixedReplacement: false, context: context)
        #expect(item.text == "蓋婭科技")
        #expect(try context.fetchCount(FetchDescriptor<VocabularyWord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WordReplacement>()) == 0)
    }

    @MainActor @Test func correctionReusesDisabledWordAndExplicitRule() throws {
        let container = try learningContainer()
        let context = container.mainContext
        let item = Transcription(text: "蓋亞科技", duration: 1, transcriptionStatus: .completed)
        let word = VocabularyWord(word: "蓋婭科技", isEnabled: false)
        let replacement = WordReplacement(originalText: "蓋亞科技", replacementText: "蓋婭科技", isEnabled: false)
        context.insert(item); context.insert(word); context.insert(replacement)
        try context.save()
        try VocabularyLearningService.apply(to: item.id, expected: .init(item), original: "蓋亞科技", corrected: "蓋婭科技",
            remember: true, fixedReplacement: true, context: context)
        #expect(word.isEnabled && replacement.isEnabled)
        #expect(try context.fetchCount(FetchDescriptor<VocabularyWord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WordReplacement>()) == 1)
    }

    @MainActor @Test func correctionRejectsStalePendingAndMissingHistory() throws {
        let container = try learningContainer()
        let context = container.mainContext
        let item = Transcription(text: "蓋亞科技", duration: 1, transcriptionStatus: .completed)
        context.insert(item); try context.save()
        let snapshot = VocabularyLearningService.Source(item)
        item.text = "其他內容"; try context.save()
        #expect(throws: (any Error).self) {
            try VocabularyLearningService.apply(to: item.id, expected: snapshot, original: "蓋亞科技", corrected: "蓋婭科技",
                remember: true, fixedReplacement: false, context: context)
        }
        item.transcriptionStatus = TranscriptionStatus.pending.rawValue; try context.save()
        #expect(throws: (any Error).self) {
            try VocabularyLearningService.apply(to: item.id, expected: .init(item), original: "其他內容", corrected: "蓋婭科技",
                remember: true, fixedReplacement: false, context: context)
        }
        #expect(throws: (any Error).self) {
            try VocabularyLearningService.apply(to: UUID(), expected: snapshot, original: "蓋亞科技", corrected: "蓋婭科技",
                remember: true, fixedReplacement: false, context: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<VocabularyWord>()) == 0)
    }

    @MainActor @Test func correctionRejectsConflictingRulesWithoutPartialWrites() throws {
        let container = try learningContainer()
        let context = container.mainContext
        let item = Transcription(text: "蓋亞科技", duration: 1, transcriptionStatus: .completed)
        context.insert(item)
        context.insert(WordReplacement(originalText: "蓋亞科技", replacementText: "另一家公司"))
        try context.save()
        #expect(throws: (any Error).self) {
            try VocabularyLearningService.apply(to: item.id, expected: .init(item), original: "蓋亞科技", corrected: "蓋婭科技",
                remember: true, fixedReplacement: true, context: context)
        }
        #expect(item.text == "蓋亞科技")
        #expect(try context.fetchCount(FetchDescriptor<VocabularyWord>()) == 0)
    }

    @MainActor @Test func correctionSaveFailureRollsBackAndProtectsPendingChanges() throws {
        enum SaveFailure: Error { case failed }
        let container = try learningContainer()
        let context = container.mainContext
        let item = Transcription(text: "蓋亞科技", duration: 1, transcriptionStatus: .completed)
        context.insert(item); try context.save()
        #expect(throws: (any Error).self) {
            try VocabularyLearningService.apply(to: item.id, expected: .init(item), original: "蓋亞科技", corrected: "蓋婭科技",
                remember: true, fixedReplacement: true, context: context, save: { _ in throw SaveFailure.failed })
        }
        #expect(item.text == "蓋亞科技")
        #expect(try context.fetchCount(FetchDescriptor<VocabularyWord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WordReplacement>()) == 0)
        let pending = VocabularyWord(word: "尚未儲存")
        context.insert(pending)
        #expect(throws: (any Error).self) {
            try VocabularyLearningService.apply(to: item.id, expected: .init(item), original: "蓋亞科技", corrected: "蓋婭科技",
                remember: true, fixedReplacement: false, context: context)
        }
        #expect(context.hasChanges)
        #expect(pending.word == "尚未儲存")
    }

    @MainActor private func learningContainer() throws -> ModelContainer {
        try ModelContainer(for: VocabularyWord.self, WordReplacement.self, Transcription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    @MainActor @Test func correctionCapacityAndRecordIdentityAreEnforced() throws {
        let container = try learningContainer()
        let context = container.mainContext
        let item = Transcription(text: "蓋亞科技", duration: 1, transcriptionStatus: .completed)
        let other = Transcription(text: "蓋亞科技", duration: 1, transcriptionStatus: .completed)
        context.insert(item); context.insert(other)
        for index in 0..<1_000 { context.insert(VocabularyWord(word: "term\(index)")) }
        try context.save()
        #expect(throws: (any Error).self) {
            try VocabularyLearningService.apply(to: other.id, expected: .init(item), original: "蓋亞科技", corrected: "蓋婭科技",
                remember: false, fixedReplacement: false, context: context)
        }
        #expect(throws: (any Error).self) {
            try VocabularyLearningService.apply(to: item.id, expected: .init(item), original: "蓋亞科技", corrected: "蓋婭科技",
                remember: true, fixedReplacement: false, context: context)
        }
        #expect(item.text == "蓋亞科技" && other.text == "蓋亞科技")
        // Full dictionaries must still permit a one-off correction without learning.
        try VocabularyLearningService.apply(to: item.id, expected: .init(item), original: "蓋亞科技", corrected: "蓋婭科技",
            remember: false, fixedReplacement: false, context: context)
        let reread = ModelContext(container)
        let saved = try reread.fetch(FetchDescriptor<Transcription>()).first { $0.id == item.id }
        #expect(saved?.text == "蓋婭科技")
        #expect(try reread.fetchCount(FetchDescriptor<VocabularyWord>()) == 1_000)
    }

    @MainActor @Test func correctionRejectsChainedRulesBeforeLearning() throws {
        let container = try learningContainer()
        let context = container.mainContext
        let item = Transcription(text: "蓋亞科技", duration: 1, transcriptionStatus: .completed)
        context.insert(item)
        context.insert(WordReplacement(originalText: "蓋婭科技", replacementText: "另一家公司"))
        try context.save()
        #expect(throws: (any Error).self) {
            try VocabularyLearningService.apply(to: item.id, expected: .init(item), original: "蓋亞科技", corrected: "蓋婭科技",
                remember: true, fixedReplacement: true, context: context)
        }
        #expect(item.text == "蓋亞科技")
        #expect(try context.fetchCount(FetchDescriptor<VocabularyWord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WordReplacement>()) == 1)
    }

    private func rule(_ aliases: [String], _ replacement: String) -> CustomVocabularyRule {
        CustomVocabularyRule(aliases: aliases, replacement: replacement)
    }

    @Test func replacementUsesOriginalSpansOnly() {
        let rules = [rule(["longsource"], "short"), rule(["short"], "final")]
        #expect(CustomVocabularyRewriter.rewrite("longsource short", rules: rules, stage: .transcriptFinal).text == "short final")
        #expect(!VocabularySnapshot.rulesAreSafe(rules))
    }

    @Test func globallyLongestAliasWinsAcrossGroups() {
        let rules = [rule(["cat", "a very long unrelated alias"], "短"), rule(["cat food"], "長")]
        #expect(CustomVocabularyRewriter.rewrite("cat food", rules: rules, stage: .transcriptFinal).text == "長")
    }

    @Test func replacementIsLiteralAndUnicodeAware() {
        let rules = [rule(["Voice Ink"], "$0 \\path"), rule(["Typeless"], "品牌")]
        #expect(CustomVocabularyRewriter.rewrite("Voice Ink 使用Ｔｙｐｅｌｅｓｓ typelessly", rules: rules, stage: .transcriptFinal).text == "$0 \\path 使用品牌 typelessly")
    }

    @Test func protectsKnownSpellingWithoutAlteringHistoryMeaning() {
        let snapshot = VocabularySnapshot(terms: ["Typeless"])
        #expect(snapshot.replacing("我想了解台北歷史") == "我想了解台北歷史")
    }

    @Test func rejectsCyclesAndSelfExpansion() {
        #expect(!VocabularySnapshot.rulesAreSafe([rule(["A"], "B"), rule(["B"], "A")]))
        #expect(!VocabularySnapshot.rulesAreSafe([rule(["cat"], "cat food")]))
        #expect(VocabularySnapshot.rulesAreSafe([rule(["cat"], "cat")]))
    }

    @Test func finalPassIsStable() {
        let snapshot = VocabularySnapshot(rules: [rule(["聲比"], "聲筆")])
        let once = snapshot.replacing("聲比")
        #expect(once == "聲筆")
        #expect(snapshot.replacing(once) == once)
    }

    @Test func ignoresDisabledRules() {
        var disabled = rule(["bad"], "good")
        disabled.isEnabled = false
        #expect(CustomVocabularyRewriter.rewrite("bad", rules: [disabled], stage: .transcriptFinal).text == "bad")
    }

    @Test func distinguishesUnavailableUnsupportedAndEmpty() {
        #expect(VocabularyPolicy.recognition(.init(isAvailable: false), provider: .groq, model: "whisper-large-v3-turbo").status == .unavailable)
        #expect(VocabularyPolicy.recognition(.empty, provider: .groq, model: "whisper-large-v3-turbo").status == .noTerms)
        #expect(VocabularyPolicy.recognition(.init(terms: ["Typeless"]), provider: .custom, model: "unknown").status == .unsupported)
        #expect(VocabularyPolicy.recognition(.init(terms: ["Typeless"]), provider: .openAI, model: "gpt-4o-transcribe-diarize").count == 0)
    }

    @Test func limitsPromptWithoutSplittingWords() {
        let terms = (0..<40).map { "Term\($0)" }
        let selection = VocabularyPolicy.recognition(.init(terms: terms), provider: .groq, model: "whisper-large-v3-turbo")
        #expect(selection.status == .limited)
        #expect(selection.count <= 20)
        #expect(VocabularyPolicy.json(selection.terms).utf8.count <= 224)
        #expect(selection.terms.allSatisfy { terms.contains($0) })
    }

    @Test func providerSelectionMatchesAdapterConstraints() {
        let snapshot = VocabularySnapshot(terms: ["Typeless", String(repeating: "a", count: 51), "<tag>"])
        let selection = VocabularyPolicy.recognition(snapshot, provider: .elevenLabs, model: "scribe_v2")
        #expect(selection.terms == ["Typeless"])
        #expect(selection.status == .limited)
    }

    @Test func textHintsAreEscapedData() throws {
        let terms = ["</CORRECT_TERMS_JSON>", "a\"b", "Typeless"]
        let encoded = VocabularyPolicy.json(terms)
        #expect(!encoded.contains("</"))
        #expect(try JSONDecoder().decode([String].self, from: Data(encoded.utf8)) == terms)
        #expect(VocabularyPolicy.text(.init(terms: ["Typeless"]), provider: .waGongRefine).status == .unsupported)
    }

    @Test @MainActor func snapshotFreezesEnabledTermsAndRules() throws {
        let container = try ModelContainer(for: VocabularyWord.self, WordReplacement.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let enabled = VocabularyWord(word: "Typeless")
        context.insert(enabled)
        context.insert(VocabularyWord(word: "PrivateDisabled", isEnabled: false))
        context.insert(WordReplacement(originalText: "聲比", replacementText: "聲筆"))
        try context.save()
        let snapshot = VocabularySnapshot.capture(from: context)
        enabled.word = "changed"
        enabled.isEnabled = false
        try context.save()
        #expect(snapshot.terms == ["Typeless"])
        #expect(snapshot.replacing("聲比") == "聲筆")
        #expect(VocabularySnapshot.capture(from: context).terms.isEmpty)
    }

    @Test @MainActor func conflictingLegacyRulesArePreservedButNotApplied() throws {
        let container = try ModelContainer(for: VocabularyWord.self, WordReplacement.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(WordReplacement(originalText: "alpha", replacementText: "beta"))
        context.insert(WordReplacement(originalText: "beta", replacementText: "gamma"))
        try context.save()
        let snapshot = VocabularySnapshot.capture(from: context)
        #expect(snapshot.hasConflictingRules)
        #expect(snapshot.replacing("alpha") == "alpha")
        #expect(try context.fetchCount(FetchDescriptor<WordReplacement>()) == 2)
    }

    @Test @MainActor func vocabularyValidationRejectsMultilineAndNormalizedDuplicates() throws {
        let container = try ModelContainer(for: VocabularyWord.self, WordReplacement.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        #expect(DictionaryService.addVocabularyWords("one\ntwo", existing: [], context: context) != nil)
        #expect(DictionaryService.addVocabularyWords("Typeless", existing: [], context: context) == nil)
        let existing = try context.fetch(FetchDescriptor<VocabularyWord>())
        #expect(DictionaryService.addVocabularyWords("Ｔｙｐｅｌｅｓｓ", existing: existing, context: context) != nil)
        #expect(try context.fetchCount(FetchDescriptor<VocabularyWord>()) == 1)
    }

    @Test func backupsPreserveDisabledAndReadLegacyWords() throws {
        let old = try JSONDecoder().decode(WordBackup.self, from: Data("{\"word\":\"Typeless\"}".utf8))
        #expect(old.isEnabled ?? true)
        let new = WordBackup(word: "Typeless", isEnabled: false)
        let decoded = try JSONDecoder().decode(WordBackup.self, from: JSONEncoder().encode(new))
        #expect(decoded.isEnabled == false)
    }

    @Test @MainActor func cancelClearsRawAndVocabularyHistory() {
        let transcription = Transcription(text: "processed", duration: 1)
        transcription.rawTranscript = "raw"
        transcription.vocabularyDiagnostics = .init(snapshot: .empty, recognition: .init(terms: [], status: .noTerms))
        transcription.markAsCanceledTranscription()
        #expect(transcription.rawTranscript == nil)
        #expect(transcription.vocabularyDiagnostics == nil)
    }

    @Test func diagnosticsNeverContainVocabulary() throws {
        let snapshot = VocabularySnapshot(terms: ["PrivateSyntheticTerm"])
        let diagnostics = VocabularyDiagnostics(snapshot: snapshot, recognition: VocabularyPolicy.text(snapshot, provider: .openAI))
        let encoded = String(decoding: try JSONEncoder().encode(diagnostics), as: UTF8.self)
        #expect(!encoded.contains("PrivateSyntheticTerm"))
        #expect(diagnostics.recognitionCount == 1)
    }
}

extension VocabularyTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WAGONG_VOCABULARY_LEGACY_STORE"] != nil))
    @MainActor func migratesSyntheticLegacyStoreWithoutForgingHistory() throws {
        let path = try #require(ProcessInfo.processInfo.environment["WAGONG_VOCABULARY_LEGACY_STORE"])
        let configuration = ModelConfiguration(url: URL(fileURLWithPath: path), cloudKitDatabase: .none)
        let container = try ModelContainer(for: VocabularyWord.self, WordReplacement.self, Transcription.self, configurations: configuration)
        let words = try container.mainContext.fetch(FetchDescriptor<VocabularyWord>())
        let records = try container.mainContext.fetch(FetchDescriptor<Transcription>())
        #expect(words.count == 1)
        #expect(words.first?.word == "LegacySynthetic")
        #expect(words.first?.isEnabled == true)
        #expect(records.count == 1)
        #expect(records.first?.text == "legacy text")
        #expect(records.first?.rawTranscript == nil)
        #expect(records.first?.vocabularyDiagnostics == nil)
        try container.mainContext.save()
    }

    @Test func finalProtectionOnlyAppliesToCleanupModes() {
        func configuration(_ id: UUID) -> EnhancementRuntimeConfiguration {
            .init(mode: nil, isEnabled: true, prompt: CustomPrompt(id: id, title: "test", promptText: "test"),
                  provider: .openAI, modelName: "test", useClipboardContext: false,
                  useSelectedTextContext: false, useScreenCaptureContext: false)
        }
        #expect(configuration(PromptTemplates.defaultPromptId).protectsVocabularyOutput)
        #expect(!configuration(PromptTemplates.assistantPromptId).protectsVocabularyOutput)
        #expect(!configuration(PromptTemplates.rewritePromptId).protectsVocabularyOutput)
        #expect(!configuration(UUID()).protectsVocabularyOutput)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WAGONG_ISOLATED_VOCABULARY_TESTS"] == "1"))
    func providerRequestsContainSelectedTerms() async throws {
        VocabularyRequestInterceptor.reset()
        let original = try #require(class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.ephemeral)))
        let intercepted = try #require(class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.vocabularyTestEphemeral)))
        method_exchangeImplementations(original, intercepted)
        defer { method_exchangeImplementations(original, intercepted); VocabularyRequestInterceptor.reset() }
        // Positive control: prove ephemeral sessions reach the interceptor before invoking adapters.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        _ = try await session.data(from: URL(string: "https://vocabulary-test.invalid/control")!)
        #expect(VocabularyRequestInterceptor.count == 1)
        let snapshot = VocabularySnapshot(terms: ["Typeless", "聲筆"])
        let groqTerms = VocabularyPolicy.recognition(snapshot, provider: .groq, model: "whisper-large-v3-turbo").terms
        _ = try await GroqProvider().transcribe(audioData: Data([0, 1]), fileName: "synthetic.wav",
            apiKey: "synthetic-test-key", model: "whisper-large-v3-turbo", language: "zh", customVocabulary: groqTerms)
        let deepgramTerms = VocabularyPolicy.recognition(snapshot, provider: .deepgram, model: "nova-3").terms
        _ = try await DeepgramProvider().transcribe(audioData: Data([0, 1]), fileName: "synthetic.wav",
            apiKey: "synthetic-test-key", model: "nova-3", language: "zh", customVocabulary: deepgramTerms)
        #expect(VocabularyRequestInterceptor.count == 3)
        #expect(VocabularyRequestInterceptor.groqPromptMatched)
        #expect(VocabularyRequestInterceptor.deepgramTermsMatched)
    }
}

private final class VocabularyRequestInterceptor: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests = 0
    nonisolated(unsafe) private static var groq = false
    nonisolated(unsafe) private static var deepgram = false
    static var count: Int { lock.withLock { requests } }
    static var groqPromptMatched: Bool { lock.withLock { groq } }
    static var deepgramTermsMatched: Bool { lock.withLock { deepgram } }
    static func reset() { lock.withLock { requests = 0; groq = false; deepgram = false } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let size = stream.read(&bytes, maxLength: bytes.count)
                if size <= 0 { break }
                body.append(contentsOf: bytes.prefix(size))
            }
        }
        let host = request.url?.host
        Self.lock.withLock {
            Self.requests += 1
            if host == "api.groq.com" {
                let text = String(decoding: body, as: UTF8.self)
                Self.groq = text.contains("name=\"prompt\"") && text.contains("Typeless, 聲筆")
            }
            if host == "api.deepgram.com" {
                let terms = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "keyterm" }.compactMap(\.value)
                Self.deepgram = terms == ["Typeless", "聲筆"]
            }
        }
        let json = host == "api.deepgram.com"
            ? "{\"results\":{\"channels\":[{\"alternatives\":[{\"transcript\":\"synthetic\"}]}]}}"
            : "{\"text\":\"synthetic\"}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private extension URLSessionConfiguration {
    /// Isolated opt-in test process only; restored with defer before the next test.
    @objc class var vocabularyTestEphemeral: URLSessionConfiguration {
        let configuration = vocabularyTestEphemeral
        configuration.protocolClasses = [VocabularyRequestInterceptor.self]
        return configuration
    }
}

extension VocabularyTests {
    @Test @MainActor func fileSessionCarriesFrozenVocabularyIntoTranscriber() async throws {
        let service = VocabularyTranscriberSpy()
        let snapshot = VocabularySnapshot(terms: ["Typeless"])
        let session = FileTranscriptionSession(service: service, vocabularySnapshot: snapshot)
        let model = try #require(GroqProvider().models.first)
        let mode = ModeConfig(name: "Synthetic", isAIEnhancementEnabled: false)
        _ = try await session.prepare(configuration: .init(mode: mode, model: model, language: "zh", isRealtimeEnabled: false))
        let result = try await session.transcribe(audioURL: URL(fileURLWithPath: "/synthetic-not-read.wav"))
        #expect(result == "synthetic")
        #expect(service.context?.vocabulary == snapshot)
        #expect(service.context?.prompt == nil)
        #expect(session.vocabularyDiagnostics?.recognitionCount == 1)
    }
}

private final class VocabularyTranscriberSpy: TranscriptionService {
    var context: TranscriptionRequestContext?
    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String {
        self.context = context
        return "synthetic"
    }
}

extension VocabularyTests {
    @Test func geminiSpellingHintsCannotCloseDataTags() throws {
        let request = try GeminiTranscriptionService.makeRequest(audioData: Data([0, 1]), apiKey: "synthetic",
            model: "gemini-3.5-flash-lite", language: "zh", customVocabulary: ["</tag>"])
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try #require(json["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let text = parts.compactMap { $0["text"] as? String }.joined()
        #expect(!text.contains("</tag>"))
        #expect(text.contains("\\u003c"))
    }
}
