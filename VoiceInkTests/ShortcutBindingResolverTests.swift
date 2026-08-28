import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import VoiceInk

struct ShortcutBindingResolverTests {
    private let shortcut = Shortcut.key(
        keyCode: UInt16(kVK_ANSI_R),
        modifierFlags: [.command, .shift]
    )

    @Test func deviceBindingTakesPriorityOverAllKeyboardsForSameAction() {
        let device = makeDevice(fingerprint: "device-a", productID: 1)
        let global = ShortcutBinding(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            shortcut: shortcut,
            scope: .allKeyboards
        )
        let scoped = ShortcutBinding(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            shortcut: shortcut,
            scope: .device(device)
        )

        let resolved = ShortcutBindingResolver.resolve(
            bindings: [global, scoped],
            matching: shortcut,
            sourceDevice: device,
            deviceMatchingAvailable: true
        )

        #expect(resolved?.id == scoped.id)
    }

    @Test func sameShortcutCanResolveForDifferentDevices() {
        let firstDevice = makeDevice(fingerprint: "device-a", productID: 1)
        let secondDevice = makeDevice(fingerprint: "device-b", productID: 2)
        let firstBinding = ShortcutBinding(shortcut: shortcut, scope: .device(firstDevice))
        let secondBinding = ShortcutBinding(shortcut: shortcut, scope: .device(secondDevice))

        #expect(
            ShortcutBindingResolver.resolve(
                bindings: [firstBinding, secondBinding],
                matching: shortcut,
                sourceDevice: firstDevice,
                deviceMatchingAvailable: true
            )?.id == firstBinding.id
        )
        #expect(
            ShortcutBindingResolver.resolve(
                bindings: [firstBinding, secondBinding],
                matching: shortcut,
                sourceDevice: secondDevice,
                deviceMatchingAvailable: true
            )?.id == secondBinding.id
        )
    }

    @Test func unknownSourceOnlyAllowsAllKeyboardsBinding() {
        let device = makeDevice(fingerprint: "device-a", productID: 1)
        let scoped = ShortcutBinding(shortcut: shortcut, scope: .device(device))
        let global = ShortcutBinding(shortcut: shortcut, scope: .allKeyboards)

        let resolved = ShortcutBindingResolver.resolve(
            bindings: [scoped, global],
            matching: shortcut,
            sourceDevice: nil,
            deviceMatchingAvailable: true
        )

        #expect(resolved?.id == global.id)
    }

    @Test func deniedDeviceAccessOnlyAllowsAllKeyboardsBinding() {
        let device = makeDevice(fingerprint: "device-a", productID: 1)
        let scoped = ShortcutBinding(shortcut: shortcut, scope: .device(device))
        let global = ShortcutBinding(shortcut: shortcut, scope: .allKeyboards)

        let resolved = ShortcutBindingResolver.resolve(
            bindings: [scoped, global],
            matching: shortcut,
            sourceDevice: device,
            deviceMatchingAvailable: false
        )

        #expect(resolved?.id == global.id)
    }

    @Test func duplicateMatchingBindingsReturnOnlyOneBinding() {
        let device = makeDevice(fingerprint: "device-a", productID: 1)
        let first = ShortcutBinding(shortcut: shortcut, scope: .device(device))
        let duplicate = ShortcutBinding(shortcut: shortcut, scope: .device(device))

        let resolved = ShortcutBindingResolver.resolve(
            bindings: [first, duplicate],
            matching: shortcut,
            sourceDevice: device,
            deviceMatchingAvailable: true
        )

        #expect(resolved?.id == first.id)
    }

    @Test func allKeyboardsScopeOverlapsEveryDeviceScope() {
        let device = makeDevice(fingerprint: "device-a", productID: 1)

        #expect(KeyboardScope.allKeyboards.overlaps(.device(device)))
        #expect(KeyboardScope.device(device).overlaps(.allKeyboards))
    }

    @Test func modelFamilyScopeOverlapsExactDeviceFromSameModel() {
        let family = KeyboardDeviceReference(
            fingerprint: "family",
            vendorID: 1204,
            productID: 4621,
            transport: "USB",
            displayName: "Majestouch Convertible 2",
            matchStrength: .modelFamily
        )
        let exact = KeyboardDeviceReference(
            fingerprint: "exact",
            vendorID: 1204,
            productID: 4621,
            transport: "usb",
            displayName: "Majestouch Convertible 2",
            matchStrength: .exact
        )

        #expect(KeyboardScope.device(family).overlaps(.device(exact)))
    }

    @Test func differentExactDevicesDoNotOverlap() {
        let first = makeDevice(fingerprint: "device-a", productID: 1)
        let second = makeDevice(fingerprint: "device-b", productID: 1)

        #expect(!KeyboardScope.device(first).overlaps(.device(second)))
    }

    private func makeDevice(fingerprint: String, productID: Int) -> KeyboardDeviceReference {
        KeyboardDeviceReference(
            fingerprint: fingerprint,
            vendorID: 1204,
            productID: productID,
            transport: "USB",
            displayName: "Test Keyboard",
            matchStrength: .exact
        )
    }
}
