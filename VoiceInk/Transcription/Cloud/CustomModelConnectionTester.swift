import Foundation
import LLMkit

enum ConnectionTestResult {
    case success
    case failure(message: String)
}

struct CustomModelConnectionTester {
    /// Shares normal transcription validation; a 4xx is never a successful test.
    static func testTranscriptionEndpoint(endpoint: String, apiKey: String, modelName: String) async -> ConnectionTestResult {
        guard let fixture = Bundle.main.url(forResource: "asr-connection-test", withExtension: "wav") else {
            return .failure(message: String(localized: "The built-in transcription test audio is unavailable"))
        }
        do {
            let request = try OpenAICompatibleTranscriptionService.makeRequest(
                audioData: AudioUploadPolicy.load(fixture), endpoint: endpoint,
                apiKey: apiKey, modelName: modelName, language: "zh"
            )
            _ = try await OpenAICompatibleTranscriptionService.send(request)
            return .success
        } catch is CancellationError {
            return .failure(message: String(localized: "Transcription test canceled"))
        } catch let error as CloudTranscriptionError {
            return .failure(message: error.localizedDescription)
        } catch {
            return .failure(message: String(localized: "Transcription test failed. Check the service and try again"))
        }
    }

    static func testEnhancementEndpoint(baseURL: String, apiKey: String, modelName: String) async -> ConnectionTestResult {
        guard let url = CustomEndpointPolicy.validatedURL(baseURL) else {
            return .failure(message: String(localized: "Base URL must use HTTPS (plain HTTP is allowed only for localhost)"))
        }
        let result = await OpenAILLMClient.verifyAPIKey(baseURL: url, apiKey: apiKey, model: modelName)
        if result.isValid { return .success }
        return .failure(message: result.errorMessage ?? String(localized: "Could not verify this API key"))
    }
}
