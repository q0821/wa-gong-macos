import Foundation
import Testing
@testable import VoiceInk

struct CustomASRContractTests {
    @Test func localRequestUsesFullContractAndAllowsColdStartup() throws {
        let request = try OpenAICompatibleTranscriptionService.makeRequest(
            audioData: Data([1, 2, 3]), endpoint: "http://127.0.0.1:8765/v1/audio/transcriptions",
            apiKey: "test-only-key", modelName: "JacobLinCool/TEA-ASR-1.1", language: "zh-TW"
        )
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(request.timeoutInterval == 180)
        #expect(body.contains("name=\"language\"\r\n\r\nzh\r\n"))
        #expect(body.contains("name=\"response_format\"\r\n\r\njson\r\n"))
        #expect(body.contains("name=\"temperature\"\r\n\r\n0\r\n"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only-key")
    }

    @Test(arguments: [200, 400, 415, 422, 500])
    func invalidAndRejectedTranscriptsNeverPassValidation(_ status: Int) throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8765/v1/audio/transcriptions")!,
            statusCode: status, httpVersion: nil, headerFields: nil
        ))
        #expect(throws: (any Error).self) {
            try OpenAICompatibleTranscriptionService.transcript(
                from: Data("{\"text\":\"   \"}".utf8), response: response
            )
        }
    }

    @Test func successfulTextIsPreserved() throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8765/v1/audio/transcriptions")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        ))
        #expect(try OpenAICompatibleTranscriptionService.transcript(
            from: Data("{\"text\":\"語音測試\"}".utf8), response: response
        ) == "語音測試")
    }

    @Test func remoteServerErrorsDoNotExposeResponseContents() throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://example.com/transcriptions")!, statusCode: 400,
            httpVersion: nil, headerFields: nil
        ))
        do {
            _ = try OpenAICompatibleTranscriptionService.transcript(
                from: Data("private-response-marker".utf8), response: response
            )
            Issue.record("Expected rejected request")
        } catch {
            #expect(!error.localizedDescription.contains("private-response-marker"))
        }
    }
}
