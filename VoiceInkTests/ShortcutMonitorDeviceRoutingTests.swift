import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import VoiceInk

@MainActor
struct ShortcutMonitorDeviceRoutingTests {
    @Test func deviceBindingOnlyTriggersFromMatchingKeyboard() async {
        let monitor = ShortcutMonitor()
        let first = attribution(fingerprint: "first")
        let second = attribution(fingerprint: "second")
        var downs: [ShortcutAction] = []
        monitor.configureForTesting(
            bindings: [.primaryRecording: [binding(device: first.device)]],
            onKeyDown: { action, _ in downs.append(action) },
            onKeyUp: { _, _ in }
        )

        let wrongSourceSuppressed = monitor.handleEvent(
            kind: .keyDown,
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.option, .command],
            eventTime: 1,
            attribution: second
        )
        let matchingSourceSuppressed = monitor.handleEvent(
            kind: .keyDown,
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.option, .command],
            eventTime: 2,
            attribution: first
        )
        await drainMainQueue()

        #expect(!wrongSourceSuppressed)
        #expect(matchingSourceSuppressed)
        #expect(downs == [.primaryRecording])
    }

    @Test func keyUpCannotBePairedAcrossDevices() async {
        let monitor = ShortcutMonitor()
        let first = attribution(fingerprint: "first")
        let second = attribution(fingerprint: "second")
        var ups: [ShortcutAction] = []
        monitor.configureForTesting(
            bindings: [.primaryRecording: [binding(device: first.device)]],
            interruptibleActions: [.primaryRecording],
            onKeyDown: { _, _ in },
            onKeyUp: { action, _ in ups.append(action) }
        )

        _ = monitor.handleEvent(
            kind: .keyDown,
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.option, .command],
            eventTime: 1,
            attribution: first
        )
        let wrongRelease = monitor.handleEvent(
            kind: .keyUp,
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.option, .command],
            eventTime: 2,
            attribution: second
        )
        let correctRelease = monitor.handleEvent(
            kind: .keyUp,
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.option, .command],
            eventTime: 3,
            attribution: first
        )
        await drainMainQueue()

        #expect(!wrongRelease)
        #expect(correctRelease)
        #expect(ups == [.primaryRecording])
    }

    @Test func missingDeviceAttributionCannotTriggerGlobalBinding() async {
        let monitor = ShortcutMonitor()
        var downs: [ShortcutAction] = []
        monitor.configureForTesting(
            bindings: [
                .primaryRecording: [
                    ShortcutBinding(shortcut: shortcut, scope: .allKeyboards)
                ]
            ],
            onKeyDown: { action, _ in downs.append(action) },
            onKeyUp: { _, _ in }
        )

        let suppressed = monitor.handleEvent(
            kind: .keyDown,
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.option, .command],
            eventTime: 1,
            attribution: nil
        )
        await drainMainQueue()

        #expect(!suppressed)
        #expect(downs.isEmpty)
    }

    @Test func attributedPhysicalEventKeepsGlobalBindingWorking() async {
        let monitor = ShortcutMonitor()
        let physical = attribution(fingerprint: "physical")
        var downs: [ShortcutAction] = []
        monitor.configureForTesting(
            bindings: [.primaryRecording: [ShortcutBinding(shortcut: shortcut, scope: .allKeyboards)]],
            onKeyDown: { action, _ in downs.append(action) },
            onKeyUp: { _, _ in }
        )

        let suppressed = monitor.handleEvent(
            kind: .keyDown,
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.option, .command],
            eventTime: 1,
            attribution: physical
        )
        await drainMainQueue()

        #expect(suppressed)
        #expect(downs == [.primaryRecording])
    }

    @Test(arguments: [KeyboardDeviceReference.MatchStrength.modelFamily, .exact])
    func bluetoothBindingRequiresCurrentConnectionVerification(strength: KeyboardDeviceReference.MatchStrength) async {
        let monitor = ShortcutMonitor()
        let sourceID = UUID()
        let device = KeyboardDeviceReference(
            fingerprint: "family",
            vendorID: 1,
            productID: 2,
            transport: "bluetooth",
            displayName: "Keyboard",
            matchStrength: strength
        )
        let physical = KeyboardEventAttribution(sourceID: sourceID, device: device)
        var downs: [ShortcutAction] = []
        monitor.configureForTesting(
            bindings: [.primaryRecording: [binding(device: device)]],
            onKeyDown: { action, _ in downs.append(action) },
            onKeyUp: { _, _ in }
        )

        #expect(!monitor.handleEvent(
            kind: .keyDown,
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.option, .command],
            eventTime: 1,
            attribution: physical
        ))

        KeyboardDeviceVerificationRegistry.shared.markVerified(sourceID: sourceID)
        defer { KeyboardDeviceVerificationRegistry.shared.revoke(sourceID: sourceID) }

        #expect(monitor.handleEvent(
            kind: .keyDown,
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.option, .command],
            eventTime: 2,
            attribution: physical
        ))
        await drainMainQueue()
        #expect(downs == [.primaryRecording])
    }

    @Test func usbModelFamilyRightControlDoesNotRequireBluetoothVerification() async {
        let monitor = ShortcutMonitor()
        let device = KeyboardDeviceReference(
            fingerprint: "usb-family", vendorID: 1204, productID: 4621,
            transport: "usb", displayName: "Test USB Keyboard", matchStrength: .modelFamily
        )
        var downs = 0
        monitor.configureForTesting(
            bindings: [.primaryRecording: [ShortcutBinding(
                shortcut: .modifierOnly(keyCode: UInt16(kVK_RightControl), modifierFlags: [.control]),
                scope: .device(device)
            )]],
            onKeyDown: { _, _ in downs += 1 }, onKeyUp: { _, _ in }
        )
        _ = monitor.handleEvent(
            kind: .flagsChanged, keyCode: UInt16(kVK_RightControl), modifierFlags: [.control],
            eventTime: 1, attribution: KeyboardEventAttribution(sourceID: UUID(), device: device)
        )
        await drainMainQueue()
        #expect(downs == 1)
    }

    @Test func delayedHIDRightControlTriggersThroughCGEventPath() async throws {
        let clock = AttributionTestClock()
        let broker = KeyboardEventAttributionBroker(monotonicNow: { clock.now })
        let monitor = ShortcutMonitor(attributionBroker: broker, monotonicNow: { clock.now })
        let source = attribution(fingerprint: "delayed-usb")
        var downs = 0
        monitor.configureForTesting(
            bindings: [.primaryRecording: [ShortcutBinding(
                shortcut: .modifierOnly(keyCode: UInt16(kVK_RightControl), modifierFlags: [.control]),
                scope: .device(source.device)
            )]],
            onKeyDown: { _, _ in downs += 1 }, onKeyUp: { _, _ in }
        )
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_RightControl), keyDown: true))
        event.flags = .maskControl
        _ = monitor.handleCGEvent(type: .flagsChanged, event: event)
        // The HID callback arrives after the CG callback, without synthesizing a system keypress.
        broker.observe(KeyboardInputEvent(
            sourceID: source.sourceID, device: source.device, usage: 0xE4,
            suggestedCarbonKeyCode: UInt16(kVK_RightControl), transition: .keyDown,
            timestamp: 1, observedAtNanoseconds: clock.now,
            pressedUsages: [0xE4], modifierUsages: [0xE4]
        ))
        await monitor.waitForPendingAttributionForTesting()
        await drainMainQueue()
        #expect(downs == 1)
        monitor.stop()
    }

    @Test(arguments: ["stop", "disconnect", "timeout", "wrong-device"])
    func pendingSourceCannotTriggerAfterInvalidation(reason: String) async throws {
        let broker = KeyboardEventAttributionBroker()
        let monitor = ShortcutMonitor(attributionBroker: broker)
        let source = attribution(fingerprint: "cancel-usb")
        var downs = 0
        monitor.configureForTesting(
            bindings: [.primaryRecording: [ShortcutBinding(
                shortcut: .modifierOnly(keyCode: UInt16(kVK_RightControl), modifierFlags: [.control]),
                scope: .device(source.device)
            )]],
            onKeyDown: { _, _ in downs += 1 }, onKeyUp: { _, _ in }
        )
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_RightControl), keyDown: true))
        event.flags = .maskControl
        _ = monitor.handleCGEvent(type: .flagsChanged, event: event)
        if reason == "stop" { monitor.stop() }
        if reason == "disconnect" { monitor.releaseActiveShortcuts(from: source.sourceID) }
        if reason == "timeout" { try await Task.sleep(for: .milliseconds(120)) }
        let delivered = reason == "wrong-device" ? attribution(fingerprint: "other") : source
        broker.observe(KeyboardInputEvent(
            sourceID: delivered.sourceID, device: delivered.device, usage: 0xE4,
            suggestedCarbonKeyCode: UInt16(kVK_RightControl), transition: .keyDown,
            timestamp: 1, observedAtNanoseconds: DispatchTime.now().uptimeNanoseconds,
            pressedUsages: [0xE4], modifierUsages: [0xE4]
        ))
        try await Task.sleep(for: .milliseconds(120))
        #expect(downs == 0)
        monitor.stop()
    }

    @Test func queuedCallbackCannotRunAfterStop() async {
        let monitor = ShortcutMonitor()
        let source = attribution(fingerprint: "stop")
        var downs = 0
        monitor.configureForTesting(
            bindings: [.primaryRecording: [binding(device: source.device)]],
            onKeyDown: { _, _ in downs += 1 }, onKeyUp: { _, _ in }
        )
        _ = monitor.handleEvent(kind: .keyDown, keyCode: shortcut.keyCode,
            modifierFlags: shortcut.modifierFlags, eventTime: 1, attribution: source)
        monitor.stop()
        await drainMainQueue()
        #expect(downs == 0)
    }

    @Test func delayedRightControlPressAndReleasePreserveOrder() async throws {
        let clock = AttributionTestClock()
        let broker = KeyboardEventAttributionBroker(monotonicNow: { clock.now })
        let monitor = ShortcutMonitor(attributionBroker: broker, monotonicNow: { clock.now })
        let source = attribution(fingerprint: "ordered-usb")
        var transitions: [String] = []
        monitor.configureForTesting(
            bindings: [.primaryRecording: [ShortcutBinding(
                shortcut: .modifierOnly(keyCode: UInt16(kVK_RightControl), modifierFlags: [.control]),
                scope: .device(source.device)
            )]],
            onKeyDown: { _, _ in transitions.append("down") },
            onKeyUp: { _, _ in transitions.append("up") }
        )
        let down = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_RightControl), keyDown: true))
        down.flags = .maskControl
        down.timestamp = 1
        let up = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_RightControl), keyDown: false))
        up.flags = []
        up.timestamp = 2
        _ = monitor.handleCGEvent(type: .flagsChanged, event: down)
        _ = monitor.handleCGEvent(type: .flagsChanged, event: up)
        await drainMainQueue()
        for transition in [KeyboardInputEvent.Transition.keyDown, .keyUp] {
            broker.observe(KeyboardInputEvent(
                sourceID: source.sourceID, device: source.device, usage: 0xE4,
                suggestedCarbonKeyCode: UInt16(kVK_RightControl), transition: transition,
                timestamp: 1, observedAtNanoseconds: clock.now,
                pressedUsages: [], modifierUsages: []
            ))
        }
        await monitor.waitForPendingAttributionForTesting()
        await drainMainQueue()
        #expect(transitions == ["down", "up"])
        monitor.stop()
    }

    // A busy test host must not consume the physical event matching budget.
    // Advance event time explicitly; the production 75 ms bound stays unchanged.
    @Test(arguments: [UInt64(74_000_000), UInt64(76_000_000)])
    func delayedSourceRespectsEventDeadline(elapsed: UInt64) async throws {
        let clock = AttributionTestClock()
        let broker = KeyboardEventAttributionBroker(monotonicNow: { clock.now })
        let monitor = ShortcutMonitor(attributionBroker: broker, monotonicNow: { clock.now })
        let source = attribution(fingerprint: "deadline-usb")
        var downs = 0
        monitor.configureForTesting(
            bindings: [.primaryRecording: [ShortcutBinding(
                shortcut: .modifierOnly(keyCode: UInt16(kVK_RightControl), modifierFlags: [.control]),
                scope: .device(source.device)
            )]],
            onKeyDown: { _, _ in downs += 1 }, onKeyUp: { _, _ in }
        )
        defer { monitor.stop() }
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_RightControl), keyDown: true))
        event.flags = .maskControl
        _ = monitor.handleCGEvent(type: .flagsChanged, event: event)
        // Do not yield until after advancing time: reproduce delayed Task start.
        clock.advance(by: elapsed)
        broker.observe(KeyboardInputEvent(
            sourceID: source.sourceID, device: source.device, usage: 0xE4,
            suggestedCarbonKeyCode: UInt16(kVK_RightControl), transition: .keyDown,
            timestamp: 1, observedAtNanoseconds: clock.now,
            pressedUsages: [0xE4], modifierUsages: [0xE4]
        ))
        // Await the actual pending Task, then its queued action callback.
        await monitor.waitForPendingAttributionForTesting()
        await drainMainQueue()
        #expect(downs == (elapsed < 75_000_000 ? 1 : 0))
    }

    private var shortcut: Shortcut {
        .key(keyCode: UInt16(kVK_ANSI_R), modifierFlags: [.option, .command])
    }

    private func binding(device: KeyboardDeviceReference) -> ShortcutBinding {
        ShortcutBinding(shortcut: shortcut, scope: .device(device))
    }

    private func attribution(fingerprint: String) -> KeyboardEventAttribution {
        KeyboardEventAttribution(
            sourceID: UUID(),
            device: KeyboardDeviceReference(
                fingerprint: fingerprint,
                vendorID: 1,
                productID: 2,
                transport: "usb",
                displayName: "Keyboard",
                matchStrength: .exact
            )
        )
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

private final class AttributionTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var nanoseconds: UInt64 = 1_000_000_000

    var now: UInt64 { lock.withLock { nanoseconds } }

    func advance(by duration: UInt64) {
        lock.withLock { nanoseconds += duration }
    }
}
