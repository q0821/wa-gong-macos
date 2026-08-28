import AppKit
import IOKit.hid

enum KeyboardInputPermissionStatus: String, Sendable {
    case granted
    case denied
    case unknown

    init(accessType: IOHIDAccessType) {
        switch accessType {
        case kIOHIDAccessTypeGranted:
            self = .granted
        case kIOHIDAccessTypeDenied:
            self = .denied
        default:
            self = .unknown
        }
    }
}

enum KeyboardInputPermission {
    static var currentStatus: KeyboardInputPermissionStatus {
        KeyboardInputPermissionStatus(
            accessType: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        )
    }

    @discardableResult
    static func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    @discardableResult
    static func openSystemSettings() -> Bool {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return true
            }
        }
        return false
    }
}
