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
        let attribution: KeyboardEventAttribution?
        let observedAtNanoseconds: UInt64
    }

    private let lock = NSLock()
    private var pendingHIDEvents: [KeyboardInputEvent] = []
    private var cachedByToken: [ShortcutEventToken: CachedAttribution] = [:]
    private let matchingWindowNanoseconds: UInt64
    private let maximumPendingEvents: Int

    init(matchingWindowNanoseconds: UInt64 = 50_000_000, maximumPendingEvents: Int = 32) {
        self.matchingWindowNanoseconds = matchingWindowNanoseconds
        self.maximumPendingEvents = maximumPendingEvents
    }

    func observe(_ event: KeyboardInputEvent) {
        lock.lock()
        defer { lock.unlock() }

        prune(now: event.observedAtNanoseconds)
        pendingHIDEvents.append(event)
        if pendingHIDEvents.count > maximumPendingEvents {
            pendingHIDEvents.removeFirst(pendingHIDEvents.count - maximumPendingEvents)
        }
    }

    func attribution(
        for token: ShortcutEventToken,
        observedAtNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> KeyboardEventAttribution? {
        lock.lock()
        defer { lock.unlock() }

        prune(now: observedAtNanoseconds)
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
        cachedByToken[token] = CachedAttribution(
            attribution: attribution,
            observedAtNanoseconds: observedAtNanoseconds
        )
        return attribution
    }

    func reset() {
        lock.lock()
        pendingHIDEvents.removeAll()
        cachedByToken.removeAll()
        lock.unlock()
    }

    func removeSource(_ sourceID: UUID) {
        lock.lock()
        pendingHIDEvents.removeAll { $0.sourceID == sourceID }
        cachedByToken = cachedByToken.filter { _, cached in
            cached.attribution?.sourceID != sourceID
        }
        lock.unlock()
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
