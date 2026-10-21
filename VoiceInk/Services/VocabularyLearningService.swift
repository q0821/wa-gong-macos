import Foundation
import SwiftData
import OSLog

enum VocabularyLearningService {
    struct Source: Equatable {
        let id: UUID
        let text: String
        let enhancedText: String?
        var output: String { enhancedText ?? text }

        init(_ transcription: Transcription) {
            id = transcription.id
            text = transcription.text
            enhancedText = transcription.enhancedText
        }
    }

    enum Failure: LocalizedError {
        case invalidTerm, noMatch, unchanged, stale, pendingChanges, capacity, conflictingRule, saveFailed

        var errorDescription: String? {
            switch self {
            case .invalidTerm: String(localized: "Enter one term of 1–120 characters, without commas, line breaks or control characters.")
            case .noMatch: String(localized: "The current wording was not found. Check the source text.")
            case .unchanged: String(localized: "Enter a different spelling to correct.")
            case .stale: String(localized: "This history entry changed or is no longer available. Close and reopen the correction.")
            case .pendingChanges: String(localized: "Other changes are still being saved. Try again after they finish.")
            case .capacity: String(localized: "The dictionary can contain up to 1,000 terms. Only the provider limit is sent per request.")
            case .conflictingRule: String(localized: "This fixed replacement conflicts with an existing rule. Edit it in the dictionary first.")
            case .saveFailed: String(localized: "The correction could not be saved. No correction or vocabulary changes were kept.")
            }
        }
    }

    static func term(_ input: String) throws -> String {
        // Validate before trimming so newlines from a selection cannot silently become a word.
        guard input.rangeOfCharacter(from: CharacterSet.controlCharacters.union(.newlines)) == nil else { throw Failure.invalidTerm }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VocabularyPolicy.validTerm(value), !value.contains(","), !value.contains("，") else {
            throw Failure.invalidTerm
        }
        return value
    }

    static func preview(_ source: String, original: String, corrected: String) throws -> VocabularyRewriteResult {
        let original = try term(original)
        let corrected = try term(corrected)
        guard original != corrected else { throw Failure.unchanged }
        let result = CustomVocabularyRewriter.rewrite(source,
            rules: [CustomVocabularyRule(aliases: [original], replacement: corrected)], stage: .transcriptFinal)
        guard !result.matches.isEmpty, result.text != source else { throw Failure.noMatch }
        return result
    }

    /// One synchronous MainActor operation. No writes occur before every check succeeds.
    @MainActor static func apply(
        to id: UUID, expected: Source, original: String, corrected: String,
        remember: Bool, fixedReplacement: Bool, context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard !context.hasChanges else { throw Failure.pendingChanges }
        guard expected.id == id else { throw Failure.stale }
        let original = try term(original)
        let corrected = try term(corrected)
        let result = try preview(expected.output, original: original, corrected: corrected)
        var descriptor = FetchDescriptor<Transcription>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try context.fetch(descriptor).first,
              item.transcriptionStatus == TranscriptionStatus.completed.rawValue,
              Source(item) == expected else { throw Failure.stale }

        let words = remember ? try context.fetch(FetchDescriptor<VocabularyWord>()) : []
        let key = CustomVocabularyRewriter.matchingKey(for: corrected)
        let existingWord = words.first { CustomVocabularyRewriter.matchingKey(for: $0.word) == key }
        if remember, existingWord == nil, words.count >= 1_000 { throw Failure.capacity }

        let replacements = fixedReplacement ? try context.fetch(FetchDescriptor<WordReplacement>()) : []
        let aliasKey = CustomVocabularyRewriter.matchingKey(for: original)
        let overlapping = replacements.filter {
            VocabularySnapshot.aliases($0.originalText).contains { CustomVocabularyRewriter.matchingKey(for: $0) == aliasKey }
        }
        guard !fixedReplacement || overlapping.allSatisfy({ $0.replacementText == corrected }) else {
            throw Failure.conflictingRule
        }
        let existingRule = overlapping.first
        // Re-enabling a multi-alias rule would also enable unrelated replacements.
        if let existingRule, !existingRule.isEnabled,
           VocabularySnapshot.aliases(existingRule.originalText).count != 1 { throw Failure.conflictingRule }
        if fixedReplacement {
            var rules = replacements.filter { $0.isEnabled || $0.id == existingRule?.id }.map(VocabularySnapshot.rule)
            if let existingRule {
                rules = rules.map { rule in
                    var enabled = rule
                    if enabled.id == existingRule.id { enabled.isEnabled = true }
                    return enabled
                }
            } else {
                rules.append(CustomVocabularyRule(aliases: [original], replacement: corrected))
            }
            guard VocabularySnapshot.rulesAreSafe(rules) else { throw Failure.conflictingRule }
        }

        if remember {
            if let existingWord { existingWord.isEnabled = true }
            else { context.insert(VocabularyWord(word: corrected)) }
        }
        if fixedReplacement {
            if let existingRule { existingRule.isEnabled = true }
            else { context.insert(WordReplacement(originalText: original, replacementText: corrected)) }
        }
        if expected.enhancedText != nil { item.enhancedText = result.text }
        else { item.text = result.text }
        do { try save(context) }
        catch {
            context.rollback()
            Logger(subsystem: "com.jackie-yeh.wagong", category: "VocabularyLearning").error("Vocabulary correction save failed; changes rolled back")
            throw Failure.saveFailed
        }
    }
}
