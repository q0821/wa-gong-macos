import Foundation

struct AudioFileDeletionPolicy {
    let recordingsDirectory: URL

    init(recordingsDirectory: URL) {
        self.recordingsDirectory = recordingsDirectory.standardizedFileURL.resolvingSymlinksInPath()
    }

    func safeAudioURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string) else { return nil }
        return safeAudioURL(url)
    }

    func safeAudioURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let standardized = url.standardizedFileURL
        guard standardized.deletingLastPathComponent() == recordingsDirectory,
              standardized.pathExtension.lowercased() == "wav",
              let values = try? standardized.resourceValues(
                  forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              standardized.resolvingSymlinksInPath() == standardized else { return nil }
        return standardized
    }
}
