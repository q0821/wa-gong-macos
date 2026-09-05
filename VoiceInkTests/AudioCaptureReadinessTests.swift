import Foundation
import Testing
@testable import VoiceInk

struct AudioCaptureReadinessTests {
    @Test func waitsForSustainedNonzeroAudioAndResetsBetweenRecordings() {
        let readiness = AudioCaptureReadiness()
        readiness.reset(at: 0)
        #expect(!readiness.isReady)
        readiness.observe(hasSignal: false, duration: 1, at: 1)
        #expect(!readiness.isReady)
        readiness.observe(hasSignal: true, duration: 0.1, at: 1.1)
        #expect(!readiness.isReady)
        readiness.observe(hasSignal: true, duration: 0.1, at: 1.2)
        #expect(readiness.isReady)
        readiness.reset(at: 2)
        #expect(!readiness.isReady)
    }

    @Test func aGapOrZeroBuffersCannotBeMistakenForContinuousAudio() {
        let readiness = AudioCaptureReadiness()
        readiness.reset(at: 0)
        readiness.observe(hasSignal: true, duration: 0.1, at: 0.1)
        readiness.observe(hasSignal: true, duration: 0.1, at: 1)
        #expect(!readiness.isReady)
        readiness.observe(hasSignal: false, duration: 0.1, at: 1.1)
        readiness.observe(hasSignal: true, duration: 0.1, at: 1.2)
        #expect(!readiness.isReady)
    }

    @Test func missingAudioTimesOutAndStoppedRecordingCancelsWaiting() async throws {
        let readiness = AudioCaptureReadiness()
        readiness.reset()
        await #expect(throws: AudioCaptureReadiness.ReadinessError.self) {
            try await readiness.waitUntilReady(timeout: 0.02)
        }
        readiness.cancel()
        await #expect(throws: CancellationError.self) {
            try await readiness.waitUntilReady()
        }
        readiness.reset()
        readiness.observe(hasSignal: true, duration: 0.2)
        try await readiness.waitUntilReady()
    }
}
