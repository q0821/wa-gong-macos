import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import VoiceInk

struct ShortcutBindingMigrationTests {
    @Test func everyLegacyStoredActionMigratesToAllKeyboards() throws {
        try withStore { store, defaults in
            let modeID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
            let actions = ShortcutAction.legacyKeyboardShortcutActions + [.mode(modeID)]

            for action in actions {
                defaults.set(try JSONEncoder().encode(makeShortcut()), forKey: action.userDefaultsKey)
                #expect(store.migrateLegacyShortcutIfNeeded(for: action))
                #expect(store.bindings(for: action).count == 1)
                #expect(store.allKeyboardBinding(for: action)?.shortcut == makeShortcut())
            }
        }
    }

    @Test func clearedLegacyShortcutDoesNotReappear() throws {
        try withStore { store, defaults in
            let action = ShortcutAction.secondaryRecording
            defaults.set(try JSONEncoder().encode(makeShortcut()), forKey: action.userDefaultsKey)
            defaults.set(true, forKey: "\(action.userDefaultsKey)_cleared")

            #expect(store.migrateLegacyShortcutIfNeeded(for: action))
            #expect(store.bindings(for: action).isEmpty)
        }
    }

    @Test func rerunningMigrationPreservesBindingIdentity() throws {
        try withStore { store, defaults in
            let action = ShortcutAction.primaryRecording
            defaults.set(try JSONEncoder().encode(makeShortcut()), forKey: action.userDefaultsKey)

            #expect(store.migrateLegacyShortcutIfNeeded(for: action))
            let firstID = try #require(store.bindings(for: action).first?.id)
            #expect(store.migrateLegacyShortcutIfNeeded(for: action))
            #expect(store.bindings(for: action).first?.id == firstID)
        }
    }

    @Test func validNewFormatIsNeverOverwrittenByLegacyData() throws {
        try withStore { store, defaults in
            let action = ShortcutAction.primaryRecording
            let deviceBinding = ShortcutBinding(
                shortcut: makeShortcut(keyCode: UInt16(kVK_ANSI_T)),
                scope: .device(makeDevice())
            )
            #expect(store.setBindings([deviceBinding], for: action))
            defaults.set(try JSONEncoder().encode(makeShortcut()), forKey: action.userDefaultsKey)

            #expect(store.migrateLegacyShortcutIfNeeded(for: action))
            #expect(store.bindings(for: action) == [deviceBinding])
        }
    }

    @Test func corruptNewFormatPreservesLegacyFallbackAndDoesNotMarkMigration() throws {
        try withStore { store, defaults in
            let action = ShortcutAction.primaryRecording
            let corruptData = Data("not-json".utf8)
            defaults.set(corruptData, forKey: action.bindingsUserDefaultsKey)
            defaults.set(try JSONEncoder().encode(makeShortcut()), forKey: action.userDefaultsKey)

            #expect(!store.migrateLegacyShortcutIfNeeded(for: action))
            #expect(defaults.data(forKey: action.bindingsUserDefaultsKey) == corruptData)
            #expect(store.allKeyboardBinding(for: action)?.shortcut == makeShortcut())
            #expect(!defaults.bool(forKey: action.bindingsMigrationUserDefaultsKey))
        }
    }

    private func withStore(
        _ body: (ShortcutBindingStore, UserDefaults) throws -> Void
    ) throws {
        let suiteName = "WaGongShortcutBindingMigration-\(UUID().uuidString)"
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
