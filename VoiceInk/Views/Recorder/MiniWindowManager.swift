import AppKit
import SwiftUI

@MainActor
class MiniWindowManager {
    private var windowController: NSWindowController?
    private var panel: MiniRecorderPanel?

    private let makeView: () -> AnyView
    private let position: MiniRecorderPosition

    init(
        engine: WaGongEngine,
        recorder: Recorder,
        assistantSession: AssistantSession,
        position: MiniRecorderPosition,
        onRecordButtonTapped: @escaping () -> Void,
        onCloseTapped: @escaping () -> Void,
        onAssistantFollowUp: @escaping (String) -> Void
    ) {
        self.position = position
        self.makeView = {
            AnyView(
                MiniRecorderView(
                    stateProvider: engine,
                    recorder: recorder,
                    assistantSession: assistantSession,
                    position: position,
                    onRecordButtonTapped: onRecordButtonTapped,
                    onCloseTapped: onCloseTapped,
                    onAssistantFollowUp: onAssistantFollowUp
                )
                .environment(\.locale, AppLanguagePreference.locale)
            )
        }
    }

    func show() {
        if panel == nil { initializeWindow() }
        panel?.show(position: position)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func destroyWindow() {
        deinitializeWindow()
    }

    private func initializeWindow() {
        deinitializeWindow()
        let metrics = MiniRecorderPanel.calculateWindowMetrics(position: position)
        let newPanel = MiniRecorderPanel(contentRect: metrics)
        let view = makeView()
        let hostingController = NSHostingController(rootView: view)
        newPanel.contentView = hostingController.view
        panel = newPanel
        windowController = NSWindowController(window: newPanel)
    }

    private func deinitializeWindow() {
        panel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        panel = nil
    }
}
