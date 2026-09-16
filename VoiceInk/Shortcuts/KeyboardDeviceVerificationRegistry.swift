import Foundation

/// Ephemeral proof that an ambiguous keyboard was verified during its current IOHID connection.
final class KeyboardDeviceVerificationRegistry: @unchecked Sendable {
    static let shared = KeyboardDeviceVerificationRegistry()

    private let lock = NSLock()
    private var verifiedSourceIDs = Set<UUID>()

    private init() {}

    func markVerified(sourceID: UUID) {
        lock.lock()
        verifiedSourceIDs.insert(sourceID)
        lock.unlock()
    }

    func revoke(sourceID: UUID) {
        lock.lock()
        verifiedSourceIDs.remove(sourceID)
        lock.unlock()
    }

    func isVerified(sourceID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return verifiedSourceIDs.contains(sourceID)
    }
}
