import AppKit
import Carbon.HIToolbox
import Testing
@testable import VoiceInk

struct ShortcutDisplayResolverTests {
    @Test func explicitlyClearedShortcutDoesNotRedisplayDefault() {
        let defaultShortcut = Shortcut.key(
            keyCode: UInt16(kVK_Escape),
            modifierFlags: []
        )

        #expect(
            ShortcutDisplayResolver.resolve(
                storedShortcut: nil,
                defaultShortcut: defaultShortcut,
                isExplicitlyCleared: true
            ) == nil
        )
    }

    @Test func untouchedShortcutCanDisplayDefault() {
        let defaultShortcut = Shortcut.key(
            keyCode: UInt16(kVK_Escape),
            modifierFlags: []
        )

        #expect(
            ShortcutDisplayResolver.resolve(
                storedShortcut: nil,
                defaultShortcut: defaultShortcut,
                isExplicitlyCleared: false
            ) == defaultShortcut
        )
    }
}
