import Foundation

enum ShortcutStore {
    static let shortcutDidChange = Notification.Name("ShortcutStoreShortcutDidChange")
    static let bindingIDUserInfoKey = "bindingID"

    private static let bindingStore = ShortcutBindingStore(defaults: .standard)

    static func rawShortcut(for action: ShortcutAction) -> Shortcut? {
        shortcutData(for: action)
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }

    static func bindings(for action: ShortcutAction) -> [ShortcutBinding] {
        guard action.isStored else {
            return []
        }
        _ = bindingStore.migrateLegacyShortcutIfNeeded(for: action)
        return bindingStore.bindings(for: action)
    }

    static func shortcut(for action: ShortcutAction) -> Shortcut? {
        guard action.isStored else {
            return nil
        }
        return allKeyboardBinding(for: action)?.shortcut
    }

    @discardableResult
    static func setBindings(_ bindings: [ShortcutBinding], for action: ShortcutAction) -> Bool {
        guard action.isStored,
            bindingStore.migrateLegacyShortcutIfNeeded(for: action),
            bindingStore.setBindings(bindings, for: action)
        else {
            return false
        }

        synchronizeLegacyAllKeyboardFallback(bindings, for: action)
        removeLegacyStorage(for: action)
        postChange(for: action)
        return true
    }

    @discardableResult
    static func upsertBinding(_ binding: ShortcutBinding, for action: ShortcutAction) -> Bool {
        guard action.isStored,
            bindingStore.upsertBinding(binding, for: action)
        else {
            return false
        }

        let updatedBindings = bindingStore.bindings(for: action)
        synchronizeLegacyAllKeyboardFallback(updatedBindings, for: action)
        removeLegacyStorage(for: action)
        postChange(for: action, bindingID: binding.id)
        return true
    }

    @discardableResult
    static func removeBinding(id: UUID, for action: ShortcutAction) -> Bool {
        guard action.isStored,
            bindingStore.removeBinding(id: id, for: action)
        else {
            return false
        }

        let updatedBindings = bindingStore.bindings(for: action)
        synchronizeLegacyAllKeyboardFallback(updatedBindings, for: action)
        removeLegacyStorage(for: action)
        postChange(for: action, bindingID: id)
        return true
    }

    static func hasBindings(for action: ShortcutAction) -> Bool {
        !bindings(for: action).isEmpty
    }

    static func allKeyboardBinding(for action: ShortcutAction) -> ShortcutBinding? {
        guard action.isStored else {
            return nil
        }
        _ = bindingStore.migrateLegacyShortcutIfNeeded(for: action)
        return bindingStore.allKeyboardBinding(for: action)
    }

    static func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        guard action.isStored else {
            return
        }

        if let shortcut, ShortcutValidator.validationError(for: shortcut, action: action) != nil {
            return
        }

        var updatedBindings = bindings(for: action).filter { $0.scope != .allKeyboards }
        if let shortcut {
            let existingID = allKeyboardBinding(for: action)?.id ?? UUID()
            updatedBindings.insert(
                ShortcutBinding(id: existingID, shortcut: shortcut, scope: .allKeyboards),
                at: 0
            )
        }
        _ = setBindings(updatedBindings, for: action)
    }

    static func seedShortcut(
        _ shortcut: Shortcut,
        for action: ShortcutAction,
        replacingCleared: Bool = false
    ) {
        guard action.isStored,
            allKeyboardBinding(for: action) == nil,
            replacingCleared || !isShortcutCleared(for: action)
        else {
            return
        }

        setShortcut(shortcut, for: action)
    }

    static func removeShortcutStorage(for action: ShortcutAction) {
        guard action.isStored else {
            return
        }

        bindingStore.removeStorage(for: action)
        UserDefaults.standard.removeObject(forKey: action.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: clearedUserDefaultsKey(for: action))
        removeLegacyStorage(for: action)
        postChange(for: action)
    }

    static func shortcuts(for actions: [ShortcutAction]) -> [ShortcutAction: Shortcut] {
        actions.reduce(into: [:]) { result, action in
            if let shortcut = shortcut(for: action) {
                result[action] = shortcut
            }
        }
    }

    @discardableResult
    static func migrateBindingsIfNeeded(for action: ShortcutAction) -> Bool {
        bindingStore.migrateLegacyShortcutIfNeeded(for: action)
    }

    static func isShortcutCleared(for action: ShortcutAction) -> Bool {
        UserDefaults.standard.bool(forKey: clearedUserDefaultsKey(for: action))
    }

    private static func synchronizeLegacyAllKeyboardFallback(
        _ bindings: [ShortcutBinding],
        for action: ShortcutAction
    ) {
        if let shortcut = bindings.first(where: { $0.scope == .allKeyboards })?.shortcut,
            let data = try? JSONEncoder().encode(shortcut)
        {
            UserDefaults.standard.set(data, forKey: action.userDefaultsKey)
            UserDefaults.standard.removeObject(forKey: clearedUserDefaultsKey(for: action))
        } else {
            UserDefaults.standard.removeObject(forKey: action.userDefaultsKey)
            UserDefaults.standard.set(true, forKey: clearedUserDefaultsKey(for: action))
        }
    }

    private static func removeLegacyStorage(for action: ShortcutAction) {
        ShortcutMigration.removeLegacyCustomRecordingShortcut(for: action)
        ShortcutMigration.removeLegacyKeyboardShortcut(for: action)
    }

    private static func shortcutData(for action: ShortcutAction) -> Data? {
        UserDefaults.standard.data(forKey: action.userDefaultsKey)
    }

    private static func clearedUserDefaultsKey(for action: ShortcutAction) -> String {
        "\(action.userDefaultsKey)_cleared"
    }

    private static func postChange(for action: ShortcutAction, bindingID: UUID? = nil) {
        let userInfo = bindingID.map { [bindingIDUserInfoKey: $0] }
        NotificationCenter.default.post(
            name: shortcutDidChange,
            object: action,
            userInfo: userInfo
        )
    }
}
