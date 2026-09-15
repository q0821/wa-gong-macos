import Foundation

enum BoundedDownloadPolicy {
    static func canAccept(currentBytes: Int64, incomingBytes: Int, expectedBytes: Int64) -> Bool {
        guard currentBytes >= 0, incomingBytes >= 0, expectedBytes >= 0 else { return false }
        let (nextBytes, overflow) = currentBytes.addingReportingOverflow(Int64(incomingBytes))
        return !overflow && nextBytes <= expectedBytes
    }
}
