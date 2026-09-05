import Foundation
import Testing
@testable import VoiceInk

@MainActor
struct EnhancementRequestRetryTests {
    @Test func timeoutWithoutOptInSendsOnlyOnce() async {
        var attempts = 0
        var notices = 0
        await #expect(throws: EnhancementError.self) {
            let _: String = try await EnhancementRequestRetry.run(retryOnTimeout: false, request: {
                attempts += 1
                throw EnhancementError.timeout
            }, onRetry: { _, _ in notices += 1 })
        }
        #expect(attempts == 1)
        #expect(notices == 0)
    }

    @Test func explicitTimeoutRetryReportsTheSecondAttemptAndReturnsItsResult() async throws {
        var attempts = 0
        var reportedAttempts: [Int] = []
        let result = try await EnhancementRequestRetry.run(retryOnTimeout: true, request: {
            attempts += 1
            if attempts == 1 { throw EnhancementError.timeout }
            return "完成"
        }, onRetry: { attempt, _ in reportedAttempts.append(attempt) })
        #expect(result == "完成")
        #expect(reportedAttempts == [2])
        #expect(attempts == 2)
    }

    @Test func transientErrorsAreNotRetriedAgainAboveTheTransport() async {
        for error in [EnhancementError.networkError, .serverError, .rateLimitExceeded] {
            var attempts = 0
            await #expect(throws: EnhancementError.self) {
                let _: String = try await EnhancementRequestRetry.run(retryOnTimeout: true, request: {
                    attempts += 1
                    throw error
                }, onRetry: { _, _ in Issue.record("Unexpected outer retry") })
            }
            #expect(attempts == 1)
        }
    }

    @Test func repeatedTimeoutStopsAfterThreeAttempts() async {
        var attempts = 0
        await #expect(throws: EnhancementError.self) {
            let _: String = try await EnhancementRequestRetry.run(retryOnTimeout: true, request: {
                attempts += 1
                throw EnhancementError.timeout
            }, onRetry: { _, _ in })
        }
        #expect(attempts == 3)
    }
}
