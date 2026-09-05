import Foundation

/// Updated only after PCM has been written. Never called on the realtime render thread.
final class AudioCaptureReadiness: @unchecked Sendable {
    private let lock = NSLock()
    private var startedAt: TimeInterval = 0
    private var lastSignalAt: TimeInterval?
    private var signalDuration: TimeInterval = 0
    private var readyAt: TimeInterval?
    private var generation = 0
    private var canceled = false

    func reset(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        defer { lock.unlock() }
        startedAt = time
        generation += 1
        canceled = false
        lastSignalAt = nil
        signalDuration = 0
        readyAt = nil
    }

    func observe(hasSignal: Bool, duration: TimeInterval, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        defer { lock.unlock() }
        guard readyAt == nil, !canceled else { return }
        guard hasSignal, duration > 0, duration.isFinite else {
            signalDuration = 0
            lastSignalAt = nil
            return
        }
        if let lastSignalAt, time - lastSignalAt > max(0.25, duration * 2) {
            signalDuration = 0
        }
        lastSignalAt = time
        signalDuration += duration
        if signalDuration >= 0.2 { readyAt = time }
    }

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !canceled && readyAt != nil
    }

    var startupDuration: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return readyAt.map { $0 - startedAt }
    }

    func waitUntilReady(timeout: TimeInterval = 10) async throws {
        let expectedGeneration = snapshot().generation
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            try Task.checkCancellation()
            let state = snapshot()
            if state.canceled || state.generation != expectedGeneration { throw CancellationError() }
            if state.ready { return }
            if ProcessInfo.processInfo.systemUptime >= deadline { throw ReadinessError.timedOut }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func cancel() {
        lock.lock()
        canceled = true
        lock.unlock()
    }

    private func snapshot() -> (generation: Int, canceled: Bool, ready: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (generation, canceled, readyAt != nil)
    }

    enum ReadinessError: Error { case timedOut }
}
