import Foundation

struct ShortcutEventToken: Equatable, Hashable, Sendable {
    enum Transition: UInt8, Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    let eventTimestamp: UInt64
    let keyCode: UInt16
    let transition: Transition
}

struct KeyboardEventAttribution: Equatable, Sendable {
    let sourceID: UUID
    let device: KeyboardDeviceReference
}

final class KeyboardEventAttributionBroker: @unchecked Sendable {
    private struct CachedAttribution {
        let attribution: KeyboardEventAttribution
        let observedAtNanoseconds: UInt64
    }

    private struct PendingAttributionRequest {
        let token: ShortcutEventToken
        let continuation: CheckedContinuation<KeyboardEventAttribution?, Never>
    }

    private let lock = NSLock()
    private var pendingHIDEvents: [KeyboardInputEvent] = []
    private var cachedByToken: [ShortcutEventToken: CachedAttribution] = [:]
    private var pendingRequests: [UUID: PendingAttributionRequest] = [:]
    private let matchingWindowNanoseconds: UInt64
    private let maximumPendingEvents: Int

    init(matchingWindowNanoseconds: UInt64 = 50_000_000, maximumPendingEvents: Int = 32) {
        self.matchingWindowNanoseconds = matchingWindowNanoseconds
        self.maximumPendingEvents = maximumPendingEvents
    }

    func observe(_ event: KeyboardInputEvent) {
        var completedRequests: [(CheckedContinuation<KeyboardEventAttribution?, Never>, KeyboardEventAttribution)] = []

        lock.lock()
        prune(now: event.observedAtNanoseconds)
        pendingHIDEvents.append(event)
        if pendingHIDEvents.count > maximumPendingEvents {
            pendingHIDEvents.removeFirst(pendingHIDEvents.count - maximumPendingEvents)
        }

        for (requestID, request) in Array(pendingRequests) {
            if let attribution = attributionLocked(
                for: request.token,
                observedAtNanoseconds: event.observedAtNanoseconds
            ) {
                pendingRequests.removeValue(forKey: requestID)
                completedRequests.append((request.continuation, attribution))
            }
        }
        lock.unlock()

        for (continuation, attribution) in completedRequests {
            continuation.resume(returning: attribution)
        }
    }

    func attribution(
        for token: ShortcutEventToken,
        observedAtNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> KeyboardEventAttribution? {
        lock.lock()
        defer { lock.unlock() }

        prune(now: observedAtNanoseconds)
        return attributionLocked(for: token, observedAtNanoseconds: observedAtNanoseconds)
    }

    func attribution(
        for token: ShortcutEventToken,
        waitingUpToNanoseconds timeoutNanoseconds: UInt64
    ) async -> KeyboardEventAttribution? {
        if let immediate = attribution(for: token) {
            return immediate
        }

        let requestID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let now = DispatchTime.now().uptimeNanoseconds
                lock.lock()
                prune(now: now)

                if let attribution = attributionLocked(
                    for: token,
                    observedAtNanoseconds: now
                ) {
                    lock.unlock()
                    continuation.resume(returning: attribution)
                    return
                }

                pendingRequests[requestID] = PendingAttributionRequest(
                    token: token,
                    continuation: continuation
                )
                lock.unlock()

                let cappedTimeout = min(timeoutNanoseconds, UInt64(Int.max))
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + .nanoseconds(Int(cappedTimeout))
                ) { [weak self] in
                    self?.resolvePendingRequest(requestID, with: nil)
                }
            }
        } onCancel: { [weak self] in
            self?.resolvePendingRequest(requestID, with: nil)
        }
    }

    private func attributionLocked(
        for token: ShortcutEventToken,
        observedAtNanoseconds: UInt64
    ) -> KeyboardEventAttribution? {
        if let cached = cachedByToken[token] {
            return cached.attribution
        }

        let transitionCandidates = pendingHIDEvents.indices.filter { index in
            transitionMatches(pendingHIDEvents[index].transition, token.transition)
                && isWithinWindow(pendingHIDEvents[index].observedAtNanoseconds, observedAtNanoseconds)
        }
        let exactCandidates = transitionCandidates.filter { index in
            pendingHIDEvents[index].suggestedCarbonKeyCode == token.keyCode
        }

        let selectedIndex: Int?
        if exactCandidates.count == 1 {
            selectedIndex = exactCandidates[0]
        } else if exactCandidates.isEmpty, transitionCandidates.count == 1 {
            selectedIndex = transitionCandidates[0]
        } else {
            selectedIndex = nil
        }

        let attribution = selectedIndex.map { index in
            let event = pendingHIDEvents.remove(at: index)
            return KeyboardEventAttribution(sourceID: event.sourceID, device: event.device)
        }
        if let attribution {
            cachedByToken[token] = CachedAttribution(
                attribution: attribution,
                observedAtNanoseconds: observedAtNanoseconds
            )
        }
        return attribution
    }

    func reset() {
        let continuations: [CheckedContinuation<KeyboardEventAttribution?, Never>]
        lock.lock()
        pendingHIDEvents.removeAll()
        cachedByToken.removeAll()
        continuations = pendingRequests.values.map(\.continuation)
        pendingRequests.removeAll()
        lock.unlock()

        continuations.forEach { $0.resume(returning: nil) }
    }

    func removeSource(_ sourceID: UUID) {
        lock.lock()
        pendingHIDEvents.removeAll { $0.sourceID == sourceID }
        cachedByToken = cachedByToken.filter { _, cached in
            cached.attribution.sourceID != sourceID
        }
        lock.unlock()
    }

    private func resolvePendingRequest(
        _ requestID: UUID,
        with attribution: KeyboardEventAttribution?
    ) {
        let continuation: CheckedContinuation<KeyboardEventAttribution?, Never>?
        lock.lock()
        continuation = pendingRequests.removeValue(forKey: requestID)?.continuation
        lock.unlock()
        continuation?.resume(returning: attribution)
    }

    private func prune(now: UInt64) {
        pendingHIDEvents.removeAll { !isWithinWindow($0.observedAtNanoseconds, now) }
        cachedByToken = cachedByToken.filter { _, cached in
            isWithinWindow(cached.observedAtNanoseconds, now)
        }
    }

    private func isWithinWindow(_ earlier: UInt64, _ later: UInt64) -> Bool {
        later >= earlier && later - earlier <= matchingWindowNanoseconds
    }

    private func transitionMatches(
        _ hidTransition: KeyboardInputEvent.Transition,
        _ cgTransition: ShortcutEventToken.Transition
    ) -> Bool {
        switch (hidTransition, cgTransition) {
        case (.keyDown, .keyDown), (.repeatKeyDown, .keyDown), (.keyUp, .keyUp),
            (.keyDown, .flagsChanged), (.repeatKeyDown, .flagsChanged), (.keyUp, .flagsChanged):
            return true
        default:
            return false
        }
    }
}
