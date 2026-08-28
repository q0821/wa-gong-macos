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

    @Test func missingDeviceAttributionKeepsGlobalBindingWorking() async {
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

        #expect(suppressed)
        #expect(downs == [.primaryRecording])
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
