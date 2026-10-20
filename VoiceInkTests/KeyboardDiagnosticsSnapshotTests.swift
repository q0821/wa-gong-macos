import Testing
@testable import VoiceInk

struct KeyboardDiagnosticsSnapshotTests {
    @Test func exportIncludesTheFourVisibleKeyboardDiagnostics() {
        let snapshot = KeyboardDiagnosticsSnapshot(
            permission: .granted, monitorStatus: .listening, connectedCount: 2, bindingCount: 2
        )
        #expect(snapshot.report == """
        Input Monitoring: granted
        Keyboard Monitor: Running
        Connected Keyboards: 2
        Device-Specific Shortcuts: 2
        """)
    }

    @Test func failedMonitorIsNotReportedAsRunningOrMissingData() {
        let snapshot = KeyboardDiagnosticsSnapshot(
            permission: .denied, monitorStatus: .failed, connectedCount: 0, bindingCount: 2
        )
        #expect(snapshot.report.contains("Input Monitoring: denied"))
        #expect(snapshot.report.contains("Keyboard Monitor: Unavailable"))
        #expect(snapshot.report.contains("Connected Keyboards: 0"))
        #expect(snapshot.report.contains("Device-Specific Shortcuts: 2"))
    }
}
