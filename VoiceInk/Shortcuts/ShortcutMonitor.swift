import AppKit
import CoreGraphics
import Foundation
import os

final class ShortcutMonitor {
    enum EventKind {
        case keyDown
        case keyUp
        case flagsChanged
    }

    private struct ShortcutState {
        var bindings: [ShortcutBinding]
        var activeBinding: ShortcutBinding? = nil
        var activeSourceID: UUID? = nil
        var isDown = false
        var pressedAt: TimeInterval?
        var isInterrupted = false
    }

    private var shortcuts: [ShortcutAction: ShortcutState] = [:]
    private var interruptibleActions: Set<ShortcutAction> = []
    private var onKeyDown: ((ShortcutAction, TimeInterval) -> Void)?
    private var onKeyUp: ((ShortcutAction, TimeInterval) -> Void)?
    private var onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private let attributionBroker: KeyboardEventAttributionBroker?
    private let logger = Logger(subsystem: "com.jackie-yeh.wagong", category: "ShortcutMonitor")

    private static let shortcutInterruptionWindow: TimeInterval = 1.0

    init(attributionBroker: KeyboardEventAttributionBroker? = nil) {
        self.attributionBroker = attributionBroker
    }

    deinit {
        stop()
    }

    @discardableResult
    func start(
        shortcuts: [ShortcutAction: Shortcut],
        interruptibleActions: Set<ShortcutAction> = [],
        onKeyDown: @escaping (ShortcutAction, TimeInterval) -> Void,
        onKeyUp: @escaping (ShortcutAction, TimeInterval) -> Void,
        onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)? = nil
    ) -> Bool {
        start(
            bindings: shortcuts.mapValues { [ShortcutBinding(shortcut: $0, scope: .allKeyboards)] },
            interruptibleActions: interruptibleActions,
            onKeyDown: onKeyDown,
            onKeyUp: onKeyUp,
            onShortcutInterrupted: onShortcutInterrupted
        )
    }

    @discardableResult
    func start(
        bindings: [ShortcutAction: [ShortcutBinding]],
        interruptibleActions: Set<ShortcutAction> = [],
        onKeyDown: @escaping (ShortcutAction, TimeInterval) -> Void,
        onKeyUp: @escaping (ShortcutAction, TimeInterval) -> Void,
        onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)? = nil
    ) -> Bool {
        configureForTesting(
            bindings: bindings,
            interruptibleActions: interruptibleActions,
            onKeyDown: onKeyDown,
            onKeyUp: onKeyUp,
            onShortcutInterrupted: onShortcutInterrupted
        )

        guard !shortcuts.isEmpty else {
            return true
        }

        return installEventTap()
    }

    func configureForTesting(
        bindings: [ShortcutAction: [ShortcutBinding]],
        interruptibleActions: Set<ShortcutAction> = [],
        onKeyDown: @escaping (ShortcutAction, TimeInterval) -> Void,
        onKeyUp: @escaping (ShortcutAction, TimeInterval) -> Void,
        onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)? = nil
    ) {
        stop()

        for (action, actionBindings) in bindings where !actionBindings.isEmpty {
            shortcuts[action] = ShortcutState(bindings: actionBindings)
        }

        self.interruptibleActions = interruptibleActions
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onShortcutInterrupted = onShortcutInterrupted

    }

    func stop() {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        shortcuts = [:]
        interruptibleActions = []
        onKeyDown = nil
        onKeyUp = nil
        onShortcutInterrupted = nil
    }

    func releaseActiveShortcuts(from sourceID: UUID) {
        let eventTime = ProcessInfo.processInfo.systemUptime
        for action in Array(shortcuts.keys) {
            guard var state = shortcuts[action], state.isDown, state.activeSourceID == sourceID else {
                continue
            }

            state.isDown = false
            state.pressedAt = nil
            state.isInterrupted = false
            state.activeBinding = nil
            state.activeSourceID = nil
            shortcuts[action] = state

            if interruptibleActions.contains(action) {
                dispatchKeyUp(for: action, eventTime: eventTime)
            }
        }
    }

    private func installEventTap() -> Bool {
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.resetPressedShortcutsAfterTapInterruption()
                if let eventTap = monitor.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let shouldSuppress = monitor.handleCGEvent(type: type, event: event)
            return shouldSuppress ? nil : Unmanaged.passUnretained(event)
        }

        guard
            let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: Self.eventMask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            logger.error("Failed to install global shortcut event tap")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            logger.error("Failed to create global shortcut event tap run loop source")
            return false
        }

        self.eventTap = eventTap
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard let eventKind = EventKind(type) else {
            return false
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        let token = ShortcutEventToken(
            eventTimestamp: event.timestamp,
            keyCode: keyCode,
            transition: eventKind.tokenTransition
        )
        let attribution = attributionBroker?.attribution(for: token)
        return handleEvent(
            kind: eventKind,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            eventTime: ProcessInfo.processInfo.systemUptime,
            attribution: attribution
        )
    }

    private func resetPressedShortcutsAfterTapInterruption() {
        let eventTime = ProcessInfo.processInfo.systemUptime
        let pressedActions = shortcuts.compactMap { action, state in
            state.isDown ? action : nil
        }

        guard !pressedActions.isEmpty else {
            return
        }

        for action in pressedActions {
            if var state = shortcuts[action] {
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                state.activeBinding = nil
                state.activeSourceID = nil
                shortcuts[action] = state
            }
            dispatchKeyUp(for: action, eventTime: eventTime)
        }
    }

    func handleEvent(
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval,
        attribution: KeyboardEventAttribution?
    ) -> Bool {
        var shouldSuppress = false

        if kind == .keyDown {
            handleShortcutInterruptions(keyCode: keyCode, eventTime: eventTime)
        }

        for action in Array(shortcuts.keys) {
            guard var state = shortcuts[action] else {
                continue
            }

            let shouldHandleAsModifierOnly = state.activeBinding?.shortcut.isModifierOnly == true
                || (!state.isDown
                    && kind == .flagsChanged
                    && state.bindings.contains(where: { $0.shortcut.isModifierOnly }))
            if shouldHandleAsModifierOnly {
                handleModifierOnlyShortcut(
                    action: action,
                    state: state,
                    kind: kind,
                    keyCode: keyCode,
                    modifierFlags: modifierFlags,
                    eventTime: eventTime,
                    attribution: attribution
                )
                continue
            }

            let binding = state.activeBinding ?? resolvedBinding(
                from: state.bindings,
                attribution: attribution,
                matching: { $0.matchesKeyEvent(keyCode: keyCode, modifierFlags: modifierFlags) }
            )
            guard let binding else { continue }
            let transition = transitionForKeyShortcut(
                binding.shortcut,
                isDown: state.isDown,
                kind: kind,
                keyCode: keyCode,
                modifierFlags: modifierFlags
            )

            switch transition {
            case .none:
                break
            case .suppress:
                shouldSuppress = true
            case .keyDown:
                state.isDown = true
                state.activeBinding = binding
                state.activeSourceID = attribution?.sourceID
                state.pressedAt = eventTime
                state.isInterrupted = false
                shortcuts[action] = state
                shouldSuppress = true
                dispatchKeyDown(for: action, eventTime: eventTime)
            case .keyUp:
                guard sourceMatchesActiveState(state, attribution: attribution) else { break }
                state.isDown = false
                state.activeBinding = nil
                state.activeSourceID = nil
                state.pressedAt = nil
                state.isInterrupted = false
                shortcuts[action] = state
                shouldSuppress = true
                dispatchKeyUp(for: action, eventTime: eventTime)
            }
        }

        return shouldSuppress
    }

    private enum ShortcutTransition {
        case none
        case suppress
        case keyDown
        case keyUp
    }

    private func transitionForKeyShortcut(
        _ shortcut: Shortcut,
        isDown: Bool,
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> ShortcutTransition {
        switch kind {
        case .keyDown:
            guard shortcut.matchesKeyEvent(keyCode: keyCode, modifierFlags: modifierFlags) else {
                return .none
            }

            return isDown ? .suppress : .keyDown
        case .keyUp:
            return isDown && keyCode == shortcut.keyCode ? .keyUp : .none
        case .flagsChanged:
            guard isDown else {
                return .none
            }

            let currentFlags = Shortcut.normalizedModifierFlags(
                modifierFlags,
                forKeyCode: shortcut.keyCode
            )
            return currentFlags.isSuperset(of: shortcut.modifierFlags) ? .suppress : .keyUp
        }
    }

    private func handleModifierOnlyShortcut(
        action: ShortcutAction,
        state: ShortcutState,
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval,
        attribution: KeyboardEventAttribution?
    ) {
        var state = state

        guard kind == .flagsChanged else {
            return
        }

        if state.isDown {
            guard let activeBinding = state.activeBinding,
                sourceMatchesActiveState(state, attribution: attribution)
            else { return }
            if activeBinding.shortcut.shouldReleaseModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) {
                state.isDown = false
                state.activeBinding = nil
                state.activeSourceID = nil
                state.pressedAt = nil
                state.isInterrupted = false
                shortcuts[action] = state
                dispatchKeyUp(for: action, eventTime: eventTime)
            }

            return
        }

        guard let binding = resolvedBinding(
            from: state.bindings,
            attribution: attribution,
            matching: { $0.matchesModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) }
        ) else { return }

        if binding.shortcut.matchesModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) {
            state.isDown = true
            state.activeBinding = binding
            state.activeSourceID = attribution?.sourceID
            state.pressedAt = eventTime
            state.isInterrupted = false
            shortcuts[action] = state
            dispatchKeyDown(for: action, eventTime: eventTime)
        }
    }

    private func handleShortcutInterruptions(keyCode: UInt16, eventTime: TimeInterval) {
        guard !Shortcut.isModifierKeyCode(keyCode) else {
            return
        }

        for action in interruptibleActions {
            guard var state = shortcuts[action],
                state.isDown,
                !state.isInterrupted,
                let pressedAt = state.pressedAt,
                eventTime - pressedAt <= Self.shortcutInterruptionWindow,
                state.activeBinding?.shortcut.isInterruptedByAdditionalKeyDown(keyCode: keyCode) == true
            else {
                continue
            }

            state.isInterrupted = true
            shortcuts[action] = state
            dispatchShortcutInterrupted(for: action, eventTime: eventTime)
        }
    }

    private func resolvedBinding(
        from bindings: [ShortcutBinding],
        attribution: KeyboardEventAttribution?,
        matching predicate: (Shortcut) -> Bool
    ) -> ShortcutBinding? {
        let candidates = bindings.filter { predicate($0.shortcut) }
        if let attribution,
            let deviceBinding = candidates.first(where: { binding in
                guard case .device(let storedDevice) = binding.scope else { return false }
                return storedDevice.matches(attribution.device)
            })
        {
            return deviceBinding
        }
        return candidates.first { $0.scope == .allKeyboards }
    }

    private func sourceMatchesActiveState(
        _ state: ShortcutState,
        attribution: KeyboardEventAttribution?
    ) -> Bool {
        guard let activeBinding = state.activeBinding else { return false }
        if case .device = activeBinding.scope {
            return state.activeSourceID != nil && state.activeSourceID == attribution?.sourceID
        }
        if let activeSourceID = state.activeSourceID, let attribution {
            return activeSourceID == attribution.sourceID
        }
        return true
    }

    private func dispatchKeyDown(for action: ShortcutAction, eventTime: TimeInterval) {
        DispatchQueue.main.async { [onKeyDown] in
            onKeyDown?(action, eventTime)
        }
    }

    private func dispatchKeyUp(for action: ShortcutAction, eventTime: TimeInterval) {
        DispatchQueue.main.async { [onKeyUp] in
            onKeyUp?(action, eventTime)
        }
    }

    private func dispatchShortcutInterrupted(for action: ShortcutAction, eventTime: TimeInterval) {
        DispatchQueue.main.async { [onShortcutInterrupted] in
            onShortcutInterrupted?(action, eventTime)
        }
    }

    private static let eventMask: CGEventMask = [
        CGEventType.keyDown,
        CGEventType.keyUp,
        CGEventType.flagsChanged,
    ].reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << Int(type.rawValue))
    }
}

private extension ShortcutMonitor.EventKind {
    var tokenTransition: ShortcutEventToken.Transition {
        switch self {
        case .keyDown: return .keyDown
        case .keyUp: return .keyUp
        case .flagsChanged: return .flagsChanged
        }
    }

    init?(_ type: CGEventType) {
        switch type {
        case .keyDown:
            self = .keyDown
        case .keyUp:
            self = .keyUp
        case .flagsChanged:
            self = .flagsChanged
        default:
            return nil
        }
    }
}
