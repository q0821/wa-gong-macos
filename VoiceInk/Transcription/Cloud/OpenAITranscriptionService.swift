import Foundation
import LLMkit

enum OpenAITranscriptionService {
    static let diarizationModel = "gpt-4o-transcribe-diarize"
    private static let requestTimeout: TimeInterval = 30

    static func transcribeWithSpeakerLabels(
        audioData: Data,
        fileName: String,
        apiKey: String,
        language: String?
    ) async throws -> String {
        let request = try makeDiarizedRequest(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            language: language
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

        return try speakerLabeledText(from: data)
    }

    static func makeDiarizedRequest(
        audioData: Data,
        fileName: String,
        apiKey: String,
        language: String?
    ) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMKitError.missingAPIKey
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        func addField(name: String, value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        addField(name: "model", value: diarizationModel)
        addField(name: "response_format", value: "diarized_json")
        addField(name: "chunking_strategy", value: "auto")

        if let language, !language.isEmpty, language.lowercased() != "auto" {
            addField(name: "language", value: language)
        }

        append("--\(boundary)--\r\n")

        var request = URLRequest(
            url: OpenAIProvider.apiBaseURL.appendingPathComponent("v1/audio/transcriptions")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    static func speakerLabeledText(from data: Data) throws -> String {
        let response: DiarizedResponse
        do {
            response = try JSONDecoder().decode(DiarizedResponse.self, from: data)
        } catch {
            throw LLMKitError.decodingError(error.localizedDescription)
        }

        var groupedSegments: [(speaker: String, text: String)] = []
        for segment in response.segments {
            let speaker = segment.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if let last = groupedSegments.last, last.speaker == speaker {
                groupedSegments[groupedSegments.count - 1].text += " \(text)"
            } else {
                groupedSegments.append((speaker: speaker, text: text))
            }
        }

        let result = groupedSegments
            .map { segment in
                segment.speaker.isEmpty ? segment.text : "\(segment.speaker): \(segment.text)"
            }
            .joined(separator: "\n")

        guard !result.isEmpty else {
            throw LLMKitError.noResultReturned
        }
        return result
    }
}

private struct DiarizedResponse: Decodable {
    let segments: [DiarizedSegment]
}

private struct DiarizedSegment: Decodable {
    let speaker: String
    let text: String
}
