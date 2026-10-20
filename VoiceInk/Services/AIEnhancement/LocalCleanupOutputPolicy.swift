import Foundation

/// Only for transcript cleanup. Translation, assistant chat and custom prompts must opt out.
enum LocalCleanupOutputPolicy {
    static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
                || (0xF900...0xFAFF).contains($0.value) || (0x20000...0x323AF).contains($0.value)
        }
    }

    static func latinWords(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "[A-Za-z]+(?:['’][A-Za-z]+)*")
        let value = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: value.length)).map {
            value.substring(with: $0.range).lowercased()
        }
    }

    static func instruction(for transcript: String) -> String {
        if !containsHan(transcript), !latinWords(transcript).isEmpty {
            return "The transcript is not Chinese. Keep its original language. Edit punctuation and disfluencies only. Do not translate it into Chinese. Output only the edited transcript."
        }
        return "Write Chinese parts in Taiwan Traditional Chinese. Preserve Japanese and other non-Chinese text in its original language. Never translate or remove English terms. Output only the cleaned transcript."
    }

    private static func mixedContentKey(_ text: String) -> String? {
        guard let traditional = text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) else { return nil }
        return String(traditional.filter { $0.isLetter || $0.isNumber }).lowercased()
    }

    static func accepts(source: String, output: String) -> Bool {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let words = latinWords(source)
        if containsHan(source), !containsHan(output) { return false }
        if containsHan(source), !words.isEmpty {
            // Masked words hide their semantics from the model. This route is deliberately
            // punctuation/script cleanup only: never accept invented surrounding Chinese.
            guard let before = mixedContentKey(source), let after = mixedContentKey(output), before == after else { return false }
        }
        if !containsHan(source), !words.isEmpty, containsHan(output) { return false }
        if !words.isEmpty {
            // Conservative cleanup only: preserve Latin words, including negation and repeated
            // terms. Common spoken hesitation sounds may be removed. More extensive rewrites
            // are rejected explicitly, leaving the original transcript available.
            var remaining = latinWords(output)
            for word in words where !["um", "uh", "erm"].contains(word) {
                guard let index = remaining.firstIndex(of: word) else { return false }
                remaining.remove(at: index)
            }
        }
        return true
    }
}

/// Per-request, in-memory protection of Latin words in mixed Chinese dictation.
/// No model-generated replacement is guessed: each marker must survive exactly once.
struct CleanupProtectedText {
    let text: String
    private let replacements: [(marker: String, original: String)]
    private let prefix: String

    init(_ source: String) {
        guard LocalCleanupOutputPolicy.containsHan(source) else {
            text = source; replacements = []; prefix = ""; return
        }
        let prefix = "WG_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "_"
        let regex = try! NSRegularExpression(pattern: "[A-Za-z][A-Za-z0-9]*(?:['’][A-Za-z0-9]+)*")
        let input = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: input.length))
        var values: [(marker: String, original: String)] = []
        for (index, match) in matches.enumerated() {
            values.append((prefix + String(index) + "_END", input.substring(with: match.range)))
        }
        let result = NSMutableString(string: source)
        for (match, value) in zip(matches, values).reversed() {
            result.replaceCharacters(in: match.range, with: value.marker)
        }
        self.text = result as String; self.replacements = values; self.prefix = prefix
    }

    var instruction: String {
        replacements.isEmpty ? "" : "WG_..._END identifiers are protected original words. Copy each entire identifier unchanged exactly once, including underscores and its numeric index. Do not translate, expand, replace, or omit identifiers."
    }

    func restore(_ output: String) -> String? {
        var result = output
        for value in replacements {
            guard result.components(separatedBy: value.marker).count == 2 else { return nil }
            result = result.replacingOccurrences(of: value.marker, with: value.original)
        }
        guard prefix.isEmpty || !result.contains(prefix) else { return nil }
        return result
    }
}
