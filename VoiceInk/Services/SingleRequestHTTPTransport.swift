import Foundation

/// Stateless transport for potentially billable inference. Never retries or redirects.
enum SingleRequestHTTPTransport {
    static func send(_ request: URLRequest, session suppliedSession: URLSession? = nil) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = request.timeoutInterval
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = suppliedSession ?? URLSession(
            configuration: configuration, delegate: InferenceRedirectPolicy(), delegateQueue: nil
        )
        defer { if suppliedSession == nil { session.finishTasksAndInvalidate() } }
        let result = try await session.data(for: request)
        try Task.checkCancellation()
        return result
    }
}

private final class InferenceRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
