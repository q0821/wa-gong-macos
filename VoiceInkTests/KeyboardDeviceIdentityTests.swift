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
