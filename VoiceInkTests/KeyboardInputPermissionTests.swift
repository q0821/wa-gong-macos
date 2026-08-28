import IOKit.hid
import Testing
@testable import VoiceInk

struct KeyboardInputPermissionTests {
    @Test func mapsGrantedDeniedAndUnknownAccessTypes() {
        #expect(KeyboardInputPermissionStatus(accessType: kIOHIDAccessTypeGranted) == .granted)
        #expect(KeyboardInputPermissionStatus(accessType: kIOHIDAccessTypeDenied) == .denied)
        #expect(KeyboardInputPermissionStatus(accessType: kIOHIDAccessTypeUnknown) == .unknown)
    }
}
