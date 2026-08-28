import Foundation
import IOKit.hid

struct KeyboardDeviceSnapshot: Identifiable, Equatable, Sendable {
    enum BindingAvailability: Equatable, Sendable {
        case supported
        case unverifiedBluetooth
        case unsupportedTransport
    }

    let id: UUID
    let reference: KeyboardDeviceReference
    let bindingAvailability: BindingAvailability
}

final class KeyboardDeviceMonitor: ObservableObject, @unchecked Sendable {
    enum Status: Equatable, Sendable {
        case idle
        case listening
        case permissionDenied
        case failed
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var permissionStatus = KeyboardInputPermission.currentStatus
    @Published private(set) var connectedDevices: [KeyboardDeviceSnapshot] = []

    var onInputEvent: (@Sendable (KeyboardInputEvent) -> Void)?
    var onDeviceRemoved: (@Sendable (UUID) -> Void)?

    private final class CallbackContext {
        weak var monitor: KeyboardDeviceMonitor?

        init(monitor: KeyboardDeviceMonitor) {
            self.monitor = monitor
        }
    }

    private let queue = DispatchQueue(label: "com.jackie-yeh.wagong.keyboard-device-monitor")
    private var manager: IOHIDManager?
    private var devicesByPointer: [UInt: KeyboardDeviceInstance] = [:]
    private var deviceState = KeyboardDeviceState()
    private var statusAfterCancellation: Status = .idle

    func refreshPermissionStatus() {
        publish(permissionStatus: KeyboardInputPermission.currentStatus)
    }

    func requestAccessAndStart() {
        let wasGranted = KeyboardInputPermission.requestAccess()
        publish(permissionStatus: KeyboardInputPermission.currentStatus)
        guard wasGranted else {
            publish(status: .permissionDenied)
            return
        }
        start()
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func startOnQueue() {
        guard manager == nil else { return }

        let permissionStatus = KeyboardInputPermission.currentStatus
        publish(permissionStatus: permissionStatus)
        guard permissionStatus == .granted else {
            deviceState.cancel()
            devicesByPointer.removeAll()
            publish(devices: [])
            publish(status: .permissionDenied)
            return
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let context = Unmanaged.passRetained(CallbackContext(monitor: self)).toOpaque()

        let keyboardMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: Int(kHIDPage_GenericDesktop),
            kIOHIDDeviceUsageKey: Int(kHIDUsage_GD_Keyboard),
        ]
        let inputMatch: [String: Any] = [
            kIOHIDElementUsagePageKey: Int(kHIDPage_KeyboardOrKeypad)
        ]

        IOHIDManagerSetDeviceMatching(manager, keyboardMatch as CFDictionary)
        IOHIDManagerSetInputValueMatching(manager, inputMatch as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, result, _, device in
                guard let context else { return }
                let callbackContext = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
                guard result == kIOReturnSuccess else {
                    callbackContext.monitor?.handleCallbackFailure()
                    return
                }
                callbackContext.monitor?.handleDeviceAdded(device)
            },
            context
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, result, _, device in
                guard let context else { return }
                let callbackContext = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
                guard result == kIOReturnSuccess else {
                    callbackContext.monitor?.handleCallbackFailure()
                    return
                }
                callbackContext.monitor?.handleDeviceRemoved(device)
            },
            context
        )
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, result, _, value in
                guard let context else { return }
                let callbackContext = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
                guard result == kIOReturnSuccess else {
                    callbackContext.monitor?.handleCallbackFailure()
                    return
                }
                callbackContext.monitor?.handleInput(value)
            },
            context
        )
        IOHIDManagerSetDispatchQueue(manager, queue)
        IOHIDManagerSetCancelHandler(manager) { [weak self] in
            Unmanaged<CallbackContext>.fromOpaque(context).release()
            self?.finishCancellation(manager)
        }

        self.manager = manager
        statusAfterCancellation = .idle
        deviceState.activate()
        IOHIDManagerActivate(manager)
        publish(status: .listening)
    }

    private func stopOnQueue() {
        guard let manager else {
            deviceState.cancel()
            devicesByPointer.removeAll()
            publish(devices: [])
            publish(status: .idle)
            return
        }

        deviceState.cancel()
        devicesByPointer.removeAll()
        publish(devices: [])
        statusAfterCancellation = .idle
        IOHIDManagerCancel(manager)
    }

    private func finishCancellation(_ cancelledManager: IOHIDManager) {
        guard manager === cancelledManager else { return }
        manager = nil
        publish(status: statusAfterCancellation)
    }

    private func handleDeviceAdded(_ device: IOHIDDevice) {
        let pointer = devicePointer(device)
        guard devicesByPointer[pointer] == nil else { return }
        devicesByPointer[pointer] = KeyboardDeviceInstance(reference: makeReference(for: device))
        publishCurrentDevices()
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        let pointer = devicePointer(device)
        guard let instance = devicesByPointer.removeValue(forKey: pointer) else { return }

        let observedAt = DispatchTime.now().uptimeNanoseconds
        _ = deviceState.removeDevice(
            instance,
            timestamp: observedAt,
            observedAtNanoseconds: observedAt
        )
        onDeviceRemoved?(instance.id)
        publishCurrentDevices()
    }

    private func handleInput(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == kHIDPage_KeyboardOrKeypad else { return }

        let device = IOHIDElementGetDevice(element)
        let pointer = devicePointer(device)
        let instance: KeyboardDeviceInstance
        if let existing = devicesByPointer[pointer] {
            instance = existing
        } else {
            instance = KeyboardDeviceInstance(reference: makeReference(for: device))
            devicesByPointer[pointer] = instance
            publishCurrentDevices()
        }

        let observedAt = DispatchTime.now().uptimeNanoseconds
        guard let event = deviceState.handle(
            device: instance,
            usage: IOHIDElementGetUsage(element),
            value: IOHIDValueGetIntegerValue(value),
            timestamp: IOHIDValueGetTimeStamp(value),
            observedAtNanoseconds: observedAt
        ) else { return }

        onInputEvent?(event)
    }

    private func handleCallbackFailure() {
        guard let manager else { return }
        deviceState.cancel()
        devicesByPointer.removeAll()
        publish(devices: [])
        statusAfterCancellation = .failed
        IOHIDManagerCancel(manager)
    }

    private func makeReference(for device: IOHIDDevice) -> KeyboardDeviceReference {
        KeyboardDeviceIdentity(
            vendorID: intProperty(device, key: kIOHIDVendorIDKey),
            productID: intProperty(device, key: kIOHIDProductIDKey),
            transport: stringProperty(device, key: kIOHIDTransportKey),
            productName: stringProperty(device, key: kIOHIDProductKey) ?? "Keyboard",
            serialNumber: stringProperty(device, key: kIOHIDSerialNumberKey),
            isBuiltIn: boolProperty(device, key: kIOHIDBuiltInKey) ?? false
        ).reference
    }

    private func publishCurrentDevices() {
        let snapshots = devicesByPointer.values
            .map { instance in
                KeyboardDeviceSnapshot(
                    id: instance.id,
                    reference: instance.reference,
                    bindingAvailability: bindingAvailability(for: instance.reference)
                )
            }
            .sorted { $0.reference.displayName.localizedStandardCompare($1.reference.displayName) == .orderedAscending }
        publish(devices: snapshots)
    }

    private func bindingAvailability(
        for reference: KeyboardDeviceReference
    ) -> KeyboardDeviceSnapshot.BindingAvailability {
        if reference.matchStrength == .builtIn {
            return .supported
        }

        let transport = reference.transport?.lowercased() ?? ""
        if transport.contains("bluetooth") {
            return .unverifiedBluetooth
        }
        if transport.contains("usb") {
            return .supported
        }
        return .unsupportedTransport
    }

    private func devicePointer(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func property(_ device: IOHIDDevice, key: String) -> AnyObject? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    private func stringProperty(_ device: IOHIDDevice, key: String) -> String? {
        property(device, key: key) as? String
    }

    private func intProperty(_ device: IOHIDDevice, key: String) -> Int? {
        (property(device, key: key) as? NSNumber)?.intValue
    }

    private func boolProperty(_ device: IOHIDDevice, key: String) -> Bool? {
        (property(device, key: key) as? NSNumber)?.boolValue
    }

    private func publish(status: Status) {
        DispatchQueue.main.async { [weak self] in
            self?.status = status
        }
    }

    private func publish(permissionStatus: KeyboardInputPermissionStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.permissionStatus = permissionStatus
        }
    }

    private func publish(devices: [KeyboardDeviceSnapshot]) {
        DispatchQueue.main.async { [weak self] in
            self?.connectedDevices = devices
        }
    }
}
