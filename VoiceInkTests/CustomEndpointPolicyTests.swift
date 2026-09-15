import Testing
@testable import VoiceInk

struct CustomEndpointPolicyTests {
    @Test(arguments: [
        "https://api.example.com/v1",
        "http://localhost:11434",
        "http://127.0.0.1:8080/v1",
        "http://[::1]:9000/v1",
    ])
    func allowsEncryptedOrLoopbackEndpoints(_ endpoint: String) {
        #expect(CustomEndpointPolicy.isAllowed(endpoint))
    }

    @Test(arguments: [
        "http://api.example.com/v1",
        "ftp://localhost/model",
        "https://user:password@example.com/v1",
        "https:///missing-host",
        "not a url",
    ])
    func rejectsUnsafeOrAmbiguousEndpoints(_ endpoint: String) {
        #expect(!CustomEndpointPolicy.isAllowed(endpoint))
    }
}
