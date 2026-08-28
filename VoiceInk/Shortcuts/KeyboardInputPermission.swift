import IOKit.hid

enum KeyboardInputPermissionStatus: String, Sendable {
    case granted
    case denied
    case unknown
}

enum KeyboardInputPermission {
    static var currentStatus: KeyboardInputPermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .unknown
        }
    }

    @discardableResult
    static func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
