import Foundation
import CryptoKit
import Darwin

enum TEAModelInstaller {
    static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host == "huggingface.co" || host == "cdn-lfs.huggingface.co" ||
            host == "cdn-lfs.hf.co" || host == "cas-bridge.xethub.hf.co" ||
            host == "us.aws.cdn.hf.co" || host == "eu.aws.cdn.hf.co"
    }

    static func validate(_ url: URL) throws {
        let artifact = TranscribeCppModelCatalog.tea
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              attributes.fileSize.map(Int64.init) == artifact.expectedFileSize else { throw TEARuntimeError.invalidModel }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            sha.update(data: data)
        }
        guard sha.finalize().map({ String(format: "%02x", $0) }).joined() == artifact.expectedSHA256 else {
            throw TEARuntimeError.invalidModel
        }
    }

    static func install(source: URL?, progress: @escaping @Sendable (Double) -> Void) async throws {
        let artifact = TranscribeCppModelCatalog.tea
        let manager = FileManager.default
        try manager.createDirectory(at: artifact.modelDirectory, withIntermediateDirectories: true)
        // Refuse redirected Application Support/model directories, not just symlink files.
        guard artifact.modelDirectory.resolvingSymlinksInPath().standardizedFileURL == artifact.modelDirectory.standardizedFileURL else {
            throw TEARuntimeError.invalidModel
        }
        let capacity = try artifact.modelDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = capacity.volumeAvailableCapacityForImportantUsage,
              free >= artifact.expectedFileSize + 3 * 1_024 * 1_024 * 1_024 else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let staging = artifact.modelDirectory.appendingPathComponent(".tea-install-\(UUID().uuidString).partial")
        defer { try? manager.removeItem(at: staging) } // Only this operation's staging file.
        if let source {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try await Task.detached(priority: .utility) {
                try validate(source)
                try Task.checkCancellation()
                try manager.copyItem(at: source, to: staging)
            }.value
        } else {
            let delegate = TEAModelDownloadDelegate(progress: progress)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 1800
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (temporary, response) = try await session.download(from: artifact.downloadURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let finalURL = response.url, isAllowedDownloadURL(finalURL) else { throw TEARuntimeError.invalidModel }
            try manager.moveItem(at: temporary, to: staging)
        }
        try Task.checkCancellation()
        try await Task.detached(priority: .utility) { try validate(staging) }.value
        try Task.checkCancellation()
        // Atomic replacement within one directory, after validating the entire staged file.
        // Preserve the old file if any check above fails.
        guard !artifact.modelFileURL.isSymbolicLinkFile, !artifact.checksumFileURL.isSymbolicLinkFile else {
            throw TEARuntimeError.invalidModel
        }
        try artifact.expectedSHA256.write(to: artifact.checksumFileURL, atomically: true, encoding: .utf8)
        guard Darwin.rename(staging.path, artifact.modelFileURL.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        progress(1)
    }
}

private extension URL {
    var isSymbolicLinkFile: Bool { (try? resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true }
}

private final class TEAModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { TEAModelInstaller.isAllowedDownloadURL($0) ? request : nil })
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let limit = TranscribeCppModelCatalog.tea.expectedFileSize
        guard totalBytesWritten <= limit, totalBytesExpectedToWrite <= limit else { downloadTask.cancel(); return }
        progress(min(0.99, Double(totalBytesWritten) / Double(limit)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
