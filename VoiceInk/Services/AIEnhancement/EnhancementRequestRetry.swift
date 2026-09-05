import Foundation

enum EnhancementRequestRetry {
    /// The transport owns network/HTTP retries. This layer only handles an explicitly enabled timeout retry.
    @MainActor
    static func run<Result>(
        retryOnTimeout: Bool,
        request: () async throws -> Result,
        onRetry: (Int, Int) -> Void
    ) async throws -> Result {
        let maximumAttempts = 3
        for attempt in 1...maximumAttempts {
            do {
                try Task.checkCancellation()
                return try await request()
            } catch EnhancementError.timeout {
                guard retryOnTimeout, attempt < maximumAttempts else { throw EnhancementError.timeout }
                try Task.checkCancellation()
                onRetry(attempt + 1, maximumAttempts)
            }
        }
        throw EnhancementError.enhancementFailed
    }
}
