import CryptoKit
import Foundation

struct ShortcutBindingStore {
    private enum StoredBindings {
        case absent
        case valid([ShortcutBinding])
        case corrupt
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func bindings(for action: ShortcutAction) -> [ShortcutBinding] {
        guard action.isStored else {
            return []
        }

        switch storedBindings(for: action) {
        case .valid(let bindings):
            return bindings
        case .absent, .corrupt:
            return legacyFallbackBinding(for: action).map { [$0] } ?? []
        }
    }

    @discardableResult
    func setBindings(_ bindings: [ShortcutBinding], for action: ShortcutAction) -> Bool {
        guard action.isStored, let data = try? encoder.encode(bindings) else {
            return false
        }

        defaults.set(data, forKey: action.bindingsUserDefaultsKey)
        guard case .valid(let stored) = storedBindings(for: action), stored == bindings else {
            return false
        }
        return true
    }

    @discardableResult
    func upsertBinding(_ binding: ShortcutBinding, for action: ShortcutAction) -> Bool {
        guard migrateLegacyShortcutIfNeeded(for: action),
            case .valid(var bindings) = storedBindings(for: action)
        else {
            return false
        }

        if let index = bindings.firstIndex(where: { hasSameSlot($0.scope, binding.scope) }) {
            bindings[index] = binding
        } else {
            bindings.append(binding)
        }
        return setBindings(bindings, for: action)
    }

    @discardableResult
    func removeBinding(id: UUID, for action: ShortcutAction) -> Bool {
        guard migrateLegacyShortcutIfNeeded(for: action),
            case .valid(var bindings) = storedBindings(for: action)
        else {
            return false
        }

        guard let index = bindings.firstIndex(where: { $0.id == id }) else {
            return false
        }
        bindings.remove(at: index)
        return setBindings(bindings, for: action)
    }

    func hasBindings(for action: ShortcutAction) -> Bool {
        !bindings(for: action).isEmpty
    }

    func allKeyboardBinding(for action: ShortcutAction) -> ShortcutBinding? {
        bindings(for: action).first { $0.scope == .allKeyboards }
    }

    @discardableResult
    func migrateLegacyShortcutIfNeeded(for action: ShortcutAction) -> Bool {
        guard action.isStored else {
            return false
        }

        if defaults.bool(forKey: action.bindingsMigrationUserDefaultsKey) {
            guard case .valid = storedBindings(for: action) else {
                return false
            }
            return true
        }

        switch storedBindings(for: action) {
        case .valid:
            defaults.set(true, forKey: action.bindingsMigrationUserDefaultsKey)
            return true
        case .corrupt:
            return false
        case .absent:
            break
        }

        let migratedBindings: [ShortcutBinding]
        if isShortcutCleared(for: action) {
            migratedBindings = []
        } else if let legacyShortcut = legacyShortcut(for: action) {
            migratedBindings = [
                ShortcutBinding(
                    id: legacyBindingID(for: action),
                    shortcut: legacyShortcut,
                    scope: .allKeyboards
                )
            ]
        } else if defaults.object(forKey: action.userDefaultsKey) != nil {
            return false
        } else {
            migratedBindings = []
        }

        guard setBindings(migratedBindings, for: action) else {
            return false
        }
        defaults.set(true, forKey: action.bindingsMigrationUserDefaultsKey)
        return true
    }

    func removeStorage(for action: ShortcutAction) {
        defaults.removeObject(forKey: action.bindingsUserDefaultsKey)
        defaults.removeObject(forKey: action.bindingsMigrationUserDefaultsKey)
    }

    private func storedBindings(for action: ShortcutAction) -> StoredBindings {
        guard let object = defaults.object(forKey: action.bindingsUserDefaultsKey) else {
            return .absent
        }
        guard let data = object as? Data,
            let bindings = try? decoder.decode([ShortcutBinding].self, from: data)
        else {
            return .corrupt
        }
        return .valid(bindings)
    }

    private func legacyShortcut(for action: ShortcutAction) -> Shortcut? {
        defaults.data(forKey: action.userDefaultsKey)
            .flatMap { try? decoder.decode(Shortcut.self, from: $0) }
    }

    private func legacyFallbackBinding(for action: ShortcutAction) -> ShortcutBinding? {
        guard !isShortcutCleared(for: action), let shortcut = legacyShortcut(for: action) else {
            return nil
        }
        return ShortcutBinding(
            id: legacyBindingID(for: action),
            shortcut: shortcut,
            scope: .allKeyboards
        )
    }

    private func isShortcutCleared(for action: ShortcutAction) -> Bool {
        defaults.bool(forKey: "\(action.userDefaultsKey)_cleared")
    }

    private func hasSameSlot(_ first: KeyboardScope, _ second: KeyboardScope) -> Bool {
        switch (first, second) {
        case (.allKeyboards, .allKeyboards):
            return true
        case let (.device(firstDevice), .device(secondDevice)):
            return firstDevice.overlaps(secondDevice)
        default:
            return false
        }
    }

    private func legacyBindingID(for action: ShortcutAction) -> UUID {
        let digest = SHA256.hash(data: Data("legacy-binding|\(action.storageName)".utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let start = hex.startIndex
        let parts = [8, 4, 4, 4, 12]
        var offset = 0
        let uuidString = parts.map { length -> String in
            let lower = hex.index(start, offsetBy: offset)
            offset += length
            let upper = hex.index(start, offsetBy: offset)
            return String(hex[lower..<upper])
        }.joined(separator: "-")
        return UUID(uuidString: uuidString)!
    }
}
