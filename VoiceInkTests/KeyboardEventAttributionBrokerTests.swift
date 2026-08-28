import Foundation
import Testing
@testable import VoiceInk

struct KeyboardEventAttributionBrokerTests {
    @Test func uniquelyMatchingHIDEventAttributesCGEvent() {
        let broker = KeyboardEventAttributionBroker()
        let source = UUID()
        broker.observe(event(sourceID: source, keyCode: 15, transition: .keyDown, observedAt: 1_000))

        let attribution = broker.attribution(
            for: token(keyCode: 15, transition: .keyDown),
            observedAtNanoseconds: 2_000
        )

        #expect(attribution?.sourceID == source)
    }

    @Test func remappedModifierCanMatchWhenItIsOnlyTransitionCandidate() {
        let broker = KeyboardEventAttributionBroker()
        let source = UUID()
        broker.observe(event(sourceID: source, keyCode: 58, transition: .keyDown, observedAt: 1_000))

        let attribution = broker.attribution(
            for: token(keyCode: 55, transition: .flagsChanged),
            observedAtNanoseconds: 2_000
        )

        #expect(attribution?.sourceID == source)
    }

    @Test func ambiguousCandidatesNeverGuessSource() {
        let broker = KeyboardEventAttributionBroker()
        broker.observe(event(sourceID: UUID(), keyCode: nil, transition: .keyDown, observedAt: 1_000))
        broker.observe(event(sourceID: UUID(), keyCode: nil, transition: .keyDown, observedAt: 1_100))

        let attribution = broker.attribution(
            for: token(keyCode: 15, transition: .keyDown),
            observedAtNanoseconds: 2_000
        )

        #expect(attribution == nil)
    }

    @Test func staleCandidateNeverAttributesLaterInput() {
        let broker = KeyboardEventAttributionBroker(matchingWindowNanoseconds: 50)
        broker.observe(event(sourceID: UUID(), keyCode: 15, transition: .keyDown, observedAt: 1_000))

        let attribution = broker.attribution(
            for: token(keyCode: 15, transition: .keyDown),
            observedAtNanoseconds: 1_051
        )

        #expect(attribution == nil)
    }

    @Test func sameCGEventTokenReturnsCachedAttributionToEveryMonitor() {
        let broker = KeyboardEventAttributionBroker()
        let source = UUID()
        let eventToken = token(keyCode: 15, transition: .keyDown)
        broker.observe(event(sourceID: source, keyCode: 15, transition: .keyDown, observedAt: 1_000))

        let first = broker.attribution(for: eventToken, observedAtNanoseconds: 2_000)
        let second = broker.attribution(for: eventToken, observedAtNanoseconds: 2_100)

        #expect(first?.sourceID == source)
        #expect(second == first)
    }

    private func token(
        keyCode: UInt16,
        transition: ShortcutEventToken.Transition
    ) -> ShortcutEventToken {
        ShortcutEventToken(eventTimestamp: 99, keyCode: keyCode, transition: transition)
    }

    private func event(
        sourceID: UUID,
        keyCode: UInt16?,
        transition: KeyboardInputEvent.Transition,
        observedAt: UInt64
    ) -> KeyboardInputEvent {
        KeyboardInputEvent(
            sourceID: sourceID,
            device: KeyboardDeviceReference(
                fingerprint: sourceID.uuidString,
                vendorID: 1,
                productID: 2,
                transport: "usb",
                displayName: "Keyboard",
                matchStrength: .exact
            ),
            usage: 0x04,
            suggestedCarbonKeyCode: keyCode,
            transition: transition,
            timestamp: observedAt,
            observedAtNanoseconds: observedAt,
            pressedUsages: [],
            modifierUsages: []
        )
    }
}
