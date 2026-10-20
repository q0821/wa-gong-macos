import Foundation
import CryptoKit

struct TranscribeCppModelArtifact: Sendable {
    let modelName: String
    let fileName: String
    let repository: String
    let repositoryRevision: String
    let expectedFileSize: Int64
    let expectedSHA256: String
    let architectureHint: String?
    let maximumChunkSeconds: Int
    let boundarySearchSeconds: Int
    let boundaryEnergyWindowSamples: Int

    var downloadURL: URL {
        URL(
            string: "https://huggingface.co/\(repository)/resolve/\(repositoryRevision)/\(fileName)"
        )!
    }

    var modelDirectory: URL {
        Self.applicationSupportDirectory
            .appendingPathComponent("TranscribeCpp", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)
    }

    var modelFileURL: URL {
        modelDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    var checksumFileURL: URL {
        modelDirectory.appendingPathComponent(".\(fileName).sha256", isDirectory: false)
    }

    var installedModelFileURL: URL? {
        modelFileIsValid(in: modelDirectory) ? modelFileURL : nil
    }

    func modelFileIsValid(in directory: URL) -> Bool {
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        let checksumURL = directory.appendingPathComponent(".\(fileName).sha256", isDirectory: false)

        guard
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let size = values.fileSize,
            Int64(size) == expectedFileSize
        else {
            return false
        }

        let installedChecksum = try? String(contentsOf: checksumURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return installedChecksum == expectedSHA256
    }

    func modelFileIntegrityIsValid(in directory: URL) -> Bool {
        guard modelFileIsValid(in: directory) else { return false }
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        return (try? Self.sha256(of: fileURL)) == expectedSHA256
    }

    func removeInstalledFiles() {
        try? FileManager.default.removeItem(at: modelDirectory)
    }

    private static var applicationSupportDirectory: URL {
        AppIdentity.applicationSupportDirectoryURL
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum TranscribeCppModelCatalog {
    static let tea = TranscribeCppModelArtifact(
        modelName: "tea-asr-1.1-q6-k", fileName: "TEA-ASR-1.1-Q6_K.gguf",
        repository: "mukiwu/TEA-ASR-1.1-transcribe-gguf",
        repositoryRevision: "83f5b0668c4718db9f16e43940c83bef7e61df61",
        expectedFileSize: 1_692_286_464,
        expectedSHA256: "2417fa52d49f852bfc11704190e10ddb681c343a661a3a3d1bb213876c780b68",
        architectureHint: "qwen3_asr", maximumChunkSeconds: 30,
        boundarySearchSeconds: 0, boundaryEnergyWindowSamples: 0
    )

    static let cohereTranscribe = TranscribeCppModelArtifact(
        modelName: "cohere-transcribe",
        fileName: "cohere-transcribe-03-2026-Q4_K_M.gguf",
        repository: "handy-computer/cohere-transcribe-03-2026-gguf",
        repositoryRevision: "dfa4adebb64f3076b7b6b90b721275cc069cb421",
        expectedFileSize: 1_558_162_944,
        expectedSHA256: "0ea56826d8bd5d74b7143a4a04e022dc1bb75452cfae49d98b6acb0c1d16a1fb",
        architectureHint: "cohere",
        maximumChunkSeconds: 35,
        boundarySearchSeconds: 5,
        boundaryEnergyWindowSamples: 1_600
    )

    private static let artifactsByModelName = [
        cohereTranscribe.modelName: cohereTranscribe,
        tea.modelName: tea
    ]

    static func artifact(for modelName: String) -> TranscribeCppModelArtifact? {
        artifactsByModelName[modelName]
    }
}
