import Foundation

@MainActor
class ModeShortcutManager {
    private let shortcutMonitor: ShortcutMonitor
    private let modeProvider: @MainActor () -> RecordingShortcutManager.Mode
    private let shortcutModeHandler: RecordingShortcutModeHandler
    private var shortcutChangeObserver: NSObjectProtocol?

    init(
        modeProvider: @escaping @MainActor () -> RecordingShortcutManager.Mode,
        shortcutModeHandler: RecordingShortcutModeHandler,
        attributionBroker: KeyboardEventAttributionBroker
    ) {
        self.modeProvider = modeProvider
        self.shortcutModeHandler = shortcutModeHandler
        self.shortcutMonitor = ShortcutMonitor(attributionBroker: attributionBroker)

        refreshModeShortcuts()

        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let action = notification.object as? ShortcutAction,
                case .mode = action
            else {
                return
            }

            Task { @MainActor in
                self?.refreshModeShortcuts()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modeShortcutAvailabilityDidChange),
            name: .modeShortcutAvailabilityDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }
        MainActor.assumeIsolated {
            shortcutMonitor.stop()
        }
    }

    @objc private func modeShortcutAvailabilityDidChange() {
        Task { @MainActor in
            refreshModeShortcuts()
        }
    }

    private func refreshModeShortcuts() {
        let bindings = ModeManager.shared.enabledConfigurations.reduce(into: [ShortcutAction: [ShortcutBinding]]()) {
            result, config in
            let action = ShortcutAction.mode(config.id)
            let actionBindings = ShortcutStore.bindings(for: action)
            if !actionBindings.isEmpty {
                result[action] = actionBindings
            }
        }

        shortcutMonitor.start(
            bindings: bindings,
            interruptibleActions: Set(bindings.keys),
            onKeyDown: { [weak self] action, eventTime in
                Task { @MainActor in
                    guard let self,
                        let modeId = self.modeId(for: action)
                    else {
                        return
                    }

                    await self.shortcutModeHandler.handleKeyDown(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        modeId: modeId
                    )
                }
            },
            onKeyUp: { [weak self] action, eventTime in
                Task { @MainActor in
                    guard let self,
                        case .mode(let modeId) = action
                    else {
                        return
                    }

                    await self.shortcutModeHandler.handleKeyUp(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        modeId: modeId
                    )
                }
            },
            onShortcutInterrupted: { [weak self] action, _ in
                Task { @MainActor in
                    guard let self, case .mode = action else { return }
                    await self.shortcutModeHandler.handleInterruption(action: action)
                }
            }
        )
    }

    private func modeId(for action: ShortcutAction) -> UUID? {
        guard case .mode(let modeId) = action,
            let config = ModeManager.shared.getConfiguration(with: modeId),
            config.isEnabled,
            ShortcutStore.hasBindings(for: .mode(config.id))
        else {
            return nil
        }

        return modeId
    }

    func releaseActiveShortcuts(from sourceID: UUID) {
        shortcutMonitor.releaseActiveShortcuts(from: sourceID)
    }
}
