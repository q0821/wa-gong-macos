import Foundation

class OpenAICompatibleTranscriptionService {
    func transcribe(audioURL: URL, model: CustomCloudModel, context: TranscriptionRequestContext) async throws -> String {
        let request = try Self.makeRequest(
            audioData: AudioUploadPolicy.load(audioURL), endpoint: model.apiEndpoint,
            apiKey: model.apiKey, modelName: model.modelName, language: context.language
        )
        return try await Self.send(request)
    }

    static func makeRequest(
        audioData: Data, endpoint: String, apiKey: String, modelName: String, language: String?
    ) throws -> URLRequest {
        guard let url = CustomEndpointPolicy.validatedURL(endpoint) else {
            throw CloudTranscriptionError.unsupportedProvider
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              apiKey.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw CloudTranscriptionError.missingAPIKey
        }
        guard !modelName.isEmpty, modelName.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw CloudTranscriptionError.dataEncodingError
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        request.timeoutInterval = ["localhost", "127.0.0.1", "::1"].contains(host ?? "") ? 180 : 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        field("model", modelName)
        field("response_format", "json")
        field("temperature", "0")
        let selectedLanguage = LanguageDictionary.whisperLanguageCode(for: language ?? "auto")
        if selectedLanguage != "auto" && !selectedLanguage.isEmpty {
            guard selectedLanguage.rangeOfCharacter(from: .controlCharacters) == nil else {
                throw CloudTranscriptionError.dataEncodingError
            }
            field("language", selectedLanguage)
        }
        append("--\(boundary)--\r\n")
        request.httpBody = body
        return request
    }

    static func send(_ request: URLRequest, session suppliedSession: URLSession? = nil) async throws -> String {
        let (data, response) = try await SingleRequestHTTPTransport.send(request, session: suppliedSession)
        return try transcript(from: data, response: response)
    }

    static func transcript(from data: Data, response: URLResponse) throws -> String {
        guard let response = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        guard (200...299).contains(response.statusCode) else {
            // Raw server bodies can echo audio content, credentials or URLs.
            let detail = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["detail"] as? String
            let message: String
            switch detail {
            case "model_busy": message = String(localized: "The local speech model is busy. Wait for the current request to finish")
            case "invalid_or_unsupported_wav_max_30_seconds": message = String(localized: "This local speech service accepts WAV recordings up to 30 seconds")
            case "inference_timeout": message = String(localized: "The local speech model timed out. Check the service and try again")
            case "model_not_found": message = String(localized: "The requested speech model is not available on this service")
            case "transcript_limit_reached": message = String(localized: "The speech model reached its output limit. Try a shorter recording")
            case "unauthorized": message = String(localized: "Invalid API key")
            default: message = String(localized: "Transcription request failed")
            }
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: response.statusCode, message: message
            )
        }
        guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data),
              !decoded.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
        return decoded.text
    }

    private struct TranscriptionResponse: Decodable { let text: String }
}
