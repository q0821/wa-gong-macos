import SwiftUI

struct DiagnosticsSettingsView: View {
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @State private var isExportingLogs = false
    @State private var exportedLogURL: URL?
    @State private var showLogExportError = false
    @State private var logExportError: String = ""

    var body: some View {
        Group {
            KeyboardDiagnosticsRows(
                monitor: recordingShortcutManager.keyboardMonitor,
                deviceBindingCount: recordingShortcutManager.deviceBindingCount
            )

            LabeledContent {
                HStack(spacing: 8) {
                    if let url = exportedLogURL {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppTheme.Status.positive)
                    }

                    Button("Export") {
                        exportDiagnosticLogs()
                    }
                    .disabled(isExportingLogs)
                }
            } label: {
                HStack(spacing: 4) {
                    if isExportingLogs {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Export Logs")
                }
            }
        }
        .alert("Export Failed", isPresented: $showLogExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(logExportError)
        }
    }

    private func exportDiagnosticLogs() {
        isExportingLogs = true
        exportedLogURL = nil

        Task {
            do {
                let url = try await LogExporter.shared.exportLogs()
                await MainActor.run {
                    exportedLogURL = url
                    isExportingLogs = false
                }
            } catch {
                await MainActor.run {
                    logExportError = error.localizedDescription
                    showLogExportError = true
                    isExportingLogs = false
                }
            }
        }
    }
}

private struct KeyboardDiagnosticsRows: View {
    @ObservedObject var monitor: KeyboardDeviceMonitor
    let deviceBindingCount: Int

    var body: some View {
        LabeledContent("Input Monitoring") {
            Text(inputMonitoringStatus)
                .foregroundStyle(.secondary)
        }

        LabeledContent("Keyboard Monitor") {
            Text(keyboardMonitorStatus)
                .foregroundStyle(.secondary)
        }

        LabeledContent("Connected Keyboards") {
            Text("\(monitor.connectedDevices.count)")
                .foregroundStyle(.secondary)
        }

        LabeledContent("Device-Specific Shortcuts") {
            Text("\(deviceBindingCount)")
                .foregroundStyle(.secondary)
        }
    }

    private var inputMonitoringStatus: LocalizedStringKey {
        switch monitor.permissionStatus {
        case .granted: return "Allowed"
        case .denied: return "Not Allowed"
        case .unknown: return "Not Requested"
        }
    }

    private var keyboardMonitorStatus: LocalizedStringKey {
        switch monitor.status {
        case .listening: return "Running"
        case .permissionDenied: return "Permission Required"
        case .failed: return "Unavailable"
        case .idle: return "Stopped"
        }
    }
}
