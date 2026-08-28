import Foundation

struct KeyboardDeviceInstance: Equatable, Hashable, Sendable {
    let id: UUID
    let reference: KeyboardDeviceReference

    init(id: UUID = UUID(), reference: KeyboardDeviceReference) {
        self.id = id
        self.reference = reference
    }
}

struct KeyboardInputEvent: Equatable, Sendable {
    enum Transition: Sendable {
        case keyDown
        case repeatKeyDown
        case keyUp
    }

    let sourceID: UUID
    let device: KeyboardDeviceReference
    let usage: UInt32
    let suggestedCarbonKeyCode: UInt16?
    let transition: Transition
    let timestamp: UInt64
    let observedAtNanoseconds: UInt64
    let pressedUsages: Set<UInt32>
    let modifierUsages: Set<UInt32>
}

struct KeyboardDeviceState {
    private struct PressedState {
        let device: KeyboardDeviceInstance
        var usages: Set<UInt32>
    }

    private var isActive = false
    private var pressedBySourceID: [UUID: PressedState] = [:]

    mutating func activate() {
        isActive = true
    }

    mutating func cancel() {
        isActive = false
        pressedBySourceID.removeAll()
    }

    mutating func handle(
        device: KeyboardDeviceInstance,
        usage: UInt32,
        value: Int,
        timestamp: UInt64,
        observedAtNanoseconds: UInt64? = nil
    ) -> KeyboardInputEvent? {
        guard isActive, let descriptor = HIDKeyboardUsageMapper.descriptor(for: usage) else {
            return nil
        }

        var state = pressedBySourceID[device.id]
            ?? PressedState(device: device, usages: [])
        let wasPressed = state.usages.contains(usage)
        let isDown = value != 0
        let transition: KeyboardInputEvent.Transition

        if isDown {
            state.usages.insert(usage)
            transition = wasPressed ? .repeatKeyDown : .keyDown
        } else {
            guard wasPressed else {
                return nil
            }
            state.usages.remove(usage)
            transition = .keyUp
        }

        if state.usages.isEmpty {
            pressedBySourceID.removeValue(forKey: device.id)
        } else {
            pressedBySourceID[device.id] = state
        }

        return makeEvent(
            device: device,
            descriptor: descriptor,
            transition: transition,
            timestamp: timestamp,
            observedAtNanoseconds: observedAtNanoseconds ?? DispatchTime.now().uptimeNanoseconds,
            activeUsages: state.usages
        )
    }

    mutating func removeDevice(
        _ device: KeyboardDeviceInstance,
        timestamp: UInt64,
        observedAtNanoseconds: UInt64? = nil
    ) -> [KeyboardInputEvent] {
        guard isActive,
            let state = pressedBySourceID.removeValue(forKey: device.id)
        else {
            return []
        }

        var remainingUsages = state.usages
        return state.usages.sorted().compactMap { usage in
            guard let descriptor = HIDKeyboardUsageMapper.descriptor(for: usage) else {
                return nil
            }
            remainingUsages.remove(usage)
            return makeEvent(
                device: state.device,
                descriptor: descriptor,
                transition: .keyUp,
                timestamp: timestamp,
                observedAtNanoseconds: observedAtNanoseconds ?? DispatchTime.now().uptimeNanoseconds,
                activeUsages: remainingUsages
            )
        }
    }

    private func makeEvent(
        device: KeyboardDeviceInstance,
        descriptor: HIDKeyboardUsageDescriptor,
        transition: KeyboardInputEvent.Transition,
        timestamp: UInt64,
        observedAtNanoseconds: UInt64,
        activeUsages: Set<UInt32>
    ) -> KeyboardInputEvent {
        let modifiers = activeUsages.filter { usage in
            HIDKeyboardUsageMapper.descriptor(for: usage)?.kind == .modifier
        }
        let keys = activeUsages.subtracting(modifiers)
        return KeyboardInputEvent(
            sourceID: device.id,
            device: device.reference,
            usage: descriptor.usage,
            suggestedCarbonKeyCode: descriptor.suggestedCarbonKeyCode,
            transition: transition,
            timestamp: timestamp,
            observedAtNanoseconds: observedAtNanoseconds,
            pressedUsages: keys,
            modifierUsages: Set(modifiers)
        )
    }
}
