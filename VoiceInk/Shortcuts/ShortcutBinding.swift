import Foundation

struct ShortcutBinding: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var shortcut: Shortcut
    var scope: KeyboardScope

    init(id: UUID = UUID(), shortcut: Shortcut, scope: KeyboardScope) {
        self.id = id
        self.shortcut = shortcut
        self.scope = scope
    }
}

enum KeyboardScope: Codable, Equatable, Hashable, Sendable {
    case allKeyboards
    case device(KeyboardDeviceReference)

    func overlaps(_ other: Self) -> Bool {
        switch (self, other) {
        case (.allKeyboards, _), (_, .allKeyboards):
            return true
        case let (.device(first), .device(second)):
            return first.overlaps(second)
        }
    }
}
