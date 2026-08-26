import Foundation

let waGongRefineXPCServiceName = "com.jackie-yeh.wagong.RefineXPC"
let waGongRefineXPCErrorDomain = "com.jackie-yeh.wagong.RefineXPC"

struct WaGongRefinePrepareRequest: Codable, Sendable {
    let requestID: UUID
    let modelDirectoryPath: String
    let systemPrompt: String
}

struct WaGongRefineEnhanceRequest: Codable, Sendable {
    let requestID: UUID
    let modelDirectoryPath: String
    let systemPrompt: String
    let transcript: String
}

struct WaGongRefineEnhanceResponse: Codable, Sendable {
    let requestID: UUID
    let output: String
}

enum WaGongRefineXPCErrorCode: Int {
    case invalidRequest = 1
    case inferenceFailed = 2
    case invalidResponse = 3
    case connectionFailed = 4
}

@objc protocol WaGongRefineXPCProtocol {
    func prepare(
        _ requestData: NSData,
        withReply reply: @escaping (NSError?) -> Void
    )

    func enhance(
        _ requestData: NSData,
        withReply reply: @escaping (NSData?, NSError?) -> Void
    )

    func shutdown(withReply reply: @escaping () -> Void)
}

func makeWaGongRefineXPCError(
    _ code: WaGongRefineXPCErrorCode,
    description: String
) -> NSError {
    NSError(
        domain: waGongRefineXPCErrorDomain,
        code: code.rawValue,
        userInfo: [NSLocalizedDescriptionKey: description]
    )
}
