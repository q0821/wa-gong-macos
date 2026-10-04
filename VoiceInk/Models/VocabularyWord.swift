import Foundation
import SwiftData

@Model
final class VocabularyWord {
    var word: String = ""
    var isEnabled: Bool = true
    var dateAdded: Date = Date()

    init(word: String, dateAdded: Date = Date(), isEnabled: Bool = true) {
        self.word = word
        self.isEnabled = isEnabled
        self.dateAdded = dateAdded
    }
}
