import Foundation
import SwiftData

class WordReplacementService {
    static let shared = WordReplacementService()
    private init() {}

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        VocabularySnapshot.capture(from: context).replacing(text)
    }
}
