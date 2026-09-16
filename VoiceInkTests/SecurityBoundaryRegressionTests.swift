import Foundation
import SwiftData
import Testing
@testable import VoiceInk

struct SecurityBoundaryRegressionTests {
    @Test("Custom command approval digest is bound to both mode and command")
    func customCommandApprovalDigestHasStableBoundaries() {
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let baseline = ModeCustomCommandApprovalStore.digest(modeID: firstID, command: "open -a TextEdit")
        #expect(baseline == ModeCustomCommandApprovalStore.digest(modeID: firstID, command: "open -a TextEdit"))
        #expect(baseline != ModeCustomCommandApprovalStore.digest(modeID: firstID, command: "open -a Notes"))
        #expect(baseline != ModeCustomCommandApprovalStore.digest(modeID: secondID, command: "open -a TextEdit"))
    }

    @Test("Unapproved persisted command cannot reach the execution configuration")
    @MainActor
    func unapprovedCustomCommandFailsClosedAtRuntime() {
        let mode = ModeConfig(
            name: "Tampered",
            isAIEnhancementEnabled: false,
            outputMode: .customCommand,
            customCommand: ModeCustomCommand(command: "open -a TextEdit")
        )

        let output = ModeRuntimeResolver.outputConfiguration(mode: mode)
        #expect(output.outputMode == .customCommand)
        #expect(output.customCommand == nil)
    }

    @Test(arguments: [
        ("https://example.com/inbox", "example.com", true),
        ("https://mail.example.com/inbox/42", "example.com/inbox", true),
        ("https://example.com/inbox-archive", "example.com/inbox", false),
        ("https://example.com.evil.test/inbox", "example.com", false),
        ("https://evil.test/?next=example.com/inbox", "example.com/inbox", false),
    ])
    func modeURLTriggerUsesHostAndPathBoundaries(
        currentURL: String,
        configuredURL: String,
        expected: Bool
    ) {
        #expect(ModeURLTriggerMatcher.matches(currentURL: currentURL, configuredURL: configuredURL) == expected)
    }

    @Test func modeWithoutStoredContextFlagsDefaultsToNoSensitiveCapture() throws {
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "name": "Legacy",
          "icon": {"kind":"symbol","value":"mic.fill"},
          "isAIEnhancementEnabled": true
        }
        """

        let mode = try JSONDecoder().decode(ModeConfig.self, from: Data(json.utf8))

        #expect(!mode.useSelectedTextContext)
        #expect(!mode.useScreenCapture)
    }

    @Test func starterModesDoNotCaptureSensitiveContextByDefault() {
        for template in StarterModeCatalog.templates {
            #expect(!template.useSelectedTextContext)
            #expect(!template.useScreenCapture)
        }
    }

    @Test(arguments: [
        "=HYPERLINK(\"https://attacker.example\")",
        "+1+1",
        "-2+3",
        "@SUM(1,2)",
        "  =1+1",
        "\u{FEFF}=1+1",
    ])
    func csvExportNeutralizesFormulaPrefixes(_ value: String) {
        let escaped = WaGongCSVExportService.escapeCSVString(value)
        #expect(escaped.hasPrefix("'") || escaped.hasPrefix("\"'"))
    }

    @Test(arguments: ["ordinary text", "123", "https://example.com"])
    func csvExportPreservesOrdinaryValues(_ value: String) {
        #expect(WaGongCSVExportService.escapeCSVString(value) == value)
    }

    @Test @MainActor func deliveryWaitsForPasteBeforeReturning() async {
        var didFinishPaste = false
        let transcription = Transcription(text: "test", duration: 1, transcriptionStatus: .completed)
        let delivery = TranscriptionDelivery()

        await delivery.deliver(
            .init(
                transcription: transcription,
                text: "test",
                output: .init(mode: nil, outputMode: .paste, autoSendKey: .none, customCommand: nil),
                responseConfig: nil,
                responseError: nil,
                isAssistantFollowUp: false,
                isCanceled: { false }
            ),
            actions: .init(
                setState: { _ in },
                dismiss: {},
                sendFollowUp: { _, _ in },
                showResponse: { _, _ in },
                failResponse: { _ in },
                pasteAtCursor: { _, _ in
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    didFinishPaste = true
                    return .commandPosted
                },
                autoSend: { _ in }
            )
        )

        #expect(didFinishPaste)
    }

    @Test func cancelingCustomCommandTerminatesTheAwaitedProcess() async {
        let task = Task {
            try await CustomCommandDeliveryRunner.run(
                command: "sleep 5",
                timeout: 10,
                context: .init(transcript: "test")
            )
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func cancelingCustomCommandTerminatesBackgroundDescendants() async {
        let testID = UUID().uuidString
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let ready = temporaryDirectory.appendingPathComponent("WaGongCommandReady-\(testID)")
        let gate = temporaryDirectory.appendingPathComponent("WaGongCommandGate-\(testID)")
        let sentinel = temporaryDirectory.appendingPathComponent("WaGongCommandSentinel-\(testID)")
        defer {
            try? FileManager.default.removeItem(at: ready)
            try? FileManager.default.removeItem(at: gate)
            try? FileManager.default.removeItem(at: sentinel)
        }
        let task = Task {
            try await CustomCommandDeliveryRunner.run(
                command: "(printf ready > \(ready.path); while [ ! -e \(gate.path) ]; do sleep 0.01; done; printf survived > \(sentinel.path)) &",
                timeout: 10,
                context: .init(transcript: "test")
            )
        }

        let readyDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: ready.path),
            ContinuousClock.now < readyDeadline
        {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(FileManager.default.fileExists(atPath: ready.path))

        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        try? Data().write(to: gate)
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test func legacyCustomModelCredentialIsOmittedWhenReencoded() throws {
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "name": "legacy",
          "displayName": "Legacy",
          "description": "Legacy model",
          "apiEndpoint": "https://api.example.com/v1/audio/transcriptions",
          "modelName": "whisper-1",
          "isMultilingualModel": true,
          "supportedLanguages": {"en":"English"},
          "apiKey": "secret-value"
        }
        """

        let model = try JSONDecoder().decode(CustomCloudModel.self, from: Data(json.utf8))
        let reencoded = try JSONEncoder().encode(model)

        #expect(model.legacyAPIKeyForMigration == "secret-value")
        #expect(!String(decoding: reencoded, as: UTF8.self).contains("secret-value"))
        #expect(!String(decoding: reencoded, as: UTF8.self).contains("\"apiKey\""))
    }

    @Test @MainActor func privacySanitizerRemovesStoredAIRequestContent() {
        let transcription = Transcription(
            text: "transcript",
            duration: 1,
            transcriptionStatus: .completed
        )
        transcription.aiRequestSystemMessage = "selected text"
        transcription.aiRequestUserMessage = "screen context"

        let removed = TranscriptionPrivacyMigration.clearAIRequestContent(in: [transcription])

        #expect(removed == 1)
        #expect(transcription.aiRequestSystemMessage == nil)
        #expect(transcription.aiRequestUserMessage == nil)
    }
}
