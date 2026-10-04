import Foundation

struct CustomVocabularyRule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var aliases: [String]
    var replacement: String
    var isEnabled: Bool
    var caseSensitive: Bool
    var allowInsideWord: Bool
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        aliases: [String],
        replacement: String,
        isEnabled: Bool = true,
        caseSensitive: Bool = false,
        allowInsideWord: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.aliases = aliases
        self.replacement = replacement
        self.isEnabled = isEnabled
        self.caseSensitive = caseSensitive
        self.allowInsideWord = allowInsideWord
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case aliases
        case replacement
        case isEnabled
        case caseSensitive
        case allowInsideWord
        case sortOrder
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        aliases = try container.decode([String].self, forKey: .aliases)
        replacement = try container.decode(String.self, forKey: .replacement)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        caseSensitive = try container.decode(Bool.self, forKey: .caseSensitive)
        allowInsideWord = try container.decode(Bool.self, forKey: .allowInsideWord)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

enum VocabularyRewriteStage: String, Codable, Equatable, Sendable {
    case transcriptFinal
    case finalProtection
}

struct VocabularyMatch: Equatable, Sendable {
    let ruleID: UUID
    let sourceRangeUTF16: NSRange
    let replacementRangeUTF16: NSRange
    let stage: VocabularyRewriteStage
}

struct VocabularyRewriteResult: Equatable, Sendable {
    let text: String
    let matches: [VocabularyMatch]
}

enum CustomVocabularyRewriter {
    private struct MatchingView {
        let text: String
        let sourceRanges: [Range<String.Index>]

        var hasValidSourceMapping: Bool {
            text.count == sourceRanges.count
        }

        func originalRange(for normalizedRange: Range<String.Index>) -> Range<String.Index>? {
            let startOffset = text.distance(from: text.startIndex, to: normalizedRange.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: normalizedRange.upperBound)
            guard startOffset < endOffset,
                  sourceRanges.indices.contains(startOffset),
                  sourceRanges.indices.contains(endOffset - 1) else {
                return nil
            }
            return sourceRanges[startOffset].lowerBound..<sourceRanges[endOffset - 1].upperBound
        }
    }

    private struct Candidate {
        let rule: CustomVocabularyRule
        let matchingLength: Int
        let sourceRange: Range<String.Index>
        let sourceRangeUTF16: NSRange
    }

    static func rewrite(
        _ text: String,
        rules: [CustomVocabularyRule],
        stage: VocabularyRewriteStage
    ) -> VocabularyRewriteResult {
        let caseSensitiveView = matchingView(for: text, caseSensitive: true)
        let caseInsensitiveView = matchingView(for: text, caseSensitive: false)
        guard caseSensitiveView.hasValidSourceMapping,
              caseInsensitiveView.hasValidSourceMapping else {
            return VocabularyRewriteResult(text: text, matches: [])
        }
        let candidates = rules
            .filter(\.isEnabled)
            .flatMap { rule in
                rule.aliases.flatMap { alias -> [Candidate] in
                    let view = rule.caseSensitive ? caseSensitiveView : caseInsensitiveView
                    let normalizedAlias = normalized(alias, caseSensitive: rule.caseSensitive)
                    guard !normalizedAlias.isEmpty else { return [] }
                    var matches: [Candidate] = []
                    var searchStart = view.text.startIndex
                    while searchStart < view.text.endIndex,
                          let normalizedRange = view.text.range(
                            of: normalizedAlias,
                            range: searchStart..<view.text.endIndex
                          ),
                          let sourceRange = view.originalRange(for: normalizedRange) {
                        if hasSafeBoundary(
                            in: view.text,
                            range: normalizedRange,
                            alias: normalizedAlias,
                            allowInsideWord: rule.allowInsideWord
                        ) {
                            let sourceRangeUTF16 = NSRange(sourceRange, in: text)
                            matches.append(
                                Candidate(
                                    rule: rule,
                                    matchingLength: normalizedAlias.count,
                                    sourceRange: sourceRange,
                                    sourceRangeUTF16: sourceRangeUTF16
                                )
                            )
                        }
                        searchStart = normalizedRange.upperBound
                    }
                    return matches
                }
            }

        let rankedCandidates = candidates.sorted { lhs, rhs in
            if lhs.matchingLength != rhs.matchingLength {
                return lhs.matchingLength > rhs.matchingLength
            }
            if lhs.rule.sortOrder != rhs.rule.sortOrder {
                return lhs.rule.sortOrder < rhs.rule.sortOrder
            }
            if lhs.rule.createdAt != rhs.rule.createdAt {
                return lhs.rule.createdAt < rhs.rule.createdAt
            }
            return lhs.rule.id.uuidString < rhs.rule.id.uuidString
        }

        var selected: [Candidate] = []
        for candidate in rankedCandidates {
            let overlaps = selected.contains { picked in
                NSIntersectionRange(candidate.sourceRangeUTF16, picked.sourceRangeUTF16).length > 0
            }
            if !overlaps {
                selected.append(candidate)
            }
        }
        selected.sort { lhs, rhs in
            lhs.sourceRangeUTF16.location < rhs.sourceRangeUTF16.location
        }

        guard !selected.isEmpty else {
            return VocabularyRewriteResult(text: text, matches: [])
        }

        var rewrittenText = ""
        var matches: [VocabularyMatch] = []
        var cursor = text.startIndex
        for candidate in selected {
            rewrittenText.append(contentsOf: text[cursor..<candidate.sourceRange.lowerBound])
            let replacementLocation = rewrittenText.utf16.count
            rewrittenText.append(candidate.rule.replacement)
            matches.append(
                VocabularyMatch(
                    ruleID: candidate.rule.id,
                    sourceRangeUTF16: candidate.sourceRangeUTF16,
                    replacementRangeUTF16: NSRange(
                        location: replacementLocation,
                        length: candidate.rule.replacement.utf16.count
                    ),
                    stage: stage
                )
            )
            cursor = candidate.sourceRange.upperBound
        }
        rewrittenText.append(contentsOf: text[cursor...])

        return VocabularyRewriteResult(
            text: rewrittenText,
            matches: matches
        )
    }

    static func matchingKey(for text: String) -> String {
        normalized(text, caseSensitive: false)
    }

    private static func normalized(_ text: String, caseSensitive: Bool) -> String {
        matchingView(for: text, caseSensitive: caseSensitive).text
    }

    private static func matchingView(
        for original: String,
        caseSensitive: Bool
    ) -> MatchingView {
        var characters: [Character] = []
        var sourceRanges: [Range<String.Index>] = []
        var index = original.startIndex

        while index < original.endIndex {
            let nextIndex = original.index(after: index)
            var fragment = String(original[index..<nextIndex])
                .precomposedStringWithCompatibilityMapping
            if !caseSensitive {
                fragment = fragment.folding(
                    options: [.caseInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
            }

            for character in fragment {
                if isWhitespace(character) {
                    if characters.last == " ", let previousRange = sourceRanges.last {
                        sourceRanges[sourceRanges.count - 1] = previousRange.lowerBound..<nextIndex
                    } else {
                        characters.append(" ")
                        sourceRanges.append(index..<nextIndex)
                    }
                } else {
                    characters.append(character)
                    sourceRanges.append(index..<nextIndex)
                }
            }
            index = nextIndex
        }

        return MatchingView(text: String(characters), sourceRanges: sourceRanges)
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private static func hasSafeBoundary(
        in text: String,
        range: Range<String.Index>,
        alias: String,
        allowInsideWord: Bool
    ) -> Bool {
        guard !allowInsideWord, requiresWordBoundary(alias) else { return true }

        let previousCharacter = range.lowerBound > text.startIndex
            ? text[text.index(before: range.lowerBound)]
            : nil
        let nextCharacter = range.upperBound < text.endIndex
            ? text[range.upperBound]
            : nil
        return !isWordCharacter(previousCharacter) && !isWordCharacter(nextCharacter)
    }

    private static func requiresWordBoundary(_ alias: String) -> Bool {
        let scalars = alias.unicodeScalars
        guard !scalars.contains(where: isCJK) else { return false }
        return scalars.contains { scalar in
            scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
        }
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.unicodeScalars.allSatisfy { scalar in
            guard !isCJK(scalar) else { return false }
            return scalar == "_"
                || CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.nonBaseCharacters.contains(scalar)
        }
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x9FFF,
             0x3040...0x30FF,
             0xAC00...0xD7AF,
             0xF900...0xFAFF,
             0x20000...0x323AF:
            true
        default:
            false
        }
    }
}
