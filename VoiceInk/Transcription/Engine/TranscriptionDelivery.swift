import Foundation
import os

@MainActor
final class TranscriptionDelivery {
    private let logger = Logger(subsystem: "com.jackie-yeh.wagong", category: "TranscriptionDelivery")

    struct Request {
        let transcription: Transcription
        let text: String?
        let output: OutputRuntimeConfiguration
        let responseConfig: EnhancementRuntimeConfiguration?
        let responseError: String?
        let isAssistantFollowUp: Bool
        let isCanceled: () -> Bool
    }

    struct Actions {
        let setState: (RecordingState) -> Void
        let dismiss: () async -> Void
        let sendFollowUp: (String, Transcription) async -> Void
        let showResponse: (String, String?) async -> Void
        let failResponse: (String) async -> Void
        let pasteAtCursor: (String, @escaping () -> Bool) async -> CursorPaster.PasteResult
        let autoSend: (AutoSendKey) -> Void
    }

    func deliver(_ request: Request, actions: Actions) async {
        guard !request.isCanceled() else {
            await actions.dismiss()
            return
        }

        guard request.transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue else {
            await actions.dismiss()
            return
        }

        if request.isAssistantFollowUp {
            await deliverFollowUp(request, actions: actions)
            return
        }

        if request.output.outputMode == .respond,
            request.responseConfig != nil || request.responseError != nil
        {
            await deliverResponse(request, actions: actions)
            return
        }

        if request.output.outputMode == .customCommand {
            await deliverCustomCommand(request, actions: actions)
            return
        }

        if let text = request.text {
            await paste(
                text,
                output: request.output,
                isCanceled: request.isCanceled,
                actions: actions
            )
        } else {
            await actions.dismiss()
        }
    }

    private func deliverFollowUp(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()

        guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty,
            !item.isCanceled()
        else {
            return
        }

        actions.setState(.enhancing)
        guard !item.isCanceled() else { return }
        await actions.sendFollowUp(text, item.transcription)
    }

    private func deliverResponse(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()

        if let responseError = item.responseError {
            await actions.failResponse("Enhancement failed: \(responseError)")
        } else if let text = item.text,
            item.responseConfig != nil
        {
            await actions.showResponse(text, item.transcription.aiRequestSystemMessage)
        } else {
            await actions.failResponse("No response was generated.")
        }
    }

    private func deliverCustomCommand(_ item: Request, actions: Actions) async {
        guard let text = item.text else {
            notifyCustomCommandFailure(CustomCommandDeliveryError.noTextToDeliver)
            SoundManager.shared.playStopSound()
            await actions.dismiss()
            return
        }

        guard let customCommand = item.output.customCommand,
            let command = customCommand.trimmedCommand
        else {
            notifyCustomCommandFailure(CustomCommandDeliveryError.commandNotConfigured)
            SoundManager.shared.playStopSound()
            await actions.dismiss()
            return
        }

        let commandText = deliverableText(from: text)
        guard !item.isCanceled() else {
            await actions.dismiss()
            return
        }

        SoundManager.shared.playStopSound()
        await actions.dismiss()

        Task {
            guard !item.isCanceled() else { return }
            await runCustomCommand(command: command, commandText: commandText)
        }
    }

    private func runCustomCommand(command: String, commandText: String) async {
        let startTime = Date()
        logger.notice("Custom command started")

        do {
            let result = try await CustomCommandDeliveryRunner.run(
                command: command,
                timeout: 10,
                context: CustomCommandDeliveryContext(transcript: commandText)
            )

            let duration = Date().timeIntervalSince(startTime)
            let stdoutBytes = result.stdout.utf8.count
            let stderrBytes = result.stderr.utf8.count

            logger.notice(
                "Custom command completed duration=\(Self.formattedDuration(duration), privacy: .public)s status=\(result.status, privacy: .public) stdoutBytes=\(stdoutBytes, privacy: .public) stderrBytes=\(stderrBytes, privacy: .public)"
            )
        } catch {
            notifyCustomCommandFailure(error, duration: Date().timeIntervalSince(startTime))
        }
    }

    private func notifyCustomCommandFailure(_ error: Error, duration: TimeInterval? = nil) {
        let errorType = String(describing: type(of: error))
        if let duration {
            logger.error(
                "Custom command failed duration=\(Self.formattedDuration(duration), privacy: .public)s errorType=\(errorType, privacy: .public)"
            )
        } else {
            logger.error("Custom command failed errorType=\(errorType, privacy: .public)")
        }
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        String(format: "%.3f", duration)
    }

    private func paste(
        _ text: String,
        output: OutputRuntimeConfiguration,
        isCanceled: @escaping () -> Bool,
        actions: Actions
    ) async {
        let textToPaste = deliverableText(from: text)
        let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
        let pastedText = textToPaste + (appendSpace ? " " : "")

        guard !isCanceled() else {
            await actions.dismiss()
            return
        }

        SoundManager.shared.playStopSound()
        await actions.dismiss()

        guard !isCanceled() else { return }

        let pasteTask = Task { @MainActor in
            await actions.pasteAtCursor(pastedText, isCanceled)
        }

        let autoSendKey = output.outputMode == .paste ? output.autoSendKey : .none
        Task { @MainActor in
            let pasteResult = await pasteTask.value

            if pasteResult.didPostPasteCommand, !isCanceled(), autoSendKey.isEnabled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !isCanceled() else { return }
                actions.autoSend(autoSendKey)
            }
        }
    }

    private func deliverableText(from text: String) -> String {
        text
    }
}
