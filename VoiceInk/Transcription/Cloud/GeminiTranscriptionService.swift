import Foundation
import LLMkit

enum GeminiTranscriptionService {
    private static let requestTimeout: TimeInterval = 15

    static func transcribe(
        audioData: Data,
        apiKey: String,
        model: String,
        language: String?,
        customVocabulary: [String]
    ) async throws -> String {
        let request = try makeRequest(
            audioData: audioData,
            apiKey: apiKey,
            model: model,
            language: language,
            customVocabulary: customVocabulary
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as NSError
            where error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut
        {
            throw LLMKitError.timeout
        } catch {
            throw LLMKitError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMKitError.networkError("No HTTP response received.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No error details"
            throw LLMKitError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        let decoded: GeminiResponse
        do {
            decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            throw LLMKitError.decodingError(error.localizedDescription)
        }

        let transcription = decoded.candidates
            .first?
            .content
            .parts
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let transcription, !transcription.isEmpty else {
            throw LLMKitError.noResultReturned
        }
        return transcription
    }

    static func makeRequest(
        audioData: Data,
        apiKey: String,
        model: String,
        language: String?,
        customVocabulary: [String]
    ) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMKitError.missingAPIKey
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            throw LLMKitError.invalidURL(urlString)
        }

        let body = GeminiRequest(
            contents: [
                GeminiContent(parts: [
                    GeminiPart(
                        text: transcriptionPrompt(
                            language: language,
                            customVocabulary: customVocabulary
                        ),
                        inlineData: nil
                    ),
                    GeminiPart(
                        text: nil,
                        inlineData: GeminiInlineData(
                            mimeType: "audio/wav",
                            data: audioData.base64EncodedString()
                        )
                    ),
                ])
            ],
            generationConfig: GeminiGenerationConfig(
                thinkingConfig: GeminiThinkingConfig(thinkingLevel: "minimal")
            )
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw LLMKitError.encodingError
        }
        return request
    }

    private static func transcriptionPrompt(
        language: String?,
        customVocabulary: [String]
    ) -> String {
        var instructions = [
            "You are a speech-to-text engine.",
            "Transcribe the audio verbatim and return only the transcription, without explanations or formatting.",
            "Do not translate, summarize, answer, or rewrite the speech.",
        ]

        switch language?.lowercased() {
        case nil, "", "auto":
            instructions.append("Preserve the language spoken in the audio.")
            instructions.append("When the speech is Chinese, use Traditional Chinese as used in Taiwan.")
        case "zh", "zh-tw":
            instructions.append("The expected language is Mandarin Chinese.")
            instructions.append("Write Chinese using Traditional Chinese as used in Taiwan.")
        case let languageCode?:
            instructions.append("The expected language code is \(languageCode).")
        }

        let vocabulary = customVocabulary
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !vocabulary.isEmpty {
            instructions.append("Preferred spellings and terms: \(vocabulary.joined(separator: ", ")).")
        }

        return instructions.joined(separator: " ")
    }
}

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    let text: String?
    let inlineData: GeminiInlineData?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let text {
            try container.encode(text, forKey: .text)
        }
        if let inlineData {
            try container.encode(inlineData, forKey: .inlineData)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case inlineData
    }
}

private struct GeminiInlineData: Encodable {
    let mimeType: String
    let data: String
}

private struct GeminiGenerationConfig: Encodable {
    let thinkingConfig: GeminiThinkingConfig
}

private struct GeminiThinkingConfig: Encodable {
    let thinkingLevel: String
}

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiResponseContent
}

private struct GeminiResponseContent: Decodable {
    let parts: [GeminiResponsePart]
}

private struct GeminiResponsePart: Decodable {
    let text: String?
    let thought: Bool?
}
