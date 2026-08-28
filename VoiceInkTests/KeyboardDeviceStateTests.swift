import Testing
@testable import VoiceInk

struct KeyboardDeviceStateTests {
    @Test func keyDownRepeatAndKeyUpTransitionsAreDistinct() throws {
        var state = KeyboardDeviceState()
        state.activate()
        let device = makeDevice(fingerprint: "device-a")

        let downResult = state.handle(device: device, usage: 0x04, value: 1, timestamp: 1)
        let repeatedResult = state.handle(device: device, usage: 0x04, value: 1, timestamp: 2)
        let upResult = state.handle(device: device, usage: 0x04, value: 0, timestamp: 3)
        let down = try #require(downResult)
        let repeated = try #require(repeatedResult)
        let up = try #require(upResult)

        #expect(down.transition == .keyDown)
        #expect(repeated.transition == .repeatKeyDown)
        #expect(up.transition == .keyUp)
        #expect(up.pressedUsages.isEmpty)
    }

    @Test func modifierStateIsIsolatedPerDevice() throws {
        var state = KeyboardDeviceState()
        state.activate()
        let first = makeDevice(fingerprint: "device-a")
        let second = makeDevice(fingerprint: "device-b")

        let firstResult = state.handle(device: first, usage: 0xE2, value: 1, timestamp: 1)
        let secondResult = state.handle(device: second, usage: 0x04, value: 1, timestamp: 2)
        let firstEvent = try #require(firstResult)
        let secondEvent = try #require(secondResult)

        #expect(firstEvent.modifierUsages == [0xE2])
        #expect(secondEvent.modifierUsages.isEmpty)
        #expect(secondEvent.pressedUsages == [0x04])
    }

    @Test func identicalModelFingerprintsStillHaveIsolatedState() throws {
        var state = KeyboardDeviceState()
        state.activate()
        let first = makeDevice(fingerprint: "shared-model")
        let second = makeDevice(fingerprint: "shared-model")

        _ = state.handle(device: first, usage: 0xE1, value: 1, timestamp: 1)
        let result = state.handle(device: second, usage: 0x04, value: 1, timestamp: 2)
        let event = try #require(result)

        #expect(first.id != second.id)
        #expect(event.sourceID == second.id)
        #expect(event.modifierUsages.isEmpty)
    }

    @Test func leftAndRightModifiersRemainDistinct() throws {
        var state = KeyboardDeviceState()
        state.activate()
        let device = makeDevice(fingerprint: "device-a")

        _ = state.handle(device: device, usage: 0xE2, value: 1, timestamp: 1)
        let result = state.handle(device: device, usage: 0xE6, value: 1, timestamp: 2)
        let event = try #require(result)

        #expect(event.modifierUsages == [0xE2, 0xE6])
    }

    @Test func removingDeviceSynthesizesReleaseAndClearsState() {
        var state = KeyboardDeviceState()
        state.activate()
        let device = makeDevice(fingerprint: "device-a")
        _ = state.handle(device: device, usage: 0x04, value: 1, timestamp: 1)
        _ = state.handle(device: device, usage: 0xE1, value: 1, timestamp: 2)

        let releases = state.removeDevice(device, timestamp: 3)

        #expect(releases.count == 2)
        #expect(releases.allSatisfy { $0.transition == .keyUp })
        #expect(state.removeDevice(device, timestamp: 4).isEmpty)
    }

    @Test func cancelClearsStateAndIgnoresFutureInput() {
        var state = KeyboardDeviceState()
        state.activate()
        let device = makeDevice(fingerprint: "device-a")
        _ = state.handle(device: device, usage: 0x04, value: 1, timestamp: 1)

        state.cancel()

        #expect(state.handle(device: device, usage: 0x04, value: 0, timestamp: 2) == nil)
        #expect(state.removeDevice(device, timestamp: 3).isEmpty)
    }

    @Test func unsupportedUsageIsIgnored() {
        var state = KeyboardDeviceState()
        state.activate()

        #expect(state.handle(device: makeDevice(fingerprint: "device-a"), usage: 0x03, value: 1, timestamp: 1) == nil)
    }

    private func makeDevice(fingerprint: String) -> KeyboardDeviceInstance {
        KeyboardDeviceInstance(
            reference: KeyboardDeviceReference(
                fingerprint: fingerprint,
                vendorID: 1204,
                productID: 4621,
                transport: "USB",
                displayName: "Test Keyboard",
                matchStrength: .exact
            )
        )
    }
}
