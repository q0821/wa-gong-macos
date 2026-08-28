import SwiftUI

struct ShortcutBindingControl: View {
    let action: ShortcutAction
    let defaultShortcut: Shortcut?
    let onShortcutChanged: () -> Void

    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @State private var bindings: [ShortcutBinding]
    @State private var draftDevice: KeyboardDeviceSnapshot?
    @State private var isShowingDevicePicker = false

    init(
        action: ShortcutAction,
        defaultShortcut: Shortcut? = nil,
        onShortcutChanged: @escaping () -> Void = {}
    ) {
        self.action = action
        self.defaultShortcut = defaultShortcut
        self.onShortcutChanged = onShortcutChanged
        _bindings = State(initialValue: ShortcutStore.bindings(for: action))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                ShortcutRecorder(
                    action: action,
                    defaultShortcut: defaultShortcut,
                    onShortcutChanged: didChangeShortcut
                )

                Button {
                    prepareDevicePicker()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("Add device-specific shortcut")
                .accessibilityLabel("Add device-specific shortcut")
                .popover(isPresented: $isShowingDevicePicker, arrowEdge: .bottom) {
                    KeyboardDevicePicker(
                        monitor: recordingShortcutManager.keyboardMonitor,
                        onSelect: { device in
                            draftDevice = device
                            isShowingDevicePicker = false
                        }
                    )
                }
            }

            ForEach(deviceBindings) { binding in
                deviceBindingRow(binding)
            }

            if let draftDevice,
                !bindings.contains(where: { bindingMatches($0, device: draftDevice.reference) })
            {
                deviceRecorderRow(
                    bindingID: UUID(),
                    shortcut: nil,
                    device: draftDevice
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
            guard let changedAction = notification.object as? ShortcutAction, changedAction == action else { return }
            reloadBindings()
        }
    }

    private var deviceBindings: [ShortcutBinding] {
        bindings.filter { binding in
            if case .device = binding.scope { return true }
            return false
        }
    }

    @ViewBuilder
    private func deviceBindingRow(_ binding: ShortcutBinding) -> some View {
        if case .device(let reference) = binding.scope {
            let connectedDevice = recordingShortcutManager.keyboardMonitor.connectedDevices.first {
                reference.matches($0.reference)
            }
            HStack(spacing: 6) {
                Text(reference.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(reference.displayName)

                if let connectedDevice {
                    DeviceShortcutRecorder(
                        action: action,
                        bindingID: binding.id,
                        currentShortcut: binding.shortcut,
                        device: connectedDevice,
                        attributionBroker: recordingShortcutManager.keyboardEventAttributionBroker,
                        onSaved: didChangeShortcut
                    )
                } else {
                    ShortcutVisualization(shortcut: binding.shortcut, isRecording: false)
                        .opacity(0.65)
                        .help("Keyboard disconnected")
                }

                Button {
                    if ShortcutStore.removeBinding(id: binding.id, for: action) {
                        didChangeShortcut()
                    }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .help("Delete device-specific shortcut")
                .accessibilityLabel("Delete \(reference.displayName) shortcut")
            }
            if reference.matchStrength == .modelFamily {
                Text("Applies to every connected keyboard of this model")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deviceRecorderRow(
        bindingID: UUID,
        shortcut: Shortcut?,
        device: KeyboardDeviceSnapshot
    ) -> some View {
        HStack(spacing: 6) {
            Text(device.reference.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            DeviceShortcutRecorder(
                action: action,
                bindingID: bindingID,
                currentShortcut: shortcut,
                device: device,
                attributionBroker: recordingShortcutManager.keyboardEventAttributionBroker,
                onSaved: {
                    draftDevice = nil
                    didChangeShortcut()
                }
            )

            Button {
                draftDevice = nil
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
    }

    private func prepareDevicePicker() {
        let monitor = recordingShortcutManager.keyboardMonitor
        if KeyboardInputPermission.currentStatus == .granted {
            monitor.start()
        } else {
            monitor.refreshPermissionStatus()
        }
        isShowingDevicePicker = true
    }

    private func bindingMatches(_ binding: ShortcutBinding, device: KeyboardDeviceReference) -> Bool {
        guard case .device(let reference) = binding.scope else { return false }
        return reference.overlaps(device)
    }

    private func reloadBindings() {
        bindings = ShortcutStore.bindings(for: action)
    }

    private func didChangeShortcut() {
        reloadBindings()
        onShortcutChanged()
    }
}

private struct KeyboardDevicePicker: View {
    @ObservedObject var monitor: KeyboardDeviceMonitor
    let onSelect: (KeyboardDeviceSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose Keyboard")
                .font(.headline)

            if monitor.permissionStatus != .granted {
                Text("Input Monitoring access is required to identify which keyboard sent a shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if monitor.permissionStatus == .denied {
                    Button("Open Input Monitoring Settings") {
                        KeyboardInputPermission.openSystemSettings()
                    }
                } else {
                    Button("Allow Input Monitoring") {
                        monitor.requestAccessAndStart()
                    }
                }
            } else if monitor.connectedDevices.isEmpty {
                ProgressView("Searching for keyboards…")
                    .controlSize(.small)
            } else {
                ForEach(monitor.connectedDevices) { device in
                    Button {
                        onSelect(device)
                    } label: {
                        HStack {
                            Text(device.reference.displayName)
                            Spacer()
                            if device.bindingAvailability == .unverifiedBluetooth {
                                Text("Bluetooth is not verified yet")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(device.bindingAvailability != .supported)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 280)
    }
}

private struct DeviceShortcutRecorder: View {
    let action: ShortcutAction
    let bindingID: UUID
    let currentShortcut: Shortcut?
    let device: KeyboardDeviceSnapshot
    let attributionBroker: KeyboardEventAttributionBroker
    let onSaved: () -> Void

    @StateObject private var recorder = ShortcutRecorderModel()
    @State private var shortcut: Shortcut?
    @State private var recorderID = UUID()

    init(
        action: ShortcutAction,
        bindingID: UUID,
        currentShortcut: Shortcut?,
        device: KeyboardDeviceSnapshot,
        attributionBroker: KeyboardEventAttributionBroker,
        onSaved: @escaping () -> Void
    ) {
        self.action = action
        self.bindingID = bindingID
        self.currentShortcut = currentShortcut
        self.device = device
        self.attributionBroker = attributionBroker
        self.onSaved = onSaved
        _shortcut = State(initialValue: currentShortcut)
    }

    var body: some View {
        Button {
            if recorder.isRecording {
                recorder.cancel()
            } else {
                NotificationCenter.default.post(
                    name: ShortcutRecorder.shortcutRecordingDidStart,
                    object: recorderID
                )
                recorder.start(
                    action: action,
                    scope: .device(device.reference),
                    requiredSourceID: device.id,
                    attributionBroker: attributionBroker
                ) { newShortcut in
                    let binding = ShortcutBinding(
                        id: bindingID,
                        shortcut: newShortcut,
                        scope: .device(device.reference)
                    )
                    if ShortcutStore.upsertBinding(binding, for: action) {
                        shortcut = newShortcut
                        onSaved()
                    }
                }
            }
        } label: {
            ShortcutVisualization(
                shortcut: recorder.isRecording ? recorder.previewShortcut : shortcut,
                isRecording: recorder.isRecording
            )
        }
        .buttonStyle(.plain)
        .help(
            recorder.isRecording
                ? "Press shortcut on \(device.reference.displayName)"
                : "Record shortcut again"
        )
        .accessibilityLabel(
            recorder.isRecording
                ? "Press shortcut on \(device.reference.displayName)"
                : "\(device.reference.displayName) shortcut"
        )
        .onReceive(NotificationCenter.default.publisher(for: ShortcutRecorder.shortcutRecordingDidStart)) {
            notification in
            guard let activeID = notification.object as? UUID, activeID != recorderID else { return }
            recorder.cancel()
        }
        .onDisappear {
            recorder.cancel()
        }
    }
}
