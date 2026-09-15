import Foundation
import Testing
@testable import VoiceInk

struct SensitiveLogSanitizerTests {
    @Test func removesURLsAndBearerCredentialsFromExportedMessages() {
        let input = "Request failed at https://user:pass@example.com/reset?token=secret#fragment Authorization: Bearer abc.def.ghi"

        let output = SensitiveLogSanitizer.redact(input)

        #expect(!output.contains("example.com"))
        #expect(!output.contains("secret"))
        #expect(!output.contains("abc.def.ghi"))
        #expect(output.contains("[REDACTED_URL]"))
        #expect(output.lowercased().contains("authorization=[redacted]"))
    }

    @Test func errorSummaryDoesNotIncludeLocalizedDescriptionOrURL() {
        let error = NSError(
            domain: "ProviderError",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Rejected https://api.example.com?api_key=secret"]
        )

        let output = SensitiveLogSanitizer.errorSummary(error)

        #expect(output == "domain=ProviderError code=401 type=NSError")
        #expect(!output.contains("secret"))
    }

    @Test func removesKnownTokenFormatsWithoutAFieldLabel() {
        let token = "sk-proj_1234567890abcdefghijklmnop"

        let output = SensitiveLogSanitizer.redact("Provider rejected \(token)")

        #expect(!output.contains(token))
        #expect(output.contains("[REDACTED_TOKEN]"))
    }
}
