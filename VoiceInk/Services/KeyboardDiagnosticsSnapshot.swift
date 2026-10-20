import Foundation

/// A diagnostic snapshot contains status and counts only, never device identities or key events.
struct KeyboardDiagnosticsSnapshot {
    let permission: KeyboardInputPermissionStatus
    let monitorStatus: KeyboardDeviceMonitor.Status
    let connectedCount: Int
    let bindingCount: Int

    var report: String {
        let status: String
        switch monitorStatus {
        case .idle: status = "Stopped"
        case .listening: status = "Running"
        case .permissionDenied: status = "Permission Required"
        case .failed: status = "Unavailable"
        }
        return """
        Input Monitoring: \(permission.rawValue)
        Keyboard Monitor: \(status)
        Connected Keyboards: \(connectedCount)
        Device-Specific Shortcuts: \(bindingCount)
        """
    }
}
