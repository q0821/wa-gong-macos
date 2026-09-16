import CryptoKit
import Foundation

enum ModeCustomCommandApprovalStore {
    private static let keyPrefix = "ModeCustomCommandApproval.v1."

    static func approve(_ mode: ModeConfig) -> Bool {
        guard mode.outputMode == .customCommand else {
            revoke(modeID: mode.id)
            return true
        }
        guard let command = mode.customCommand?.trimmedCommand else { return false }
        return KeychainService.shared.save(
            digest(modeID: mode.id, command: command),
            forKey: key(modeID: mode.id),
            syncable: false,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
    }

    static func isApproved(_ mode: ModeConfig) -> Bool {
        guard mode.outputMode == .customCommand,
              let command = mode.customCommand?.trimmedCommand,
              let stored = KeychainService.shared.getString(
                  forKey: key(modeID: mode.id),
                  syncable: false
              ) else {
            return false
        }
        return stored == digest(modeID: mode.id, command: command)
    }

    @discardableResult
    static func revoke(modeID: UUID) -> Bool {
        KeychainService.shared.delete(forKey: key(modeID: modeID), syncable: false)
    }

    static func digest(modeID: UUID, command: String) -> String {
        let payload = Data("v1\u{0}\(modeID.uuidString.lowercased())\u{0}\(command)".utf8)
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    private static func key(modeID: UUID) -> String {
        keyPrefix + modeID.uuidString.lowercased()
    }
}
