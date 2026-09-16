import Darwin
import Foundation

enum BoundedRegularFileReader {
    enum ReadError: Error {
        case invalidFile
        case invalidSize
        case fileChangedDuringRead
    }

    static func load(_ url: URL, maximumBytes: Int, minimumBytes: Int = 1) throws -> Data {
        guard url.isFileURL, maximumBytes >= minimumBytes, minimumBytes >= 0 else {
            throw ReadError.invalidFile
        }

        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ReadError.invalidFile }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var status = stat()
        guard fstat(descriptor, &status) == 0,
            (status.st_mode & S_IFMT) == S_IFREG,
            status.st_size >= minimumBytes,
            status.st_size <= maximumBytes
        else {
            throw ReadError.invalidSize
        }

        let expectedSize = Int(status.st_size)
        var result = Data()
        result.reserveCapacity(expectedSize)
        while result.count <= maximumBytes {
            let remainingAllowance = maximumBytes - result.count
            let chunk = try handle.read(upToCount: min(1_048_576, remainingAllowance + 1)) ?? Data()
            if chunk.isEmpty { break }
            result.append(chunk)
        }
        guard result.count == expectedSize else {
            throw ReadError.fileChangedDuringRead
        }
        return result
    }
}
