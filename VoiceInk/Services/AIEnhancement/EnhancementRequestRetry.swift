import Foundation

enum EnhancementRequestRetry {
    /// A timeout may leave inference running or billed. Do not automatically resubmit
    /// Gemini/Claude/Ollama even when legacy timeout retry is enabled.
    @MainActor
    static func run<Result>(
        retryOnTimeout: Bool,
        provider: AIProvider? = nil,
        shouldCancel: () -> Bool = { false },
        request: () async throws -> Result,
        onRetry: (Int, Int) -> Void
    ) async throws -> Result {
        let maximumAttempts = 3
        for attempt in 1...maximumAttempts {
            do {
                guard !shouldCancel() else { throw CancellationError() }
                try Task.checkCancellation()
                return try await request()
            } catch EnhancementError.timeout {
                guard retryOnTimeout, provider != .gemini, provider != .anthropic, provider != .ollama,
                      attempt < maximumAttempts else { throw EnhancementError.timeout }
                guard !shouldCancel() else { throw CancellationError() }
                try Task.checkCancellation()
                onRetry(attempt + 1, maximumAttempts)
            }
        }
        throw EnhancementError.enhancementFailed
    }
}
