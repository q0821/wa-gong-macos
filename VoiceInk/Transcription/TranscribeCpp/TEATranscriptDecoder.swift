import Foundation

/// TEA's tokenizer.json applies ByteLevel decoding, then removes BMP private-use markers.
/// The native GGUF backend has already applied ByteLevel decoding. Never apply this to other models.
enum TEATranscriptDecoder {
    static func decode(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { !(0xE000...0xF8FF).contains($0.value) }))
    }
}
