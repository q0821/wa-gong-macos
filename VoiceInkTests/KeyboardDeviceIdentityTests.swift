import Foundation
import Testing
@testable import VoiceInk

struct KeyboardDeviceIdentityTests {
    @Test func serialBackedFingerprintIsDeterministicAndDoesNotExposeSerial() {
        let serialNumber = "private-device-serial"
        let first = KeyboardDeviceIdentity(
            vendorID: 1204,
            productID: 4621,
            transport: "USB",
            productName: "Majestouch Convertible 2",
            serialNumber: serialNumber,
            isBuiltIn: false
        ).reference
        let second = KeyboardDeviceIdentity(
            vendorID: 1204,
            productID: 4621,
            transport: "USB",
            productName: "Majestouch Convertible 2",
            serialNumber: serialNumber,
            isBuiltIn: false
        ).reference

        #expect(first == second)
        #expect(first.matchStrength == .exact)
        #expect(!first.fingerprint.contains(serialNumber))
        #expect(first.fingerprint.count == 64)
    }

    @Test func differentSerialNumbersProduceDifferentExactReferences() {
        let first = makeIdentity(serialNumber: "first").reference
        let second = makeIdentity(serialNumber: "second").reference

        #expect(first != second)
        #expect(!first.matches(second))
    }

    @Test func modelFamilyMatchesSameHardwareWithoutDependingOnDisplayName() {
        let stored = KeyboardDeviceReference(
            fingerprint: "stored-family",
            vendorID: 1204,
            productID: 4621,
            transport: "usb",
            displayName: "Office Keyboard",
            matchStrength: .modelFamily
        )
        let connected = KeyboardDeviceReference(
            fingerprint: "new-session-family",
            vendorID: 1204,
            productID: 4621,
            transport: "USB",
            displayName: "Renamed Keyboard",
            matchStrength: .modelFamily
        )

        #expect(stored.matches(connected))
    }

    @Test func modelFamilyRejectsDifferentProduct() {
        let first = makeIdentity(serialNumber: nil).reference
        let second = KeyboardDeviceIdentity(
            vendorID: 1204,
            productID: 9999,
            transport: "USB",
            productName: "Another Keyboard",
            serialNumber: nil,
            isBuiltIn: false
        ).reference

        #expect(!first.matches(second))
    }

    @Test func builtInKeyboardUsesStableReferenceIndependentOfDisplayName() {
        let first = KeyboardDeviceIdentity(
            vendorID: 1452,
            productID: 834,
            transport: "SPI",
            productName: "Apple Internal Keyboard / Trackpad",
            serialNumber: "ignored-first",
            isBuiltIn: true
        ).reference
        let second = KeyboardDeviceIdentity(
            vendorID: nil,
            productID: nil,
            transport: nil,
            productName: "Built-in Keyboard",
            serialNumber: "ignored-second",
            isBuiltIn: true
        ).reference

        #expect(first.matches(second))
        #expect(first.matchStrength == .builtIn)
        #expect(second.matchStrength == .builtIn)
    }

    private func makeIdentity(serialNumber: String?) -> KeyboardDeviceIdentity {
        KeyboardDeviceIdentity(
            vendorID: 1204,
            productID: 4621,
            transport: "USB",
            productName: "Majestouch Convertible 2",
            serialNumber: serialNumber,
            isBuiltIn: false
        )
    }
}

struct KeyboardDeviceVerificationPolicyTests {
    @Test func bluetoothKeyboardRequiresConnectionVerification() {
        let reference = makeReference(transport: "Bluetooth")

        #expect(KeyboardDeviceVerificationPolicy.availability(for: reference) == .requiresVerification)
    }

    @Test func usbAndBuiltInKeyboardsRemainImmediatelyAvailable() {
        let usb = makeReference(transport: "USB")
        let builtIn = KeyboardDeviceIdentity(
            vendorID: nil,
            productID: nil,
            transport: nil,
            productName: "Built-in Keyboard",
            serialNumber: nil,
            isBuiltIn: true
        ).reference

        #expect(KeyboardDeviceVerificationPolicy.availability(for: usb) == .supported)
        #expect(KeyboardDeviceVerificationPolicy.availability(for: builtIn) == .supported)
    }

    @Test func unknownTransportRemainsUnavailable() {
        let reference = makeReference(transport: "Virtual")

        #expect(KeyboardDeviceVerificationPolicy.availability(for: reference) == .unsupportedTransport)
    }

    @Test func onlyInitialKeyDownFromSelectedConnectionCompletesVerification() {
        let selectedSourceID = UUID()

        #expect(
            KeyboardDeviceVerificationPolicy.accepts(
                sourceID: selectedSourceID,
                transition: .keyDown,
                selectedSourceID: selectedSourceID
            )
        )
        #expect(
            !KeyboardDeviceVerificationPolicy.accepts(
                sourceID: UUID(),
                transition: .keyDown,
                selectedSourceID: selectedSourceID
            )
        )
        #expect(
            !KeyboardDeviceVerificationPolicy.accepts(
                sourceID: selectedSourceID,
                transition: .repeatKeyDown,
                selectedSourceID: selectedSourceID
            )
        )
        #expect(
            !KeyboardDeviceVerificationPolicy.accepts(
                sourceID: selectedSourceID,
                transition: .keyUp,
                selectedSourceID: selectedSourceID
            )
        )
    }

    @Test @MainActor func disconnectStopsActiveVerification() {
        let verifier = KeyboardDeviceVerificationModel()
        verifier.start(
            selectedSourceID: UUID(),
            attributionBroker: KeyboardEventAttributionBroker(),
            timeoutNanoseconds: 1_000_000_000
        )

        verifier.markDisconnected()

        #expect(verifier.state == .disconnected)
    }

    @Test @MainActor func timeoutEndsVerificationWithRetryableState() async throws {
        let verifier = KeyboardDeviceVerificationModel()
        verifier.start(
            selectedSourceID: UUID(),
            attributionBroker: KeyboardEventAttributionBroker(),
            timeoutNanoseconds: 1_000_000
        )

        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(verifier.state == .timedOut)
    }

    @Test @MainActor func cancelReturnsVerificationToIdle() {
        let verifier = KeyboardDeviceVerificationModel()
        verifier.start(
            selectedSourceID: UUID(),
            attributionBroker: KeyboardEventAttributionBroker()
        )

        verifier.cancel()

        #expect(verifier.state == .idle)
    }

    @Test @MainActor func completedBluetoothVerificationSurvivesCompetingRecorderCancellation() async throws {
        let verifier = KeyboardDeviceVerificationModel()
        let broker = KeyboardEventAttributionBroker()
        let selectedSourceID = UUID()
        let token = ShortcutEventToken(
            eventTimestamp: 99,
            keyCode: 0,
            transition: .keyDown
        )
        verifier.start(
            selectedSourceID: selectedSourceID,
            attributionBroker: broker
        )

        let shouldConsumeKey = verifier.handleVerificationKeyDown(token: token, isRepeat: false)
        await Task.yield()
        broker.observe(
            KeyboardInputEvent(
                sourceID: selectedSourceID,
                device: makeReference(transport: "Bluetooth"),
                usage: 0x04,
                suggestedCarbonKeyCode: 0,
                transition: .keyDown,
                timestamp: 100,
                observedAtNanoseconds: DispatchTime.now().uptimeNanoseconds,
                pressedUsages: [],
                modifierUsages: []
            )
        )
        try await waitUntilState(.verified, in: verifier)

        #expect(shouldConsumeKey)
        #expect(verifier.state == .verified)

        verifier.cancel()

        #expect(verifier.state == .verified)
    }

    @Test @MainActor func keyFromDifferentConnectionReportsDetectedDevice() async throws {
        let verifier = KeyboardDeviceVerificationModel()
        let broker = KeyboardEventAttributionBroker()
        let selectedSourceID = UUID()
        let token = ShortcutEventToken(
            eventTimestamp: 99,
            keyCode: 0,
            transition: .keyDown
        )
        verifier.start(
            selectedSourceID: selectedSourceID,
            attributionBroker: broker
        )

        let shouldConsumeKey = verifier.handleVerificationKeyDown(token: token, isRepeat: false)
        await Task.yield()
        broker.observe(
            KeyboardInputEvent(
                sourceID: UUID(),
                device: KeyboardDeviceIdentity(
                    vendorID: 0x5321,
                    productID: 0x000A,
                    transport: "USB",
                    productName: "Tree80",
                    serialNumber: nil,
                    isBuiltIn: false
                ).reference,
                usage: 0x04,
                suggestedCarbonKeyCode: 0,
                transition: .keyDown,
                timestamp: 100,
                observedAtNanoseconds: DispatchTime.now().uptimeNanoseconds,
                pressedUsages: [],
                modifierUsages: []
            )
        )
        try await waitUntilState(
            .differentDevice(displayName: "Tree80", transport: "usb"),
            in: verifier
        )

        #expect(shouldConsumeKey)
        #expect(verifier.state == .differentDevice(displayName: "Tree80", transport: "usb"))
    }

    @MainActor
    private func waitUntilState(
        _ expectedState: KeyboardDeviceVerificationModel.State,
        in verifier: KeyboardDeviceVerificationModel
    ) async throws {
        for _ in 0..<100 {
            if verifier.state == expectedState {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func makeReference(transport: String) -> KeyboardDeviceReference {
        KeyboardDeviceIdentity(
            vendorID: 1204,
            productID: 4621,
            transport: transport,
            productName: "Test Keyboard",
            serialNumber: nil,
            isBuiltIn: false
        ).reference
    }
}

struct KeyboardDeviceMonitoringPolicyTests {
    @Test func activeDeviceConfigurationKeepsMonitoringBeforeBindingIsSaved() {
        #expect(
            KeyboardDeviceMonitoringPolicy.shouldMonitor(
                hasDeviceBinding: false,
                activeConfigurationCount: 1,
                hasInputMonitoringPermission: true
            )
        )
    }

    @Test func savedDeviceBindingKeepsMonitoringWithoutActiveConfiguration() {
        #expect(
            KeyboardDeviceMonitoringPolicy.shouldMonitor(
                hasDeviceBinding: true,
                activeConfigurationCount: 0,
                hasInputMonitoringPermission: true
            )
        )
    }

    @Test func monitoringStopsWhenNoBindingOrConfigurationNeedsIt() {
        #expect(
            !KeyboardDeviceMonitoringPolicy.shouldMonitor(
                hasDeviceBinding: false,
                activeConfigurationCount: 0,
                hasInputMonitoringPermission: true
            )
        )
    }

    @Test func permissionIsRequiredDuringActiveConfiguration() {
        #expect(
            !KeyboardDeviceMonitoringPolicy.shouldMonitor(
                hasDeviceBinding: false,
                activeConfigurationCount: 1,
                hasInputMonitoringPermission: false
            )
        )
    }
}
