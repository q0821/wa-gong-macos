import Foundation

enum AudioUploadPolicy {
    static let maximumFileBytes = 500_000_000

    static func load(_ url: URL) throws -> Data {
        do {
            return try BoundedRegularFileReader.load(url, maximumBytes: maximumFileBytes)
        } catch {
            throw CloudTranscriptionError.audioFileNotFound
        }
    }
}
