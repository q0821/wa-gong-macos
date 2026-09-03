import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: View {
    let action: ShortcutAction
    let defaultShortcut: Shortcut?
    let onShortcutChanged: () -> Void

    @StateObject private var recorder = ShortcutRecorderModel()
    @State private var recorderID = UUID()
    @State private var shortcut: Shortcut?

    init(
        action: ShortcutAction,
        defaultShortcut: Shortcut? = nil,
        onShortcutChanged: @escaping () -> Void = {}
    ) {
        self.action = action
        self.defaultShortcut = defaultShortcut
        self.onShortcutChanged = onShortcutChanged
        _shortcut = State(initialValue: ShortcutStore.shortcut(for: action))
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if recorder.isRecording {
                    recorder.cancel()
                } else {
                    NotificationCenter.default.post(
                        name: Self.shortcutRecordingDidStart,
                        object: recorderID
                    )
                    recorder.start(action: action, scope: .allKeyboards) { newShortcut in
                        let binding = ShortcutBinding(
                            id: ShortcutStore.allKeyboardBinding(for: action)?.id ?? UUID(),
                            shortcut: newShortcut,
                            scope: .allKeyboards
                        )
                        if ShortcutStore.upsertBinding(binding, for: action) {
                            shortcut = newShortcut
                            onShortcutChanged()
                        }
                    }
                }
            } label: {
                ShortcutVisualization(
                    shortcut: displayedShortcut,
                    isRecording: recorder.isRecording
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .help(accessibilityLabel)

            if !recorder.isRecording, displayedShortcut != nil {
                Button {
                    clearShortcut()
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
            guard let changedAction = notification.object as? ShortcutAction, changedAction == action else { return }
            shortcut = ShortcutStore.shortcut(for: action)
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.shortcutRecordingDidStart)) { notification in
            guard let activeRecorderID = notification.object as? UUID, activeRecorderID != recorderID else { return }
            recorder.cancel()
        }
        .onChange(of: action) { _, newAction in
            recorder.cancel()
            recorderID = UUID()
            shortcut = ShortcutStore.shortcut(for: newAction)
        }
        .onDisappear {
            recorder.cancel()
        }
    }

    private var accessibilityLabel: String {
        if recorder.isRecording {
            return recorder.previewShortcut?.displayString ?? String(localized: "Press shortcut")
        }

        return displayedShortcut?.displayString ?? String(localized: "Record shortcut")
    }

    private var displayedShortcut: Shortcut? {
        if recorder.isRecording {
            return recorder.previewShortcut
        }

        return ShortcutDisplayResolver.resolve(
            storedShortcut: shortcut,
            defaultShortcut: defaultShortcut,
            isExplicitlyCleared: ShortcutStore.isShortcutCleared(for: action)
        )
    }

    private func clearShortcut() {
        recorder.cancel()
        ShortcutStore.setShortcut(nil, for: action)
        shortcut = nil
        onShortcutChanged()
    }

    static let shortcutRecordingDidStart = Notification.Name("ShortcutRecorderRecordingDidStart")
}

enum ShortcutDisplayResolver {
    static func resolve(
        storedShortcut: Shortcut?,
        defaultShortcut: Shortcut?,
        isExplicitlyCleared: Bool
    ) -> Shortcut? {
        if let storedShortcut {
            return storedShortcut
        }
        return isExplicitlyCleared ? nil : defaultShortcut
    }
}

struct ShortcutVisualization: View {
    let shortcut: Shortcut?
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let shortcut {
                ForEach(Array(shortcut.displayTokens.enumerated()), id: \.offset) { _, token in
                    ShortcutKeyCap(title: token, isRecording: isRecording)
                }
            } else {
                Text(isRecording ? LocalizedStringKey("Press shortcut") : LocalizedStringKey("Record"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isRecording ? .primary : .secondary)
            }
        }
        .padding(4)
        .frame(minWidth: shortcut == nil ? 104 : nil, minHeight: 26)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isRecording ? AppTheme.Accent.fill : AppTheme.Surface.control)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isRecording ? AppTheme.Accent.border : AppTheme.Border.subtle, lineWidth: 1)
        }
    }
}

private struct ShortcutKeyCap: View {
    let title: String
    let isRecording: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 5)
            .frame(minHeight: 18)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: 1)
            }
    }

    private var foregroundColor: Color {
        Color(NSColor.textBackgroundColor)
    }

    private var backgroundColor: Color {
        Color(NSColor.labelColor)
    }

    private var borderColor: Color {
        isRecording ? AppTheme.Accent.foreground : foregroundColor.opacity(0.28)
    }
}

final class ShortcutRecorderModel: ObservableObject {
    @Published var isRecording = false
    @Published var previewShortcut: Shortcut?

    private var localMonitor: Any?
    private var onCapture: ((Shortcut) -> Void)?
    private var activeAction: ShortcutAction?
    private var activeScope: KeyboardScope?
    private var pendingModifierShortcut: Shortcut?
    private var peakModifierFlags: NSEvent.ModifierFlags = []
    private var requiredSourceID: UUID?
    private var attributionBroker: KeyboardEventAttributionBroker?
    private var pendingAttributionTasks: [Task<Void, Never>] = []

    deinit {
        removeRecordingMonitor()
    }

    func start(
        action: ShortcutAction,
        scope: KeyboardScope,
        requiredSourceID: UUID? = nil,
        attributionBroker: KeyboardEventAttributionBroker? = nil,
        onCapture: @escaping (Shortcut) -> Void
    ) {
        cancel()

        activeAction = action
        activeScope = scope
        self.requiredSourceID = requiredSourceID
        self.attributionBroker = attributionBroker
        self.onCapture = onCapture
        isRecording = true
        previewShortcut = nil
        installRecordingMonitor()
    }

    func cancel() {
        removeRecordingMonitor()
        resetRecordingState()
    }

    private func finish(with shortcut: Shortcut) {
        guard let activeAction else {
            cancel()
            return
        }

        guard let activeScope else {
            cancel()
            return
        }

        let candidate = ShortcutBinding(shortcut: shortcut, scope: activeScope)
        if let validationError = ShortcutValidator.validationError(for: candidate, action: activeAction) {
            cancel()
            showErrorNotification(validationError.notificationTitle(for: shortcut))
            return
        }

        let capture = onCapture
        removeRecordingMonitor()
        resetRecordingState()

        capture?(shortcut)
    }

    private func resetRecordingState() {
        isRecording = false
        previewShortcut = nil
        onCapture = nil
        activeAction = nil
        activeScope = nil
        pendingModifierShortcut = nil
        peakModifierFlags = []
        requiredSourceID = nil
        attributionBroker = nil
        pendingAttributionTasks.forEach { $0.cancel() }
        pendingAttributionTasks.removeAll()
    }

    private func showErrorNotification(_ title: String) {
        Task { @MainActor in
            NotificationManager.shared.showNotification(
                title: title,
                type: .error
            )
        }
    }

    private func installRecordingMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let shouldConsume = self.handleRecordingEvent(event)
            return shouldConsume ? nil : event
        }
    }

    private func removeRecordingMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleRecordingEvent(_ event: NSEvent) -> Bool {
        guard isRecording else {
            return false
        }

        if let requiredSourceID {
            guard let attributionBroker, let token = eventToken(for: event) else {
                return false
            }

            if let attribution = attributionBroker.attribution(for: token) {
                guard attribution.sourceID == requiredSourceID else { return false }
                return handleAttributedRecordingEvent(event)
            }

            let eventType = event.type
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags
            let task = Task { @MainActor [weak self] in
                let attribution = await attributionBroker.attribution(
                    for: token,
                    waitingUpToNanoseconds: 75_000_000
                )
                guard !Task.isCancelled,
                    let self,
                    self.isRecording,
                    self.requiredSourceID == attribution?.sourceID
                else {
                    return
                }

                _ = self.handleAttributedRecordingEvent(
                    type: eventType,
                    keyCode: keyCode,
                    modifierFlags: modifierFlags
                )
            }
            pendingAttributionTasks.append(task)
            return true
        }

        return handleAttributedRecordingEvent(event)
    }

    private func handleAttributedRecordingEvent(_ event: NSEvent) -> Bool {
        handleAttributedRecordingEvent(
            type: event.type,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        )
    }

    private func handleAttributedRecordingEvent(
        type: NSEvent.EventType,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        switch type {
        case .keyDown:
            return handleKeyDown(keyCode: keyCode, modifierFlags: modifierFlags)
        case .flagsChanged:
            return handleFlagsChanged(keyCode: keyCode, modifierFlags: modifierFlags)
        default:
            return false
        }
    }

    private func eventToken(for event: NSEvent) -> ShortcutEventToken? {
        guard let cgEvent = event.cgEvent else { return nil }
        let transition: ShortcutEventToken.Transition
        switch event.type {
        case .keyDown:
            transition = .keyDown
        case .keyUp:
            transition = .keyUp
        case .flagsChanged:
            transition = .flagsChanged
        default:
            return nil
        }
        return ShortcutEventToken(
            eventTimestamp: cgEvent.timestamp,
            keyCode: event.keyCode,
            transition: transition
        )
    }

    private func handleKeyDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let modifiers = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: keyCode)

        if keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
            cancel()
            return true
        }

        guard !Shortcut.isModifierKeyCode(keyCode) else {
            return true
        }

        let shortcut = Shortcut.key(keyCode: keyCode, modifierFlags: modifiers)
        previewShortcut = shortcut
        finish(with: shortcut)
        return true
    }

    private func handleFlagsChanged(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let modifiers = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: keyCode)

        if modifiers.isEmpty,
            Shortcut.isFunctionKeyCode(keyCode),
            Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: nil).contains(.function)
        {
            return true
        }

        if !modifiers.isEmpty {
            peakModifierFlags.formUnion(modifiers)
            let singleModifierKeyCode = Shortcut.modifierKeyCodeForSingleModifierEvent(
                keyCode: keyCode,
                modifiers: peakModifierFlags
            )
            let shortcut = Shortcut.modifierOnly(
                keyCode: singleModifierKeyCode,
                modifierFlags: peakModifierFlags
            )

            pendingModifierShortcut = shortcut
            previewShortcut = shortcut
            return true
        }

        if let pendingModifierShortcut {
            finish(with: pendingModifierShortcut)
        }

        return true
    }
}

@MainActor
final class KeyboardDeviceVerificationModel: ObservableObject {
    enum State: Equatable {
        case idle
        case waiting
        case verified
        case timedOut
        case disconnected
        case differentDevice(displayName: String, transport: String)
    }

    @Published private(set) var state: State = .idle

    private var localMonitor: Any?
    private var timeoutTask: Task<Void, Never>?
    private var attributionTask: Task<Void, Never>?
    private var selectedSourceID: UUID?
    private var attributionBroker: KeyboardEventAttributionBroker?

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        timeoutTask?.cancel()
        attributionTask?.cancel()
    }

    func start(
        selectedSourceID: UUID,
        attributionBroker: KeyboardEventAttributionBroker,
        timeoutNanoseconds: UInt64 = 12_000_000_000
    ) {
        cancel()
        self.selectedSourceID = selectedSourceID
        self.attributionBroker = attributionBroker
        state = .waiting

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else { return }
            self?.finish(with: .timedOut)
        }
    }

    func markDisconnected() {
        guard state == .waiting else { return }
        finish(with: .disconnected)
    }

    func cancel() {
        guard state == .waiting else { return }
        removeEventMonitor()
        timeoutTask?.cancel()
        timeoutTask = nil
        attributionTask?.cancel()
        attributionTask = nil
        selectedSourceID = nil
        attributionBroker = nil
        state = .idle
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let cgEvent = event.cgEvent else { return false }
        let token = ShortcutEventToken(
            eventTimestamp: cgEvent.timestamp,
            keyCode: event.keyCode,
            transition: .keyDown
        )
        return handleVerificationKeyDown(token: token, isRepeat: event.isARepeat)
    }

    @discardableResult
    func handleVerificationKeyDown(token: ShortcutEventToken, isRepeat: Bool) -> Bool {
        guard state == .waiting, !isRepeat, let attributionBroker else {
            return false
        }

        attributionTask?.cancel()
        attributionTask = Task { [weak self] in
            let attribution = await attributionBroker.attribution(
                for: token,
                waitingUpToNanoseconds: 75_000_000
            )
            guard !Task.isCancelled,
                let self,
                self.state == .waiting,
                let selectedSourceID = self.selectedSourceID,
                let attribution
            else {
                return
            }

            if KeyboardDeviceVerificationPolicy.accepts(
                sourceID: attribution.sourceID,
                transition: .keyDown,
                selectedSourceID: selectedSourceID
            ) {
                self.finish(with: .verified)
            } else {
                self.finish(
                    with: .differentDevice(
                        displayName: attribution.device.displayName,
                        transport: attribution.device.transport ?? "Unknown"
                    )
                )
            }
        }
        return true
    }

    private func finish(with finalState: State) {
        removeEventMonitor()
        timeoutTask?.cancel()
        timeoutTask = nil
        attributionTask?.cancel()
        attributionTask = nil
        selectedSourceID = nil
        attributionBroker = nil
        state = finalState
    }

    private func removeEventMonitor() {
        guard let localMonitor else { return }
        NSEvent.removeMonitor(localMonitor)
        self.localMonitor = nil
    }
}
