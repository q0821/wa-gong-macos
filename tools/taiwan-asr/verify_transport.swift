import Foundation
@testable import VoiceInk

/// Links the actual built App library. It does not launch the App or read Keychain.
@main
struct AppTransportProbe {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["WAGONG_ASR_TEST_ENDPOINT"],
              let url = URL(string: endpoint), url.scheme == "http", url.host == "127.0.0.1",
              let token = environment["WAGONG_ASR_TEST_TOKEN"],
              let audio = environment["WAGONG_ASR_TEST_AUDIO"] else {
            throw URLError(.badURL)
        }
        let request = try OpenAICompatibleTranscriptionService.makeRequest(
            audioData: Data(contentsOf: URL(fileURLWithPath: audio)), endpoint: endpoint,
            apiKey: token, modelName: "breeze", language: "zh-TW"
        )
        let result = try await OpenAICompatibleTranscriptionService.send(request)
        let normalized = result.filter { $0.isLetter || $0.isNumber }.replacingOccurrences(of: "3", with: "三")
        guard normalized == "今天下午三點開會請保留原始資料不要刪除" else {
            throw URLError(.cannotParseResponse)
        }
        print("Actual App request, transport and response validation passed")
    }
}
