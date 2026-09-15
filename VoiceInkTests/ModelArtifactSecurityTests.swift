import Testing
import CryptoKit
import Foundation
@testable import VoiceInk

struct ModelArtifactSecurityTests {
    @Test func rejectsChunkThatWouldExceedExpectedArtifactSize() {
        #expect(BoundedDownloadPolicy.canAccept(currentBytes: 90, incomingBytes: 10, expectedBytes: 100))
        #expect(!BoundedDownloadPolicy.canAccept(currentBytes: 90, incomingBytes: 11, expectedBytes: 100))
        #expect(!BoundedDownloadPolicy.canAccept(currentBytes: -1, incomingBytes: 1, expectedBytes: 100))
    }

    @Test func whisperCatalogPinsRevisionSizeAndSHA256() throws {
        let artifact = try #require(WhisperModelArtifactCatalog.artifact(for: "ggml-base"))

        #expect(artifact.repositoryRevision == "5359861c739e955e79d9a303bcbc70fb988958b1")
        #expect(artifact.modelFile.size == 147_951_465)
        #expect(artifact.modelFile.sha256 == "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe")
        #expect(artifact.modelFile.downloadURL.absoluteString.contains("/5359861c739e955e79d9a303bcbc70fb988958b1/"))
    }

    @Test func whisperLoadBoundaryRejectsSameSizeTampering() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperSecurity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let safeData = Data("safe".utf8)
        let expectedHash = SHA256.hash(data: safeData).map { String(format: "%02x", $0) }.joined()
        let artifact = WhisperRemoteArtifact(
            filename: "model.bin",
            size: 4,
            sha256: expectedHash,
            repositoryRevision: "fixed"
        )
        let modelURL = directory.appendingPathComponent(artifact.filename)
        try safeData.write(to: modelURL)
        #expect(artifact.integrityIsValid(at: modelURL))

        try Data("evil".utf8).write(to: modelURL)
        #expect(!artifact.integrityIsValid(at: modelURL))
    }

    @Test func transcribeCppRejectsSameSizeTamperingDespiteChecksumSidecar() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscribeCppSecurity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let safeData = Data("safe".utf8)
        let expectedHash = SHA256.hash(data: safeData).map { String(format: "%02x", $0) }.joined()
        let artifact = TranscribeCppModelArtifact(
            modelName: "test",
            fileName: "model.gguf",
            repository: "example/model",
            repositoryRevision: "fixed",
            expectedFileSize: 4,
            expectedSHA256: expectedHash,
            architectureHint: nil,
            maximumChunkSeconds: 1,
            boundarySearchSeconds: 1,
            boundaryEnergyWindowSamples: 1
        )
        let modelURL = directory.appendingPathComponent("model.gguf")
        let checksumURL = directory.appendingPathComponent(".model.gguf.sha256")
        try safeData.write(to: modelURL)
        try expectedHash.write(to: checksumURL, atomically: true, encoding: .utf8)
        #expect(artifact.modelFileIntegrityIsValid(in: directory))

        try Data("evil".utf8).write(to: modelURL)
        #expect(!artifact.modelFileIntegrityIsValid(in: directory))
    }

    @Test func refineExecutionBoundaryRejectsSameSizeTampering() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefineSecurity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let safeData = Data("safe".utf8)
        let expectedHash = SHA256.hash(data: safeData).map { String(format: "%02x", $0) }.joined()
        let file = WaGongRefineModelDownloader.ModelFile(path: "model.bin", size: 4, sha256: expectedHash)
        let modelURL = directory.appendingPathComponent(file.path)
        try safeData.write(to: modelURL)
        #expect(WaGongRefineModelDownloader.isSnapshotComplete(at: directory, files: [file]))

        try Data("evil".utf8).write(to: modelURL)
        #expect(!WaGongRefineModelDownloader.snapshotIntegrityIsValid(at: directory, files: [file]))
    }

    @Test func extractedWhisperArchiveRejectsOversizeContentAndSymbolicLinks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperArchiveSecurity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("model.bin")
        try Data("safe".utf8).write(to: fileURL)
        #expect(throws: Error.self) {
            try WhisperModelManager.validateExtractedArchive(
                at: directory,
                maximumEntryCount: 10,
                maximumExpandedBytes: 3
            )
        }

        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: URL(fileURLWithPath: "/tmp"))
        #expect(throws: Error.self) {
            try WhisperModelManager.validateExtractedArchive(
                at: directory,
                maximumEntryCount: 10,
                maximumExpandedBytes: 100
            )
        }
    }
}
