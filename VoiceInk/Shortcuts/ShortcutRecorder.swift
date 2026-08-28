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
            guard sourceID(for: event) == requiredSourceID else {
                return false
            }
        }

        switch event.type {
        case .keyDown:
            return handleKeyDown(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        case .flagsChanged:
            return handleFlagsChanged(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        default:
            return false
        }
    }

    private func sourceID(for event: NSEvent) -> UUID? {
        guard let attributionBroker, let cgEvent = event.cgEvent else { return nil }
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
        let token = ShortcutEventToken(
            eventTimestamp: cgEvent.timestamp,
            keyCode: event.keyCode,
            transition: transition
        )
        return attributionBroker.attribution(for: token)?.sourceID
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
