import CryptoKit
import Foundation

struct KeyboardDeviceReference: Codable, Equatable, Hashable, Sendable {
    enum MatchStrength: String, Codable, Sendable {
        case exact
        case modelFamily
        case builtIn
    }

    let fingerprint: String
    let vendorID: Int?
    let productID: Int?
    let transport: String?
    let displayName: String
    let matchStrength: MatchStrength

    func matches(_ connectedDevice: Self) -> Bool {
        switch matchStrength {
        case .builtIn:
            return connectedDevice.matchStrength == .builtIn
        case .exact:
            return connectedDevice.matchStrength == .exact
                && fingerprint == connectedDevice.fingerprint
        case .modelFamily:
            return connectedDevice.matchStrength != .builtIn
                && hasSameModel(as: connectedDevice)
        }
    }

    func overlaps(_ other: Self) -> Bool {
        if matchStrength == .builtIn || other.matchStrength == .builtIn {
            return matchStrength == .builtIn && other.matchStrength == .builtIn
        }

        if matchStrength == .exact && other.matchStrength == .exact {
            return fingerprint == other.fingerprint
        }

        return hasSameModel(as: other)
    }

    private func hasSameModel(as other: Self) -> Bool {
        vendorID == other.vendorID
            && productID == other.productID
            && normalizedTransport == other.normalizedTransport
    }

    private var normalizedTransport: String? {
        transport?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct KeyboardDeviceIdentity: Sendable {
    let reference: KeyboardDeviceReference

    init(
        vendorID: Int?,
        productID: Int?,
        transport: String?,
        productName: String,
        serialNumber: String?,
        isBuiltIn: Bool
    ) {
        let normalizedName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = normalizedName.isEmpty ? "Keyboard" : normalizedName

        if isBuiltIn {
            reference = KeyboardDeviceReference(
                fingerprint: Self.fingerprint(for: ["built-in-keyboard"]),
                vendorID: nil,
                productID: nil,
                transport: nil,
                displayName: displayName,
                matchStrength: .builtIn
            )
            return
        }

        let normalizedTransport = transport?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedSerial = serialNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedSerial, !normalizedSerial.isEmpty {
            reference = KeyboardDeviceReference(
                fingerprint: Self.fingerprint(
                    for: [
                        "exact-v1",
                        String(vendorID ?? -1),
                        String(productID ?? -1),
                        normalizedTransport ?? "unknown",
                        normalizedSerial,
                    ]
                ),
                vendorID: vendorID,
                productID: productID,
                transport: normalizedTransport,
                displayName: displayName,
                matchStrength: .exact
            )
        } else {
            reference = KeyboardDeviceReference(
                fingerprint: Self.fingerprint(
                    for: [
                        "model-family-v1",
                        String(vendorID ?? -1),
                        String(productID ?? -1),
                        normalizedTransport ?? "unknown",
                        normalizedName.lowercased(),
                    ]
                ),
                vendorID: vendorID,
                productID: productID,
                transport: normalizedTransport,
                displayName: displayName,
                matchStrength: .modelFamily
            )
        }
    }

    private static func fingerprint(for components: [String]) -> String {
        let digest = SHA256.hash(data: Data(components.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
