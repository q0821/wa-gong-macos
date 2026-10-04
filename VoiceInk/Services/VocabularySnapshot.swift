import Foundation
import SwiftData
import os

/// Value-only data captured once for a recording/import. Never encoded into history or logs.
struct VocabularySnapshot: Equatable, Sendable {
    var terms: [String] = []
    var rules: [CustomVocabularyRule] = []
    var isAvailable = true
    var hasConflictingRules = false

    static let empty = VocabularySnapshot()

    static func capture(from context: ModelContext) -> VocabularySnapshot {
        do {
            let words = try context.fetch(FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.dateAdded)]))
            let replacements = try context.fetch(FetchDescriptor<WordReplacement>(sortBy: [SortDescriptor(\.dateAdded)]))
            let rules = replacements.filter(\.isEnabled).map(rule)
            let conflict = !rulesAreSafe(rules)
            if conflict {
                Logger(subsystem: "com.jackie-yeh.wagong", category: "Vocabulary").error("Conflicting vocabulary replacement rules; replacements disabled for this request")
            }
            return VocabularySnapshot(
                terms: words.filter(\.isEnabled).map(\.word),
                rules: conflict ? [] : rules, hasConflictingRules: conflict)
        } catch {
            Logger(subsystem: "com.jackie-yeh.wagong", category: "Vocabulary").error("Vocabulary snapshot unavailable; no dictionary data used")
            return VocabularySnapshot(isAvailable: false)
        }
    }

    static func rule(_ item: WordReplacement) -> CustomVocabularyRule {
        CustomVocabularyRule(id: item.id, aliases: aliases(item.originalText), replacement: item.replacementText,
                             isEnabled: item.isEnabled, createdAt: item.dateAdded, updatedAt: item.dateAdded)
    }

    static func aliases(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func rulesAreSafe(_ rules: [CustomVocabularyRule]) -> Bool {
        let enabled = rules.filter(\.isEnabled)
        guard enabled.count <= 500 else { return false }
        var owners: [String: UUID] = [:]
        for rule in enabled {
            guard !rule.aliases.isEmpty, !rule.replacement.isEmpty,
                  rule.replacement.utf8.count <= 16_384, rule.aliases.count <= 100,
                  rule.aliases.allSatisfy({ !$0.isEmpty && $0.count <= 500 }) else { return false }
            for alias in rule.aliases {
                let key = CustomVocabularyRewriter.matchingKey(for: alias)
                if let owner = owners[key], owner != rule.id { return false }
                owners[key] = rule.id
            }
            // Also rejects self-expanding rules. A literal no-op is safe.
            if CustomVocabularyRewriter.rewrite(rule.replacement, rules: enabled, stage: .finalProtection).text != rule.replacement {
                return false
            }
        }
        return true
    }

    func replacing(_ text: String) -> String {
        CustomVocabularyRewriter.rewrite(text, rules: rules, stage: .transcriptFinal).text
    }
}

struct VocabularySelection: Equatable, Sendable {
    let terms: [String]
    let status: VocabularyUseStatus
    var count: Int { terms.count }
}

enum VocabularyUseStatus: String, Codable, Sendable {
    case applied, limited, noTerms, unavailable, unsupported, notRequested, notConfigured, skippedShortText, failed

    var label: String {
        switch self {
        case .applied: String(localized: "Vocabulary included")
        case .limited: String(localized: "Vocabulary partly included (limit reached)")
        case .noTerms: String(localized: "No enabled vocabulary")
        case .unavailable: String(localized: "Vocabulary unavailable")
        case .unsupported: String(localized: "Vocabulary not supported by this model")
        case .notRequested: String(localized: "Vocabulary processing not requested")
        case .notConfigured: String(localized: "Text service is not configured")
        case .skippedShortText: String(localized: "Text cleanup skipped for short text")
        case .failed: String(localized: "Vocabulary request failed")
        }
    }
}

enum VocabularyPolicy {
    static func validTerm(_ term: String) -> Bool {
        !term.isEmpty && term.count <= 120 && term.utf8.count <= 2_048
            && term.rangeOfCharacter(from: .controlCharacters) == nil
    }

    static func selection(_ snapshot: VocabularySnapshot, supported: Bool,
                          limit: Int = 100, byteLimit: Int = 8_000, accepts: (String) -> Bool = { _ in true }) -> VocabularySelection {
        guard snapshot.isAvailable else { return .init(terms: [], status: .unavailable) }
        guard !snapshot.terms.isEmpty else { return .init(terms: [], status: .noTerms) }
        guard supported else { return .init(terms: [], status: .unsupported) }
        var seen = Set<String>()
        var accepted: [String] = []
        var limited = false
        for value in snapshot.terms {
            let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard validTerm(term), accepts(term) else { limited = true; continue }
            guard seen.insert(CustomVocabularyRewriter.matchingKey(for: term)).inserted else { continue }
            guard accepted.count < limit, json(accepted + [term]).utf8.count <= byteLimit else {
                limited = true; continue
            }
            accepted.append(term)
        }
        return .init(terms: accepted, status: limited ? .limited : .applied)
    }

    static func recognition(_ snapshot: VocabularySnapshot, provider: ModelProvider, model: String,
                            streaming: Bool = false) -> VocabularySelection {
        switch provider {
        case .whisper:
            return selection(snapshot, supported: true, limit: 20, byteLimit: 224)
        case .openAI:
            return selection(snapshot, supported: !streaming && ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "gpt-transcribe", "whisper-1"].contains(model), limit: 20, byteLimit: 224)
        case .groq:
            return selection(snapshot, supported: !streaming && ["whisper-large-v3", "whisper-large-v3-turbo"].contains(model), limit: 20, byteLimit: 224)
        case .deepgram:
            return selection(snapshot, supported: ["nova-3", "nova-3-medical"].contains(model), limit: 50)
        case .elevenLabs:
            let supported = CloudProviderRegistry.provider(for: provider)?.models.contains { $0.name == model } == true
            return selection(snapshot, supported: supported, limit: 50, byteLimit: 4_000) { term in
                term.count <= 50 && term.split(whereSeparator: \.isWhitespace).count <= 5
                    && !term.contains { "<>{}[]\\".contains($0) }
            }
        case .assemblyAI:
            let supported = streaming ? model == "universal-3-5-pro" : ["universal-3-5-pro", "universal-2"].contains(model)
            return selection(snapshot, supported: supported, limit: 50, byteLimit: 4_000) { term in
                term.count <= 50 && term.split(separator: " ").count <= 6
            }
        case .soniox, .speechmatics:
            // Only models listed by the installed provider adapter are eligible.
            let supported = CloudProviderRegistry.provider(for: provider)?.models.contains { $0.name == model } == true
            return selection(snapshot, supported: supported, limit: 50, byteLimit: 4_000)
        case .gemini:
            let supported = !streaming && (CloudProviderRegistry.provider(for: provider)?.models.contains { $0.name == model } == true)
            return selection(snapshot, supported: supported)
        default:
            return selection(snapshot, supported: false)
        }
    }

    static func text(_ snapshot: VocabularySnapshot, provider: AIProvider?) -> VocabularySelection {
        selection(snapshot, supported: provider != nil && provider != .waGongRefine, byteLimit: 16_384)
    }

    /// Encode terms as data and escape tag delimiters, including hostile imported terms.
    static func json(_ terms: [String]) -> String {
        // An array of strings is always JSON serializable.
        let data = try! JSONEncoder().encode(terms)
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
    }

    static func userInput(_ text: String, selection: VocabularySelection) -> String {
        guard !selection.terms.isEmpty else { return text }
        return text + "\n<CORRECT_TERMS_JSON>\n" + json(selection.terms) + "\n</CORRECT_TERMS_JSON>"
    }
}

/// Counts/status only. Never persist the snapshot or the actual prompt.
struct VocabularyDiagnostics: Codable, Equatable {
    var recognitionStatus: VocabularyUseStatus
    var recognitionCount: Int
    var recognitionPath: String
    var textStatus: VocabularyUseStatus = .notRequested
    var textCount: Int = 0
    var replacementCount: Int
    var conflictingRules: Bool

    init(snapshot: VocabularySnapshot, recognition: VocabularySelection, streaming: Bool = false) {
        recognitionStatus = recognition.status
        recognitionCount = recognition.count
        recognitionPath = streaming ? "streaming" : "file"
        replacementCount = snapshot.rules.count
        conflictingRules = snapshot.hasConflictingRules
    }
}
