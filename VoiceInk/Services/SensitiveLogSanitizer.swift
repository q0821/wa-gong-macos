import Foundation

enum SensitiveLogSanitizer {
    static func redact(_ message: String) -> String {
        var result = replacing(
            pattern: #"(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token|authorization|oauth[_-]?code)\s*[=:]\s*(?:Bearer\s+)?[^\s,;]+"#,
            in: message,
            with: "$1=[REDACTED]"
        )
        result = replacing(
            pattern: #"(?i)\bBearer\s+[^\s,;]+"#,
            in: result,
            with: "Bearer [REDACTED]"
        )
        result = replacing(
            pattern: #"(?i)https?://[^\s<>\"']+"#,
            in: result,
            with: "[REDACTED_URL]"
        )
        result = replacing(
            pattern: #"\b(sk-[A-Za-z0-9_-]{16,}|AIza[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9_]{16,}|xox[baprs]-[A-Za-z0-9-]{16,})\b"#,
            in: result,
            with: "[REDACTED_TOKEN]"
        )
        return result
    }

    static func errorSummary(_ error: Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code) type=\(String(describing: type(of: error)))"
    }

    private static func replacing(pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}
