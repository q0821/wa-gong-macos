import CoreGraphics
import Testing
@testable import VoiceInk

struct RecordingContextCapturePolicyTests {
    @Test func disabledEnhancementCapturesNoContext() {
        let configuration = EnhancementRuntimeConfiguration(
            mode: nil,
            isEnabled: false,
            prompt: nil,
            provider: .openAI,
            modelName: "gpt-5",
            useClipboardContext: false,
            useSelectedTextContext: true,
            useScreenCaptureContext: true
        )

        #expect(RecordingContextCapturePlan(configuration: configuration) == .none)
    }

    @Test func capturePlanIncludesOnlyExplicitlyEnabledContext() {
        let configuration = EnhancementRuntimeConfiguration(
            mode: nil,
            isEnabled: true,
            prompt: nil,
            provider: .openAI,
            modelName: "gpt-5",
            useClipboardContext: false,
            useSelectedTextContext: true,
            useScreenCaptureContext: false
        )

        #expect(
            RecordingContextCapturePlan(configuration: configuration)
                == RecordingContextCapturePlan(captureSelectedText: true, captureScreenText: false)
        )
    }

    @Test func ambiguousOrMissingFocusDoesNotChooseAnArbitraryWindow() {
        let windows = [
            ScreenWindowDescriptor(id: 1, processID: 10, title: "One", frame: CGRect(x: 0, y: 0, width: 500, height: 500)),
            ScreenWindowDescriptor(id: 2, processID: 10, title: "Two", frame: CGRect(x: 500, y: 0, width: 500, height: 500)),
            ScreenWindowDescriptor(id: 3, processID: 20, title: "Other", frame: CGRect(x: 0, y: 0, width: 500, height: 500)),
        ]

        #expect(FocusedScreenWindowResolver.resolveWindowID(in: windows, hint: nil) == nil)
        #expect(
            FocusedScreenWindowResolver.resolveWindowID(
                in: windows,
                hint: FocusedScreenWindowDescriptor(processID: 10, title: nil, frame: nil)
            ) == nil
        )
    }

    @Test func uniqueFocusedWindowCanBeResolvedByTitle() {
        let windows = [
            ScreenWindowDescriptor(id: 1, processID: 10, title: "Document", frame: .zero),
            ScreenWindowDescriptor(id: 2, processID: 10, title: "Settings", frame: .zero),
        ]

        #expect(
            FocusedScreenWindowResolver.resolveWindowID(
                in: windows,
                hint: FocusedScreenWindowDescriptor(processID: 10, title: "Document", frame: nil)
            ) == 1
        )
    }

    @Test func equalFrameMatchesRemainAmbiguous() {
        let focusedFrame = CGRect(x: 10, y: 10, width: 500, height: 500)
        let windows = [
            ScreenWindowDescriptor(id: 1, processID: 10, title: "One", frame: focusedFrame),
            ScreenWindowDescriptor(id: 2, processID: 10, title: "Two", frame: focusedFrame),
        ]

        #expect(
            FocusedScreenWindowResolver.resolveWindowID(
                in: windows,
                hint: FocusedScreenWindowDescriptor(processID: 10, title: nil, frame: focusedFrame)
            ) == nil
        )
    }
}
