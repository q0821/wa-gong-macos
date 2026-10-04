import Foundation
import SwiftData
import SwiftUI

class CustomVocabularyService {
    static let shared = CustomVocabularyService()

    private init() {}

    func getCustomVocabulary(from context: ModelContext) -> String {
        guard let customWords = getCustomVocabularyWords(from: context), !customWords.isEmpty else {
            return ""
        }

        let wordsText = customWords.joined(separator: ", ")
        return "Important Vocabulary: \(wordsText)"
    }

    func getCustomVocabularyWords(from context: ModelContext) -> [String]? {
        let snapshot = VocabularySnapshot.capture(from: context)
        guard snapshot.isAvailable else { return nil }
        let words = VocabularyPolicy.selection(snapshot, supported: true).terms
        return words.isEmpty ? nil : words
    }
}
