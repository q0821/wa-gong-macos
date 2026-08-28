import AppKit
import SwiftUI

enum AppNotificationPlacement {
    case defaultBottom
    case recorderAdjacent(MiniRecorderPosition)
}

enum PrivacyNotificationLayout {
    static func origin(
        in visibleFrame: NSRect,
        notificationSize: NSSize,
        recorderHeight: CGFloat,
        edgePadding: CGFloat,
        spacing: CGFloat,
        position: MiniRecorderPosition
    ) -> NSPoint {
        let proposedX = visibleFrame.midX - notificationSize.width / 2
        let minimumX = visibleFrame.minX + edgePadding
        let maximumX = visibleFrame.maxX - edgePadding - notificationSize.width
        let x = min(max(proposedX, minimumX), max(minimumX, maximumX))

        let proposedY: CGFloat
        switch position {
        case .top:
            let recorderBottom = visibleFrame.maxY - edgePadding - recorderHeight
            proposedY = recorderBottom - spacing - notificationSize.height
        case .bottom:
            let recorderTop = visibleFrame.minY + edgePadding + recorderHeight
            proposedY = recorderTop + spacing
        }

        let minimumY = visibleFrame.minY + edgePadding
        let maximumY = visibleFrame.maxY - edgePadding - notificationSize.height
        let y = min(max(proposedY, minimumY), max(minimumY, maximumY))
        return NSPoint(x: x, y: y)
    }
}

class NotificationManager {
    static let shared = NotificationManager()

    private var notificationWindow: NSPanel?
    private var dismissTimer: Timer?

    private init() {}

    @MainActor
    func showNotification(
        title: String,
        type: AppNotificationView.NotificationType,
        duration: TimeInterval = 3.0,
        placement: AppNotificationPlacement = .defaultBottom,
        onTap: (() -> Void)? = nil,
        actionButton: (label: String, action: () -> Void)? = nil
    ) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        if let existingWindow = notificationWindow {
            existingWindow.close()
            notificationWindow = nil
        }

        // Play esc sound for error notifications
        if type == .error {
            SoundManager.shared.playEscSound()
        }

        let notificationView = AppNotificationView(
            title: title,
            type: type,
            duration: duration,
            onClose: { [weak self] in
                Task { @MainActor in
                    self?.dismissNotification()
                }
            },
            onTap: onTap,
            actionButton: actionButton
        )
        let hostingController = NSHostingController(rootView: notificationView)
        let size = hostingController.view.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingController.view
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level.mainMenu
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false

        positionWindow(panel, placement: placement)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil as Any?)

        self.notificationWindow = panel

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        })

        // Schedule a new timer to dismiss the new notification.
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: duration,
            repeats: false
        ) { [weak self] _ in
            self?.dismissNotification()
        }
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, placement: AppNotificationPlacement) {
        let activeScreen: NSScreen
        switch placement {
        case .defaultBottom:
            activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        case .recorderAdjacent:
            activeScreen = NSScreen.main ?? NSScreen.screens[0]
        }

        let screenRect = activeScreen.visibleFrame
        let notificationRect = window.frame

        switch placement {
        case .defaultBottom:
            let notificationX = screenRect.midX - notificationRect.width / 2
            let bottomPadding: CGFloat = 24
            let componentHeight: CGFloat = 34
            let notificationSpacing: CGFloat = 16
            let notificationY = screenRect.minY + bottomPadding + componentHeight + notificationSpacing
            window.setFrameOrigin(NSPoint(x: notificationX, y: notificationY))
        case .recorderAdjacent(let position):
            window.setFrameOrigin(
                PrivacyNotificationLayout.origin(
                    in: screenRect,
                    notificationSize: notificationRect.size,
                    recorderHeight: MiniRecorderPanel.visibleControlBarHeight,
                    edgePadding: MiniRecorderPanel.edgePadding,
                    spacing: 16,
                    position: position
                )
            )
        }
    }

    @MainActor
    func dismissNotification() {
        guard let window = notificationWindow else { return }

        notificationWindow = nil

        dismissTimer?.invalidate()
        dismissTimer = nil

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            },
            completionHandler: {
                window.close()

            })
    }
}
