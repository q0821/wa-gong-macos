import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import VoiceInk

struct ShortcutBindingStoreTests {
    @Test func storesAndReadsVersionedBindings() throws {
        try withStore { store, defaults in
            let action = ShortcutAction.primaryRecording
            let binding = ShortcutBinding(shortcut: makeShortcut(), scope: .allKeyboards)

            #expect(store.setBindings([binding], for: action))
            #expect(store.bindings(for: action) == [binding])
            #expect(defaults.data(forKey: "ShortcutBindings_v1_primaryRecording") != nil)
            #expect(store.hasBindings(for: action))
            #expect(store.allKeyboardBinding(for: action) == binding)
        }
    }

    @Test func modeActionUsesStableVersionedStorageKey() throws {
        try withStore { store, defaults in
            let modeID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
            let action = ShortcutAction.mode(modeID)
            let binding = ShortcutBinding(shortcut: makeShortcut(), scope: .allKeyboards)

            #expect(store.setBindings([binding], for: action))
            #expect(
                defaults.data(forKey: "ShortcutBindings_v1_mode_11111111-2222-3333-4444-555555555555")
                    != nil
            )
        }
    }

    @Test func removingDeviceBindingPreservesAllKeyboardBinding() throws {
        try withStore { store, _ in
            let action = ShortcutAction.primaryRecording
            let global = ShortcutBinding(shortcut: makeShortcut(), scope: .allKeyboards)
            let scoped = ShortcutBinding(
                shortcut: makeShortcut(keyCode: UInt16(kVK_ANSI_T)),
                scope: .device(makeDevice())
            )
            #expect(store.setBindings([global, scoped], for: action))

            #expect(store.removeBinding(id: scoped.id, for: action))
            #expect(store.bindings(for: action) == [global])
        }
    }

    @Test func upsertingSameDeviceScopeDoesNotCreateDuplicate() throws {
        try withStore { store, _ in
            let action = ShortcutAction.primaryRecording
            let first = ShortcutBinding(shortcut: makeShortcut(), scope: .device(makeDevice()))
            let replacement = ShortcutBinding(
                shortcut: makeShortcut(keyCode: UInt16(kVK_ANSI_T)),
                scope: .device(makeDevice())
            )

            #expect(store.upsertBinding(first, for: action))
            #expect(store.upsertBinding(replacement, for: action))
            #expect(store.bindings(for: action) == [replacement])
        }
    }

    @Test func nonStoredActionCannotWriteBindings() throws {
        try withStore { store, _ in
            let binding = ShortcutBinding(shortcut: makeShortcut(), scope: .allKeyboards)

            #expect(!store.setBindings([binding], for: .recorderPanelEscape))
            #expect(store.bindings(for: .recorderPanelEscape).isEmpty)
        }
    }

    private func withStore(
        _ body: (ShortcutBindingStore, UserDefaults) throws -> Void
    ) throws {
        let suiteName = "WaGongShortcutBindingStore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(ShortcutBindingStore(defaults: defaults), defaults)
    }

    private func makeShortcut(keyCode: UInt16 = UInt16(kVK_ANSI_R)) -> Shortcut {
        .key(keyCode: keyCode, modifierFlags: [.command, .shift])
    }

    private func makeDevice() -> KeyboardDeviceReference {
        KeyboardDeviceReference(
            fingerprint: "device-a",
            vendorID: 1204,
            productID: 4621,
            transport: "USB",
            displayName: "Test Keyboard",
            matchStrength: .exact
        )
    }
}
