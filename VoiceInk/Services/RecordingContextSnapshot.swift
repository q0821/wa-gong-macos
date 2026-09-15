import AppKit
import Foundation

struct RecordingContextSnapshot {
    var capturedAt = Date()
    var selectedText: String?
    var screenText: String?
}

struct RecordingContextCapturePlan: Equatable {
    let captureSelectedText: Bool
    let captureScreenText: Bool

    static let none = RecordingContextCapturePlan(captureSelectedText: false, captureScreenText: false)

    init(captureSelectedText: Bool, captureScreenText: Bool) {
        self.captureSelectedText = captureSelectedText
        self.captureScreenText = captureScreenText
    }

    init(configuration: EnhancementRuntimeConfiguration) {
        guard configuration.isEnabled, configuration.provider != nil else {
            self = .none
            return
        }

        self.init(
            captureSelectedText: configuration.useSelectedTextContext,
            captureScreenText: configuration.useScreenCaptureContext
        )
    }
}

@MainActor
final class RecordingContextSnapshotStore {
    private(set) var snapshot = RecordingContextSnapshot()

    func updateSelectedText(_ text: String?) {
        snapshot.selectedText = Self.normalized(text)
    }

    func updateScreenText(_ text: String?) {
        snapshot.screenText = Self.normalized(text)
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
enum RecordingContextCaptureService {
    static func startCapture(
        into store: RecordingContextSnapshotStore,
        plan: RecordingContextCapturePlan
    ) -> [Task<Void, Never>] {
        var tasks: [Task<Void, Never>] = []

        if plan.captureSelectedText {
            tasks.append(Task { @MainActor in
                guard !Task.isCancelled else { return }
                let selectedText = await SelectedTextService.fetchSelectedText()
                guard !Task.isCancelled else { return }
                store.updateSelectedText(selectedText)
            })
        }

        if plan.captureScreenText {
            tasks.append(Task { @MainActor in
                guard CGPreflightScreenCaptureAccess(), !Task.isCancelled else { return }
                let screenCaptureService = ScreenCaptureService()
                let screenText = await screenCaptureService.captureAndExtractText()
                guard !Task.isCancelled else { return }
                store.updateScreenText(screenText)
            })
        }

        return tasks
    }
}
