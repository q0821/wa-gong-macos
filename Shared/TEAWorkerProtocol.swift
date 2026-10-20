import Foundation

enum TEAWorkerWire {
    static let version = 1
    static let maximumFrameBytes = 3_000_000
    static let maximumSamples = 30 * 16_000

    struct Message: Codable, Sendable {
        var version = TEAWorkerWire.version
        var kind: String
        var id: UUID
        var generation: UUID
        var modelPath: String? = nil
        var language: String? = nil
        var pcm: Data? = nil
        var text: String? = nil
        var seconds: Double? = nil
    }

    enum Failure: Error { case invalidFrame, incompatibleVersion, invalidAudio }

    static func encode(_ message: Message) throws -> Data {
        let body = try JSONEncoder().encode(message)
        guard !body.isEmpty, body.count <= maximumFrameBytes else { throw Failure.invalidFrame }
        var length = UInt32(body.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(body)
        return frame
    }

    static func read(from handle: FileHandle) throws -> Message {
        let header = try readExactly(4, from: handle)
        let count = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard count > 0, count <= maximumFrameBytes else { throw Failure.invalidFrame }
        let message = try JSONDecoder().decode(Message.self, from: readExactly(Int(count), from: handle))
        guard message.version == version else { throw Failure.incompatibleVersion }
        return message
    }

    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let part = try handle.read(upToCount: count - result.count), !part.isEmpty else {
                throw Failure.invalidFrame
            }
            result.append(part)
        }
        return result
    }

    static func samples(from data: Data) throws -> [Float] {
        guard !data.isEmpty, data.count % 4 == 0, data.count <= maximumSamples * 4 else {
            throw Failure.invalidAudio
        }
        var samples = [Float](repeating: 0, count: data.count / 4)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        guard samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else { throw Failure.invalidAudio }
        return samples
    }
}
