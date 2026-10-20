import Foundation
import Testing
@testable import VoiceInk

struct TEAWorkerContractTests {
    @Test func framesRoundTripWithoutWritingTranscriptToMetadata() throws {
        let pipe = Pipe()
        let request = TEAWorkerWire.Message(kind: "load", id: UUID(), generation: UUID(), modelPath: "/model.gguf")
        try pipe.fileHandleForWriting.write(contentsOf: TEAWorkerWire.encode(request))
        try pipe.fileHandleForWriting.close()
        let decoded = try TEAWorkerWire.read(from: pipe.fileHandleForReading)
        #expect(decoded.id == request.id)
        #expect(decoded.generation == request.generation)
        #expect(decoded.version == 1)
        #expect(decoded.text == nil)
        try pipe.fileHandleForReading.close()
    }

    @Test(arguments: [Data([0, 0, 0, 0]), Data([255, 255, 255, 255]), Data([0, 0, 0, 5, 123])])
    func malformedOrIncompleteFramesFail(data: Data) throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: data)
        try pipe.fileHandleForWriting.close()
        #expect(throws: (any Error).self) { try TEAWorkerWire.read(from: pipe.fileHandleForReading) }
        try pipe.fileHandleForReading.close()
    }

    @Test func incompatibleProtocolFails() throws {
        let pipe = Pipe()
        var request = TEAWorkerWire.Message(kind: "load", id: UUID(), generation: UUID())
        request.version = 99
        try pipe.fileHandleForWriting.write(contentsOf: TEAWorkerWire.encode(request))
        try pipe.fileHandleForWriting.close()
        #expect(throws: TEAWorkerWire.Failure.incompatibleVersion) { try TEAWorkerWire.read(from: pipe.fileHandleForReading) }
        try pipe.fileHandleForReading.close()
    }

    @Test func audioBoundariesAndInvalidSamplesFailClosed() throws {
        let allowed = [Float](repeating: 0, count: 30 * 16_000)
        #expect(try TEAWorkerWire.samples(from: allowed.withUnsafeBytes { Data($0) }).count == 480_000)
        for invalid in [[Float](), [Float.nan], [Float.infinity], [Float(1.01)],
                        [Float](repeating: 0, count: 480_001)] {
            let bytes = invalid.withUnsafeBytes { Data($0) }
            #expect(throws: TEAWorkerWire.Failure.invalidAudio) { try TEAWorkerWire.samples(from: bytes) }
        }
        #expect(throws: TEAWorkerWire.Failure.invalidAudio) { try TEAWorkerWire.samples(from: Data([0])) }
    }

    @Test func teaHasDistinctIdentityAndHonestAttribution() throws {
        let artifact = TranscribeCppModelCatalog.tea
        #expect(artifact.expectedFileSize == 1_692_286_464)
        #expect(artifact.repository == "mukiwu/TEA-ASR-1.1-transcribe-gguf")
        #expect(artifact.repositoryRevision == "83f5b0668c4718db9f16e43940c83bef7e61df61")
        #expect(artifact.expectedSHA256 == "2417fa52d49f852bfc11704190e10ddb681c343a661a3a3d1bb213876c780b68")
        let model = TranscriptionModelRegistry.teaModel
        #expect(model.displayName == "TEA-ASR 1.1")
        #expect(model.speed == nil && model.accuracy == nil && model.ramUsage == nil)
        #expect(model.name != "tea-gguf")
        #expect(model.provider == .transcribeCpp)
        #expect(!model.supportsStreaming)
        #expect(model.supportedLanguages.keys.sorted() == ["auto", "en", "zh"])
        #expect(TranscribeCppModelCatalog.artifact(for: "cohere-transcribe") != nil)
    }

    @Test(arguments: ["http://huggingface.co/file", "https://127.0.0.1/file", "https://huggingface.co.attacker.test/file",
                      "https://user:password@huggingface.co/file", "https://huggingface.co:444/file"])
    func downloadsRejectUnexpectedDestinations(url: String) throws {
        #expect(!TEAModelInstaller.isAllowedDownloadURL(try #require(URL(string: url))))
    }

    @Test func fixedDownloadAndCDNAreAllowed() {
        #expect(TEAModelInstaller.isAllowedDownloadURL(TranscribeCppModelCatalog.tea.downloadURL))
        #expect(TEAModelInstaller.isAllowedDownloadURL(URL(string: "https://cas-bridge.xethub.hf.co/model")!))
    }

    @Test func missingOrSymlinkModelsAreNeverAccepted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("wrong.gguf")
        try Data([1, 2, 3]).write(to: file)
        #expect(throws: (any Error).self) { try TEAModelInstaller.validate(file) }
        let link = directory.appendingPathComponent("link.gguf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: (any Error).self) { try TEAModelInstaller.validate(link) }
    }
}
