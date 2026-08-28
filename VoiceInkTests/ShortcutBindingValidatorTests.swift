import AppKit
import Carbon.HIToolbox
import Testing
@testable import VoiceInk

struct ShortcutBindingValidatorTests {
    private let shortcut = Shortcut.key(
        keyCode: UInt16(kVK_ANSI_R),
        modifierFlags: [.option, .command]
    )

    @Test func allKeyboardsConflictsWithDeviceScopeForDifferentAction() {
        let existing = binding(scope: .device(exactDevice(serialFingerprint: "device-a")))
        let candidate = binding(scope: .allKeyboards)

        let error = validate(candidate, existing: existing)

        #expect(error == .alreadyUsedBy(ShortcutAction.secondaryRecording.displayName))
    }

    @Test func sameExactDeviceConflictsForDifferentAction() {
        let device = exactDevice(serialFingerprint: "device-a")
        let existing = binding(scope: .device(device))
        let candidate = binding(scope: .device(device))

        #expect(validate(candidate, existing: existing) != nil)
    }

    @Test func modelFamilyConflictsWithExactDeviceFromSameModel() {
        let existing = binding(scope: .device(modelFamilyDevice()))
        let candidate = binding(scope: .device(exactDevice(serialFingerprint: "device-a")))

        #expect(validate(candidate, existing: existing) != nil)
    }

    @Test func differentExactDevicesCanReuseShortcutForDifferentActions() {
        let existing = binding(scope: .device(exactDevice(serialFingerprint: "device-a")))
        let candidate = binding(scope: .device(exactDevice(serialFingerprint: "device-b")))

        #expect(validate(candidate, existing: existing) == nil)
    }

    @Test func sameActionCanHaveGlobalFallbackAndDeviceOverride() {
        let existing = binding(scope: .allKeyboards)
        let candidate = binding(scope: .device(exactDevice(serialFingerprint: "device-a")))
        let entries = [(action: ShortcutAction.primaryRecording, binding: existing)]

        let error = ShortcutValidator.validationError(
            for: candidate,
            action: .primaryRecording,
            existingBindings: entries
        )

        #expect(error == nil)
    }

    @Test func differentShortcutDoesNotConflictEvenWhenScopeOverlaps() {
        let existing = binding(scope: .allKeyboards)
        let candidate = ShortcutBinding(
            shortcut: .key(keyCode: UInt16(kVK_ANSI_T), modifierFlags: [.option, .command]),
            scope: .allKeyboards
        )

        #expect(validate(candidate, existing: existing) == nil)
    }

    private func validate(
        _ candidate: ShortcutBinding,
        existing: ShortcutBinding
    ) -> ShortcutValidationError? {
        ShortcutValidator.validationError(
            for: candidate,
            action: .primaryRecording,
            existingBindings: [(action: .secondaryRecording, binding: existing)]
        )
    }

    private func binding(scope: KeyboardScope) -> ShortcutBinding {
        ShortcutBinding(shortcut: shortcut, scope: scope)
    }

    private func exactDevice(serialFingerprint: String) -> KeyboardDeviceReference {
        KeyboardDeviceReference(
            fingerprint: serialFingerprint,
            vendorID: 1204,
            productID: 4621,
            transport: "usb",
            displayName: "USB Keyboard",
            matchStrength: .exact
        )
    }

    private func modelFamilyDevice() -> KeyboardDeviceReference {
        KeyboardDeviceReference(
            fingerprint: "model-family",
            vendorID: 1204,
            productID: 4621,
            transport: "usb",
            displayName: "USB Keyboard",
            matchStrength: .modelFamily
        )
    }
}
